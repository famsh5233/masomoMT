"""HTTP API for the Masomo app. Run: uvicorn jarvis.server:app --host 0.0.0.0 --port 8000"""
from __future__ import annotations

import hmac
import logging
import secrets
import sqlite3
from dataclasses import dataclass
from functools import lru_cache

from fastapi import Depends, FastAPI, Header, HTTPException, Path, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from pydantic import BaseModel, Field

from .agents import LANGUAGES, LEVELS
from .agents.analyst import AnalystAgent
from .agents.content import lesson_index, load_lesson
from .agents.support import SupportAgent
from .agents.tutor import SCENARIOS, LimitReached, TutorService
from .config import Settings, get_settings
from .db import DB
from .llm import LLM, AnthropicLLM, DemoLLM
from .payments.azampay import AzamPay, PaymentError
from .payments.play import PlayError, PlayVerifier
from .phones import PhoneError, is_valid_mobile, normalize_phone
from .plans import PLANS
from .security import BodySizeLimit, SecurityHeaders, mask_phone
from .sms import SMSError, SMSSender
from .videos import VideoLibrary, VideoSourceError

log = logging.getLogger("jarvis.server")


class AuthStart(BaseModel):
    phone: str = Field(min_length=7, max_length=20)
    country: str = Field(default="TZ", min_length=2, max_length=2)


class AuthVerify(AuthStart):
    code: str = Field(min_length=4, max_length=8)
    name: str = Field(default="", max_length=80)
    native_lang: str = Field(default="sw")
    level: str = Field(default="A2")


class ProfileUpdate(BaseModel):
    name: str | None = Field(default=None, max_length=80)
    native_lang: str | None = None
    level: str | None = None


class Chat(BaseModel):
    message: str = Field(min_length=1, max_length=600)
    scenario: str = Field(default="free_talk")


class MobilePay(BaseModel):
    plan: str = Field(max_length=32)
    provider: str = Field(max_length=32)
    phone: str = Field(max_length=20)


class PlayPurchase(BaseModel):
    # Google's tokens use only these characters; anything else could alter the Google API URL it goes into.
    purchase_token: str = Field(min_length=10, max_length=1000, pattern=r"^[A-Za-z0-9._-]+$")


class SupportMsg(BaseModel):
    message: str = Field(min_length=1, max_length=2000)


@dataclass
class Services:
    settings: Settings
    db: DB
    llm: LLM
    tutor: TutorService
    support: SupportAgent
    azampay: AzamPay
    play: PlayVerifier
    sms: SMSSender
    videos: VideoLibrary


def make_llm(settings: Settings) -> LLM:
    if settings.llm_mode == "demo":
        if settings.env != "dev":
            raise RuntimeError("JARVIS_LLM=demo is only allowed with JARVIS_ENV=dev")
        return DemoLLM()
    return AnthropicLLM(settings.anthropic_api_key)


def build_services(settings: Settings, llm: LLM | None = None) -> Services:
    db = DB(settings.db_path, token_ttl_days=settings.token_ttl_days)
    llm = llm or make_llm(settings)
    return Services(settings, db, llm, TutorService(db, llm, settings), SupportAgent(db, llm, settings),
                    AzamPay(settings, db), PlayVerifier(settings, db), SMSSender(settings),
                    VideoLibrary(settings))


@lru_cache
def _default_services() -> Services:
    return build_services(get_settings())


# Endpoints anyone may call without a login token. Every other route must depend on
# current_user or admin; tests/test_jarvis.py enforces this for every route in the app.
PUBLIC_ROUTES = {
    ("GET", "/health"),                         # uptime checks
    ("GET", "/v1/catalog"),                     # prices, shown before sign-in
    ("POST", "/v1/auth/start"),                 # rate-limited per number, per address and per day
    ("POST", "/v1/auth/verify"),                # 5 guesses per code, rate-limited per address
    ("POST", "/v1/pay/azampay/callback"),       # AzamPay; needs the callback secret (+ optional IP list)
}

MIN_ADMIN_KEY_LENGTH = 24


def client_ip(request: Request) -> str:
    # With uvicorn --proxy-headers this is the real client address forwarded by the local reverse proxy.
    return request.client.host if request.client else "unknown"


