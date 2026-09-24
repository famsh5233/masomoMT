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
                   free_turns_per_day=2, paid_turns_per_day=5)


@pytest.fixture
def client(settings):
    svc = build_services(settings, llm=FakeLLM(FAKE))
    return TestClient(create_app(svc)), svc


def signup(c, phone="255754000001"):
    r = c.post("/v1/users", json={"phone": phone, "name": "Asha"})
    assert r.status_code == 201, r.text
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
