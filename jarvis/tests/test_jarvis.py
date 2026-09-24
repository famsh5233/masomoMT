from __future__ import annotations

import json
from dataclasses import replace
from datetime import timedelta

import httpx
import pytest
from fastapi.testclient import TestClient

from jarvis.agents.analyst import compute_metrics
from jarvis.agents.content import LessonAgent
from jarvis.agents.growth import GrowthAgent
from jarvis.config import Settings
from jarvis.db import DB, utcnow
from jarvis.llm import FakeLLM
from jarvis.payments.azampay import AzamPay, PaymentError, normalize_tz_msisdn
from jarvis.payments.play import PlayError, PlayVerifier, parse_rfc3339
from jarvis.plans import PLANS
from jarvis.server import build_services, create_app


def tutor_resp(messages):
    return {"reply": "Nice! What do you do at work?", "corrected": "I am working in a hotel.",
            "mistakes": [{"wrong": "I working", "right": "I am working", "why": "Tumia 'am' kabla ya -ing."}],
            "tip": "Umefanya vizuri!", "score": 72, "level": "A2"}


def support_resp(messages):
    text = messages[-1]["content"]
    paid_issue = "nimelipa" in text.lower()
    return {"reply": "Tunashughulikia.", "escalate": paid_issue,
            "reason": "paid but not active" if paid_issue else ""}


def lesson_resp(messages):
    return {"title": "Hello", "objectives": ["a", "b", "c"],
            "vocabulary": [{"word": f"w{i}", "meaning": "m", "example": "e"} for i in range(10)],
            "phrases": [{"english": "Hi", "meaning": "Habari"}] * 6,
            "dialogue": [{"speaker": "A", "line": "Hi"}] * 8,
            "grammar": {"point": "to be", "explanation": "x", "examples": ["a", "b", "c"]},
            "speaking_tasks": ["a", "b", "c"],
            "quiz": [{"question": "q", "options": ["a", "b", "c"], "answer_index": 1}] * 5}


def growth_resp(messages):
    return {"posts": [{"day": 1, "channel": "tiktok", "format": "30s", "hook": "Usiseme hivi!",
                       "script": "...", "caption": "c", "hashtags": ["#kiingereza"], "cta": "Pakua"}],
            "ads": [{"platform": "meta", "headline": "h", "primary_text": "p", "angle": "job"}] * 3}


FAKE = {"tutor_turn": tutor_resp, "support_reply": support_resp, "lesson": lesson_resp,
        "content_calendar": growth_resp}


@pytest.fixture
def settings(tmp_path):
    return replace(Settings(), db_path=str(tmp_path / "t.db"), content_dir=str(tmp_path / "content"),
                   admin_key="adm", azampay_callback_secret="cbsecret", azampay_app_name="app",
                   azampay_client_id="id", azampay_client_secret="sec", azampay_api_key="k",
                   free_turns_per_day=2, paid_turns_per_day=5, env="dev", sms_provider="console")


@pytest.fixture
def client(settings):
    svc = build_services(settings, llm=FakeLLM(FAKE))
    return TestClient(create_app(svc)), svc


def signup(c, phone="255754000001"):
    r = c.post("/v1/auth/start", json={"phone": phone})
    assert r.status_code == 200, r.text
    r = c.post("/v1/auth/verify", json={"phone": phone, "code": r.json()["dev_code"], "name": "Asha"})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['token']}"}


def test_tutor_free_limit_then_upgrade(client):
    c, svc = client
    h = signup(c)
    for left in (1, 0):
        r = c.post("/v1/tutor/chat", json={"message": "i working in hotel"}, headers=h)
        assert r.status_code == 200
        assert r.json()["turns_left"] == left
    r = c.post("/v1/tutor/chat", json={"message": "hello"}, headers=h)
    assert r.status_code == 429 and r.json()["detail"]["upgrade"] is True
    uid = svc.db.user_by_phone("255754000001")["id"]
    plan = PLANS["tz_week"]
    svc.db.grant(uid, plan.code, plan.channel, plan.days, "manual:1", plan.usd_net_monthly)
    assert c.get("/v1/me", headers=h).json()["turns_left_today"] == 3


def test_history_is_sent_to_model(client):
    c, svc = client
    h = signup(c)
    c.post("/v1/tutor/chat", json={"message": "first"}, headers=h)
    c.post("/v1/tutor/chat", json={"message": "second"}, headers=h)
    msgs = svc.llm.calls[-1]["messages"]
    assert [m["role"] for m in msgs] == ["user", "assistant", "user"]
    assert msgs[-1]["content"] == "second"