def create_app(services: Services | None = None) -> FastAPI:
    settings = services.settings if services else get_settings()
    dev = settings.env == "dev"
    # The interactive API docs would publish a map of every endpoint, so they exist only in development.
    app = FastAPI(title="Masomo JARVIS API", version="1.2.0", docs_url="/docs" if dev else None,
                  redoc_url=None, openapi_url="/openapi.json" if dev else None)
    svc = services or None
    origins = [o.strip() for o in settings.cors_origins.split(",") if o.strip()]
    if origins:
        app.add_middleware(CORSMiddleware, allow_origins=origins, allow_methods=["GET", "POST", "PATCH"],
                           allow_headers=["Authorization", "Content-Type"])
    hosts = [h.strip() for h in settings.allowed_hosts.split(",") if h.strip()]
    if hosts:
        app.add_middleware(TrustedHostMiddleware, allowed_hosts=hosts)
    app.add_middleware(SecurityHeaders)
    app.add_middleware(BodySizeLimit)

    def S() -> Services:
        return svc or _default_services()

    def current_user(authorization: str = Header(default="")) -> sqlite3.Row:
        scheme, _, token = authorization.partition(" ")
        user = S().db.user_by_token(token.strip()) if scheme.lower() == "bearer" and token.strip() else None
        if not user:
            raise HTTPException(401, "invalid or missing token", headers={"WWW-Authenticate": "Bearer"})
        return user

    def admin(request: Request, x_admin_key: str = Header(default="")) -> None:
        s = S()
        key = s.settings.admin_key
        ip = client_ip(request)
        # A short or unset key disables admin access entirely rather than being guessable.
        if len(key) < MIN_ADMIN_KEY_LENGTH or not hmac.compare_digest(x_admin_key.encode(), key.encode()):
            if not s.db.rate_hit(f"admin-fail:{ip}", s.settings.admin_failures_per_ip_per_hour, 3600):
                raise HTTPException(429, "too many attempts")
            log.warning("rejected admin request from %s", ip)
            raise HTTPException(403, "admin only")

    def limited(key: str, limit: int, window: int = 3600) -> None:
        if not S().db.rate_hit(key, limit, window):
            raise HTTPException(429, {"code": "rate_limited",
                                      "message_en": "Too many requests. Please try again later.",
                                      "message_sw": "Maombi mengi mno. Tafadhali jaribu tena baadaye."})

    @app.get("/health")
    def health():
        return {"ok": True}

    @app.get("/v1/catalog")
    def catalog():
        return {"plans": [{"code": p.code, "channel": p.channel, "currency": p.currency, "amount": p.amount,
                           "days": p.days, "label_sw": p.label_sw, "label_en": p.label_en}
                          for p in PLANS.values()],
                "languages": LANGUAGES, "levels": LEVELS, "scenarios": list(SCENARIOS)}

    def _phone(raw: str, country: str) -> str:
        try:
            return normalize_phone(raw, country)
        except PhoneError as e:
            raise HTTPException(422, str(e))

    @app.post("/v1/auth/start")
    def auth_start(body: AuthStart, request: Request):
        s = S()
        phone = _phone(body.phone, body.country)
        allowed = [c.strip() for c in s.settings.otp_country_codes.split(",") if c.strip()]
        if allowed and not any(phone.startswith(c) for c in allowed):
            raise HTTPException(422, {"code": "country_not_supported",
                                      "message_en": "Sign-in by SMS is not available in your country yet.",
                                      "message_sw": "Kuingia kwa SMS bado hakupatikani katika nchi yako."})
        if not is_valid_mobile(phone):
            raise HTTPException(422, "not a mobile number")
        ip = client_ip(request)
        if not s.db.rate_hit(f"otp-ip:{ip}", s.settings.otp_per_ip_per_hour, 3600):
            raise HTTPException(429, {"code": "too_many_codes",
                                      "message_en": "Too many codes requested. Try again in an hour.",
                                      "message_sw": "Umeomba namba nyingi mno. Jaribu tena baada ya saa moja."})
        if not s.db.rate_hit("otp-global", s.settings.otp_daily_cap, 86400):
            log.error("daily SMS cap of %s reached; sign-in codes paused", s.settings.otp_daily_cap)
            raise HTTPException(503, "sign-in is temporarily unavailable, try again later")
        code = f"{secrets.randbelow(1_000_000):06d}"
        if not s.db.otp_issue(phone, code, s.settings.otp_ttl_minutes, s.settings.otp_max_sends_per_hour):
            raise HTTPException(429, {"code": "too_many_codes",
                                      "message_en": "Too many codes requested. Try again in an hour.",
                                      "message_sw": "Umeomba namba nyingi mno. Jaribu tena baada ya saa moja."})
        try:
            s.sms.send(phone, f"Masomo: namba yako ya kuingia ni {code}. Your login code is {code}.")
        except SMSError as e:
            log.error("OTP send failed for %s: %s", mask_phone(phone), e)
            raise HTTPException(503, "could not send SMS, try again later")
        out = {"phone": phone, "sent": True, "expires_in_minutes": s.settings.otp_ttl_minutes}
        if s.settings.env == "dev" and s.settings.sms_provider == "console":
            out["dev_code"] = code
        return out

    @app.post("/v1/auth/verify")
    def auth_verify(body: AuthVerify, request: Request):
        s = S()
        limited(f"verify-ip:{client_ip(request)}", s.settings.verify_per_ip_per_hour)
        phone = _phone(body.phone, body.country)
        if not s.db.otp_check(phone, body.code.strip(), s.settings.otp_max_attempts):
            raise HTTPException(401, {"code": "bad_code", "message_en": "Wrong or expired code.",
                                      "message_sw": "Namba si sahihi au imeisha muda."})
        user = s.db.user_by_phone(phone)
        if user:
            return {"token": s.db.rotate_token(user["id"]), "user_id": user["id"], "is_new": False}
        native = body.native_lang if body.native_lang in LANGUAGES else "sw"
        level = body.level if body.level in LEVELS else "A2"
        try:
            user_id, token = s.db.create_user(phone, body.name.strip(), native, body.country.upper(), level)
        except sqlite3.IntegrityError:  # created by a parallel request a moment ago
            user = s.db.user_by_phone(phone)
            return {"token": s.db.rotate_token(user["id"]), "user_id": user["id"], "is_new": False}
        return {"token": token, "user_id": user_id, "is_new": True}

    def _me(user_id: int) -> dict:
        s = S()
        user = s.db.user(user_id)
        sub = s.db.active_subscription(user_id)
        return {"id": user["id"], "name": user["name"], "phone": user["phone"], "level": user["level"],
                "native_lang": user["native_lang"], "country": user["country"], "pro": bool(sub),
                "pro_until": sub["expires_at"] if sub else None, "pro_plan": sub["plan"] if sub else None,
                "turns_left_today": s.tutor.turns_left(user_id),
                "daily_limit": s.tutor.daily_limit(user_id)}

    @app.get("/v1/me")
    def me(user=Depends(current_user)):
        return _me(user["id"])

    @app.patch("/v1/me")
    def update_me(body: ProfileUpdate, user=Depends(current_user)):
        if body.native_lang is not None and body.native_lang not in LANGUAGES:
            raise HTTPException(422, "unsupported native_lang")
        if body.level is not None and body.level not in LEVELS:
            raise HTTPException(422, "unsupported level")
        S().db.update_profile(user["id"], name=body.name.strip() if body.name is not None else None,
                              native_lang=body.native_lang, level=body.level)
        return _me(user["id"])

    @app.post("/v1/auth/logout")
    def logout(user=Depends(current_user)):
        S().db.revoke_token(user["id"])
        return {"ok": True}

    @app.post("/v1/tutor/chat")
    def tutor_chat(body: Chat, user=Depends(current_user)):
        if body.scenario not in SCENARIOS:
            raise HTTPException(422, f"scenario must be one of {list(SCENARIOS)}")
        try:
            return S().tutor.chat(user["id"], body.message, body.scenario)
        except LimitReached:
            raise HTTPException(429, {"code": "daily_limit", "upgrade": True,
                                      "message_sw": "Umemaliza mazungumzo ya leo. Jiunge na Pro uendelee.",
                                      "message_en": "You've used today's conversations. Go Pro to continue."})

    @app.get("/v1/lessons")
    def lessons(user=Depends(current_user)):
        s = S()
        pro = s.db.active_subscription(user["id"]) is not None
        return {"lessons": lesson_index(s.settings.content_dir, user["native_lang"],
                                        s.settings.free_lesson_weeks, pro)}

    @app.get("/v1/videos")
    def video_weeks(user=Depends(current_user)):
        s = S()
        pro = s.db.active_subscription(user["id"]) is not None
        return {"weeks": [{"week": w, "locked": w > s.settings.free_video_weeks and not pro}
                          for w in range(1, s.settings.video_weeks + 1)]}

    @app.get("/v1/videos/{week}")
    def videos(week: int, user=Depends(current_user)):
        s = S()
        if not 1 <= week <= s.settings.video_weeks:
            raise HTTPException(404, "no such week")
        if week > s.settings.free_video_weeks and not s.db.active_subscription(user["id"]):
            raise HTTPException(402, {"code": "pro_required", "upgrade": True})
        try:
            return {"week": week, "videos": s.videos.week(week)}
        except VideoSourceError as e:
            log.error("video source error: %s", e)
            raise HTTPException(503, "videos are temporarily unavailable")

    @app.get("/v1/lessons/{week}")
    def lesson(week: int, user=Depends(current_user)):
        s = S()
        if week > s.settings.free_lesson_weeks and not s.db.active_subscription(user["id"]):
            raise HTTPException(402, {"code": "pro_required", "upgrade": True})
        data = load_lesson(s.settings.content_dir, week, user["native_lang"]) or \
            load_lesson(s.settings.content_dir, week, "sw")
        if not data:
            raise HTTPException(404, "lesson not published yet")
        return data

    @app.post("/v1/pay/mobile")
    def pay_mobile(body: MobilePay, user=Depends(current_user)):
        s = S()
        # Each checkout pushes a PIN prompt to a phone; cap it so an account can't be used to spam people.
        limited(f"checkout:{user['id']}", s.settings.checkouts_per_user_per_hour)
        try:
            return s.azampay.start_checkout(user["id"], body.plan, body.provider, body.phone)
        except PaymentError as e:
            if e.public:
                raise HTTPException(400, str(e))
            log.error("mobile checkout failed for user %s: %s", user["id"], e)
            raise HTTPException(502, "the payment service is unavailable, please try again")
        except ValueError as e:  # unknown plan
            raise HTTPException(400, str(e))

    @app.post("/v1/pay/azampay/callback")
    async def azampay_callback(request: Request, key: str = Query(default="", max_length=200)):
        allowed_ips = [i.strip() for i in S().settings.azampay_callback_ips.split(",") if i.strip()]
        if allowed_ips and client_ip(request) not in allowed_ips:
            log.warning("AzamPay callback from unexpected address %s", client_ip(request))
            raise HTTPException(403, "forbidden")
        try:
            payload = await request.json()
        except ValueError:
            raise HTTPException(400, "invalid json")
        result = S().azampay.handle_callback(payload if isinstance(payload, dict) else {}, key)
        if result["status"] == "unauthorized":
            raise HTTPException(403, "bad key")
        return result

    @app.get("/v1/pay/status/{external_id}")
    def pay_status(external_id: str = Path(max_length=64), user=Depends(current_user)):
        p = S().db.payment(external_id)
        if not p or p["user_id"] != user["id"]:
            raise HTTPException(404, "not found")
        return {"external_id": external_id, "status": p["status"], "plan": p["plan"]}

    @app.post("/v1/pay/play/verify")
    def play_verify(body: PlayPurchase, user=Depends(current_user)):
        s = S()
        limited(f"play-verify:{user['id']}", s.settings.play_verifies_per_user_per_hour)
        try:
            return s.play.verify(user["id"], body.purchase_token)
        except PlayError as e:
            if e.public:
                raise HTTPException(400, str(e))
            log.error("Play verification failed for user %s: %s", user["id"], e)
            raise HTTPException(502, "could not confirm the purchase with Google Play, please try again")
        except ValueError as e:  # product ID with no matching plan
            raise HTTPException(400, str(e))

    @app.post("/v1/support")
    def support(body: SupportMsg, user=Depends(current_user)):
        s = S()
        if not s.db.rate_hit(f"support:{user['id']}", s.settings.support_per_day, 86400):
            raise HTTPException(429, {"code": "support_limit",
                                      "message_en": "You've sent a lot of messages today. We'll reply soon.",
                                      "message_sw": "Umetuma ujumbe mwingi leo. Tutakujibu hivi karibuni."})
        return s.support.answer(body.message, user["phone"])

    @app.get("/v1/admin/report", dependencies=[Depends(admin)])
    def admin_report(advice: bool = False):
        s = S()
        return AnalystAgent(s.db, s.llm if advice else None, s.settings).report(with_advice=advice)

    return app


app = create_app()