def test_auth_required(client):
    c, _ = client
    assert c.post("/v1/tutor/chat", json={"message": "x"}).status_code == 401
    assert c.get("/v1/admin/report").status_code == 403


def test_lessons_paywall(client, settings):
    c, svc = client
    h = signup(c)
    agent = LessonAgent(svc.llm, settings)
    agent.generate_and_save(1)
    agent.generate_and_save(2)
    assert c.get("/v1/lessons/1", headers=h).json()["theme"]
    assert c.get("/v1/lessons/2", headers=h).status_code == 402


def test_growth_calendar_files(settings, tmp_path):
    agent = GrowthAgent(FakeLLM(FAKE), settings)
    md, csv_path = agent.save(agent.plan(1), str(tmp_path / "mk"))
    assert "Usiseme hivi!" in md.read_text() and csv_path.exists()


def test_msisdn():
    assert normalize_tz_msisdn("0754 123 456") == "255754123456"
    assert normalize_tz_msisdn("+255 712 345 678") == "255712345678"
    with pytest.raises(PaymentError):
        normalize_tz_msisdn("12345")


def azampay_with(settings, db, handler):
    return AzamPay(settings, db, http=httpx.Client(transport=httpx.MockTransport(handler)))


def ok_handler(request: httpx.Request):
    if request.url.path.endswith("GenerateToken"):
        return httpx.Response(200, json={"data": {"accessToken": "tok"}, "success": True})
    body = json.loads(request.content)
    assert request.headers["Authorization"] == "Bearer tok"
    assert body["amount"] in ("7000", "2000") and body["provider"] == "Mpesa" and body["accountNumber"] == "255754000001"
    return httpx.Response(200, json={"success": True, "transactionId": "AZ1", "message": "ok"})


def test_azampay_full_flow(settings):
    db = DB(settings.db_path)
    uid, _ = db.create_user("255754000001")
    az = azampay_with(settings, db, ok_handler)
    start = az.start_checkout(uid, "tz_month", "mpesa", "0754000001")
    ref = start["external_id"]
    assert db.payment(ref)["provider_ref"] == "AZ1"
    cb = {"utilityref": ref, "amount": "7000", "transactionstatus": "success", "reference": "MP123",
          "msisdn": "255754000001", "operator": "Mpesa", "message": "ok"}
    assert az.handle_callback(cb, "wrong")["status"] == "unauthorized"
    assert az.handle_callback(cb, "cbsecret")["status"] == "success"
    assert az.handle_callback(cb, "cbsecret")["status"] == "already_processed"
    sub = db.active_subscription(uid)
    assert sub["plan"] == "tz_month"
    assert len(db.subscriptions()) == 1


def test_azampay_amount_mismatch_and_failure(settings):
    db = DB(settings.db_path)
    uid, _ = db.create_user("255754000001")
    az = azampay_with(settings, db, ok_handler)
    ref = az.start_checkout(uid, "tz_month", "mpesa", "0754000001")["external_id"]
    r = az.handle_callback({"utilityref": ref, "amount": "100", "transactionstatus": "success"}, "cbsecret")
    assert r["status"] == "amount_mismatch" and db.active_subscription(uid) is None
    assert len(db.open_escalations()) == 1
    ref2 = az.start_checkout(uid, "tz_week", "mpesa", "0754000001")["external_id"]
    r = az.handle_callback({"utilityref": ref2, "amount": "2000", "transactionstatus": "failure"}, "cbsecret")
    assert r["status"] == "failed" and db.payment(ref2)["status"] == "failed"


def test_azampay_rejected_checkout_marks_failed(settings):
    db = DB(settings.db_path)
    uid, _ = db.create_user("255754000001")

    def handler(request):
        if request.url.path.endswith("GenerateToken"):
            return httpx.Response(200, json={"data": {"accessToken": "tok"}})
        return httpx.Response(400, json={"success": False, "message": "bad"})

    with pytest.raises(PaymentError):
        azampay_with(settings, db, handler).start_checkout(uid, "tz_week", "airtel", "0784000001")


def test_mobile_money_purchases_stack(settings):
    db = DB(settings.db_path)
    uid, _ = db.create_user("255754000001")
    p = PLANS["tz_week"]
    a = db.grant(uid, p.code, p.channel, p.days, "r1", p.usd_net_monthly)
    b = db.grant(uid, p.code, p.channel, p.days, "r2", p.usd_net_monthly)
    assert b["starts_at"] == a["expires_at"]


class FakeResp:
    def __init__(self, status, data=None):
        self.status_code, self._data, self.text = status, data or {}, json.dumps(data or {})

    def json(self):
        return self._data


class FakeSession:
    def __init__(self, data):
        self.data, self.posts = data, []

    def get(self, url):
        return FakeResp(200, self.data)

    def post(self, url, json=None):
        self.posts.append(url)
        return FakeResp(200)


def test_play_verify_and_acknowledge(settings):
    db = DB(settings.db_path)
    uid, _ = db.create_user("447700900000", country="GB")
    uid2, _ = db.create_user("447700900001", country="GB")
    exp = (utcnow() + timedelta(days=30)).strftime("%Y-%m-%dT%H:%M:%S.123456789Z")
    sess = FakeSession({"subscriptionState": "SUBSCRIPTION_STATE_ACTIVE",
                        "acknowledgementState": "ACKNOWLEDGEMENT_STATE_PENDING",
                        "lineItems": [{"productId": "pro_monthly", "expiryTime": exp}]})
    pv = PlayVerifier(replace(settings, play_package_name="tz.co.masomo"), db, session_factory=lambda s: sess)
    out = pv.verify(uid, "token-abcdefghij")
    assert out["active"] and out["plan"] == "pro_monthly"
    assert sess.posts and sess.posts[0].endswith(":acknowledge")
    with pytest.raises(PlayError):
        pv.verify(uid2, "token-abcdefghij")


def test_parse_rfc3339():
    assert parse_rfc3339("2026-10-24T12:00:00.123456789Z").microsecond == 123456
    assert parse_rfc3339("2026-10-24T12:00:00Z").year == 2026


def test_support_escalates_payment_issue(client):
    c, _ = client
    h = signup(c)
    r = c.post("/v1/support", json={"message": "Nimelipa lakini Pro haijawaka"}, headers=h).json()
    assert r["escalate"] and r["ticket_id"]


def test_metrics_math(settings):
    db = DB(settings.db_path)
    for i in range(3):
        uid, _ = db.create_user(f"25575400000{i}")
        p = PLANS["tz_month"]
        db.grant(uid, p.code, p.channel, p.days, f"r{i}", p.usd_net_monthly)
    m = compute_metrics(db)
    assert m["paying_users"] == 3
    assert m["mrr_usd"] == pytest.approx(3 * PLANS["tz_month"].usd_net_monthly, abs=0.01)
    assert m["paying_users_needed_at_current_arpu"] == 389  # ceil(1000 / 2.5718)


def test_admin_report(client):
    c, _ = client
    r = c.get("/v1/admin/report", headers={"X-Admin-Key": "adm"})
    assert r.status_code == 200 and "mrr_usd" in r.json()["metrics"]


def test_otp_login_flow_and_limits(client):
    c, svc = client
    r = c.post("/v1/auth/start", json={"phone": "0754 000 002"}).json()
    assert r["phone"] == "255754000002" and len(r["dev_code"]) == 6
    assert svc.sms.sent[-1][0] == "255754000002"
    wrong = "000000" if r["dev_code"] != "000000" else "111111"
    assert c.post("/v1/auth/verify", json={"phone": "0754000002", "code": wrong}).status_code == 401
    ok = c.post("/v1/auth/verify", json={"phone": "0754000002", "code": r["dev_code"], "name": "Juma"})
    assert ok.status_code == 200 and ok.json()["is_new"] is True
    # A code works once only.
    assert c.post("/v1/auth/verify", json={"phone": "0754000002", "code": r["dev_code"]}).status_code == 401
    # Logging in again returns the same account with a new token; the old token stops working.
    old = {"Authorization": f"Bearer {ok.json()['token']}"}
    code2 = c.post("/v1/auth/start", json={"phone": "0754000002"}).json()["dev_code"]
    again = c.post("/v1/auth/verify", json={"phone": "0754000002", "code": code2}).json()
    assert again["is_new"] is False and again["user_id"] == ok.json()["user_id"]
    assert c.get("/v1/me", headers=old).status_code == 401
    # Third code in the hour is allowed, the fourth is refused.
    assert c.post("/v1/auth/start", json={"phone": "0754000002"}).status_code == 200
    assert c.post("/v1/auth/start", json={"phone": "0754000002"}).status_code == 429


def test_otp_brute_force_locked(client):
    c, _ = client
    code = c.post("/v1/auth/start", json={"phone": "0754000003"}).json()["dev_code"]
    wrong = "000000" if code != "000000" else "111111"
    for _ in range(5):
        c.post("/v1/auth/verify", json={"phone": "0754000003", "code": wrong})
    assert c.post("/v1/auth/verify", json={"phone": "0754000003", "code": code}).status_code == 401


def test_otp_country_allowlist_and_bad_numbers(client):
    c, _ = client
    r = c.post("/v1/auth/start", json={"phone": "+447700900123", "country": "GB"})
    assert r.status_code == 422 and r.json()["detail"]["code"] == "country_not_supported"
    assert c.post("/v1/auth/start", json={"phone": "12345678"}).status_code == 422


def test_console_sms_refused_in_production(settings):
    svc = build_services(replace(settings, env="prod"), llm=FakeLLM(FAKE))
    c = TestClient(create_app(svc))
    r = c.post("/v1/auth/start", json={"phone": "0754000004"})
    assert r.status_code == 503 and "dev_code" not in r.text


def test_profile_update_and_logout(client):
    c, _ = client
    h = signup(c)
    r = c.patch("/v1/me", json={"name": "Asha M", "level": "B1", "native_lang": "sw"}, headers=h)
    assert r.status_code == 200 and r.json()["level"] == "B1" and r.json()["name"] == "Asha M"
    assert c.patch("/v1/me", json={"level": "Z9"}, headers=h).status_code == 422
    assert c.post("/v1/auth/logout", headers=h).status_code == 200
    assert c.get("/v1/me", headers=h).status_code == 401


def test_seed_lessons_and_index(client):
    c, _ = client
    h = signup(c)
    week1 = c.get("/v1/lessons/1", headers=h).json()
    assert week1["title"] == "Jitambulishe kwa Kiingereza" and len(week1["quiz"]) >= 5
    idx = c.get("/v1/lessons", headers=h).json()["lessons"]
    assert len(idx) == 12 and idx[0]["published"] and idx[1]["published"] and not idx[2]["published"]
    assert idx[0]["locked"] is False and idx[1]["locked"] is True
    assert idx[0]["title"] == "Jitambulishe kwa Kiingereza" and idx[2]["title"] == idx[2]["theme"]


def test_videos_proxy_and_paywall(client):
    c, svc = client
    h = signup(c)
    calls = []

    def handler(request):
        calls.append(str(request.url))
        return httpx.Response(200, json=[{"title": "Greetings", "size": "12MB", "url": "https://cdn.example/v1.mp4"},
                                         {"title": "bad", "url": "javascript:alert(1)"}, "junk"])

    svc.videos.http = httpx.Client(transport=httpx.MockTransport(handler))
    r = c.get("/v1/videos/1", headers=h).json()
    assert r["videos"] == [{"title": "Greetings", "size": "12MB", "url": "https://cdn.example/v1.mp4"}]
    c.get("/v1/videos/1", headers=h)
    assert len(calls) == 1  # cached
    assert c.get("/v1/videos/2", headers=h).status_code == 402
    assert c.get("/v1/videos/99", headers=h).status_code == 404
    weeks = c.get("/v1/videos", headers=h).json()["weeks"]
    assert weeks[0] == {"week": 1, "locked": False} and weeks[1]["locked"] is True

    def down(request):
        return httpx.Response(500)

    svc.videos.http = httpx.Client(transport=httpx.MockTransport(down))
    svc.videos._cache.clear()
    assert c.get("/v1/videos/1", headers=h).status_code == 503


def test_demo_llm_only_in_dev(settings):
    from jarvis.server import make_llm
    with pytest.raises(RuntimeError):
        make_llm(replace(settings, env="prod", llm_mode="demo"))
    svc = build_services(replace(settings, llm_mode="demo"))
    c = TestClient(create_app(svc))
    h = signup(c)
    r = c.post("/v1/tutor/chat", json={"message": "she go to market"}, headers=h).json()
    assert r["corrected"] == "she goes to market" and r["mistakes"][0]["right"] == "she goes"


def test_phone_normalization():
    from jarvis.phones import PhoneError, normalize_phone
    assert normalize_phone("0712 345 678") == "255712345678"
    assert normalize_phone("0712345678", "KE") == "254712345678"
    assert normalize_phone("+1 (415) 555-0100", "US") == "14155550100"
    assert normalize_phone("00255712345678") == "255712345678"
    with pytest.raises(PhoneError):
        normalize_phone("abc")


# ---------- regression tests for the security review ----------

def test_otp_parallel_guesses_limited_and_code_single_use(settings):
    import threading
    db = DB(settings.db_path)
    db.otp_issue("255754000010", "123456", 10, 3)
    results = []

    def guess(code):
        results.append(db.otp_check("255754000010", code, 5))

    threads = [threading.Thread(target=guess, args=(f"{i:06d}",)) for i in range(40)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    with db.conn() as c:
        attempts = c.execute("SELECT attempts FROM otps WHERE phone='255754000010'").fetchone()["attempts"]
    assert attempts == 5 and not any(results)

    db.otp_issue("255754000011", "654321", 10, 3)
    results.clear()
    threads = [threading.Thread(target=lambda: results.append(db.otp_check("255754000011", "654321", 5)))
               for _ in range(10)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert results.count(True) == 1


def test_tutor_limit_holds_under_parallel_requests(settings):
    import threading
    import time as _time

    def slow_tutor(messages):
        _time.sleep(0.05)
        return tutor_resp(messages)

    svc = build_services(settings, llm=FakeLLM({**FAKE, "tutor_turn": slow_tutor}))
    uid, _ = svc.db.create_user("255754000012")
    ok, limited = [], []

    def chat():
        try:
            svc.tutor.chat(uid, "hello")
            ok.append(1)
        except Exception as e:  # noqa: BLE001
            limited.append(type(e).__name__)

    threads = [threading.Thread(target=chat) for _ in range(12)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert len(ok) == settings.free_turns_per_day and set(limited) == {"LimitReached"}


def test_failed_model_call_refunds_the_turn(settings):
    def boom(messages):
        raise RuntimeError("model down")

    svc = build_services(settings, llm=FakeLLM({**FAKE, "tutor_turn": boom}))
    uid, _ = svc.db.create_user("255754000013")
    with pytest.raises(RuntimeError):
        svc.tutor.chat(uid, "hello")
    assert svc.tutor.turns_left(uid) == settings.free_turns_per_day


def test_play_after_prepaid_time_is_active_now_and_mobile_money_blocked_during_play(settings):
    db = DB(settings.db_path)
    uid, _ = db.create_user("255754000014")
    q = PLANS["tz_quarter"]
    db.grant(uid, q.code, q.channel, q.days, "mm-1", q.usd_net_monthly)
    play_expiry = utcnow() + timedelta(days=30)
    sub = db.grant(uid, "pro_monthly", "play", 30, "play:tok", 4.24, expires_at=play_expiry)
    assert sub["starts_at"] <= db.active_subscription(uid)["expires_at"]
    assert utcnow() >= datetime_from(sub["starts_at"]) - timedelta(seconds=1)

    uid2, _ = db.create_user("255754000015")
    db.grant(uid2, "pro_monthly", "play", 30, "play:tok2", 4.24, expires_at=play_expiry)
    az = azampay_with(settings, db, ok_handler)
    with pytest.raises(PaymentError, match="Google Play"):
        az.start_checkout(uid2, "tz_month", "mpesa", "0754000001")


def datetime_from(ts):
    from jarvis.db import parse
    return parse(ts)


def test_sms_abuse_guards(client, settings):
    c, svc = client
    # Not a real Tanzanian mobile number.
    assert c.post("/v1/auth/start", json={"phone": "+2551234567", "country": "TZ"}).status_code == 422
    # Per-address limit: 10 codes an hour from one address, across different numbers.
    codes = [c.post("/v1/auth/start", json={"phone": f"07540001{i:02d}"}).status_code for i in range(11)]
    assert codes[:10] == [200] * 10 and codes[10] == 429

    capped = build_services(replace(settings, otp_daily_cap=2, db_path=settings.db_path + "2"), llm=FakeLLM(FAKE))
    cc = TestClient(create_app(capped))
    assert [cc.post("/v1/auth/start", json={"phone": f"07540002{i:02d}"}).status_code for i in range(3)] == \
        [200, 200, 503]


def test_support_is_rate_limited_and_costed(client, settings):
    c, svc = client
    h = signup(c)
    for _ in range(settings.support_per_day):
        assert c.post("/v1/support", json={"message": "hi"}, headers=h).status_code == 200
    assert c.post("/v1/support", json={"message": "hi"}, headers=h).status_code == 429
    uid = svc.db.user_by_phone("255754000001")["id"]
    assert svc.db.usage_today(uid)["cost_usd"] > 0 and svc.db.usage_today(uid)["turns"] == 0


def test_non_ascii_secrets_do_not_crash(client, settings):
    c, svc = client
    assert c.get("/v1/admin/report", headers={"X-Admin-Key": "ключ".encode()}).status_code == 403
    assert svc.azampay.handle_callback({"utilityref": "x"}, "ключ")["status"] == "unauthorized"
