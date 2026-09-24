"""HTTP API for the Masomo app. Run: uvicorn jarvis.server:app --host 0.0.0.0 --port 8000"""
from __future__ import annotations

import hmac
import logging
import secrets
import sqlite3
from dataclasses import dataclass
from functools import lru_cache

from fastapi import Depends, FastAPI, Header, HTTPException, Query, Request
from fastapi.middleware.cors import CORSMiddleware
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
from .phones import PhoneError, normalize_phone
from .plans import PLANS
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
    plan: str
    provider: str
    phone: str


class PlayPurchase(BaseModel):
    purchase_token: str = Field(min_length=10, max_length=1000)


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
    db = DB(settings.db_path)
    llm = llm or make_llm(settings)
    return Services(settings, db, llm, TutorService(db, llm, settings), SupportAgent(db, llm, settings),
                    AzamPay(settings, db), PlayVerifier(settings, db), SMSSender(settings),
                    VideoLibrary(settings))


@lru_cache
def _default_services() -> Services:
    return build_services(get_settings())


def create_app(services: Services | None = None) -> FastAPI:
    app = FastAPI(title="Masomo JARVIS API", version="1.1.0")
    svc = services or None
    origins = [o.strip() for o in (services.settings if services else get_settings()).cors_origins.split(",")
               if o.strip()]
    if origins:
        app.add_middleware(CORSMiddleware, allow_origins=origins, allow_methods=["*"],
                           allow_headers=["Authorization", "Content-Type"])

    def S() -> Services:
        return svc or _default_services()

    def current_user(authorization: str = Header(default="")) -> sqlite3.Row:
        token = authorization.removeprefix("Bearer ").strip()
        user = S().db.user_by_token(token) if token else None
        if not user:
            raise HTTPException(401, "invalid or missing token")
        return user

    def admin(x_admin_key: str = Header(default="")) -> None:
        key = S().settings.admin_key
        if not key or not hmac.compare_digest(x_admin_key, key):
            raise HTTPException(403, "admin only")

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
    def auth_start(body: AuthStart):
        s = S()
        phone = _phone(body.phone, body.country)
        allowed = [c.strip() for c in s.settings.otp_country_codes.split(",") if c.strip()]
        if allowed and not any(phone.startswith(c) for c in allowed):
            raise HTTPException(422, {"code": "country_not_supported",
                                      "message_en": "Sign-in by SMS is not available in your country yet.",
                                      "message_sw": "Kuingia kwa SMS bado hakupatikani katika nchi yako."})
        code = f"{secrets.randbelow(1_000_000):06d}"
        if not s.db.otp_issue(phone, code, s.settings.otp_ttl_minutes, s.settings.otp_max_sends_per_hour):
            raise HTTPException(429, {"code": "too_many_codes",
                                      "message_en": "Too many codes requested. Try again in an hour.",
                                      "message_sw": "Umeomba namba nyingi mno. Jaribu tena baada ya saa moja."})
        try:
            s.sms.send(phone, f"Masomo: namba yako ya kuingia ni {code}. Your login code is {code}.")
        except SMSError as e:
            log.error("OTP send failed for %s: %s", phone, e)
            raise HTTPException(503, "could not send SMS, try again later")
        out = {"phone": phone, "sent": True, "expires_in_minutes": s.settings.otp_ttl_minutes}
        if s.settings.env == "dev" and s.settings.sms_provider == "console":
            out["dev_code"] = code
        return out

    @app.post("/v1/auth/verify")
    def auth_verify(body: AuthVerify):
        s = S()
        phone = _phone(body.phone, body.country)
        if not s.db.otp_check(phone, body.code.strip(), s.settings.otp_max_attempts):
            raise HTTPException(401, {"code": "bad_code", "message_en": "Wrong or expired code.",
                                      "message_sw": "Namba si sahihi au imeisha muda."})
        user = s.db.user_by_phone(phone)
        if user:
            return {"token": s.db.rotate_token(user["id"]), "user_id": user["id"], "is_new": False}
        native = body.native_lang if body.native_lang in LANGUAGES else "sw"
        level = body.level if body.level in LEVELS else "A2"
        user_id, token = s.db.create_user(phone, body.name.strip(), native, body.country.upper(), level)
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
        S().db.rotate_token(user["id"])  # invalidates the current token
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
        try:
            return S().azampay.start_checkout(user["id"], body.plan, body.provider, body.phone)
        except (PaymentError, ValueError) as e:
            raise HTTPException(400, str(e))

    @app.post("/v1/pay/azampay/callback")
    async def azampay_callback(request: Request, key: str = Query(default="")):
        try:
            payload = await request.json()
        except ValueError:
            raise HTTPException(400, "invalid json")
        result = S().azampay.handle_callback(payload if isinstance(payload, dict) else {}, key)
        if result["status"] == "unauthorized":
            raise HTTPException(403, "bad key")
        return result

    @app.get("/v1/pay/status/{external_id}")
    def pay_status(external_id: str, user=Depends(current_user)):
        p = S().db.payment(external_id)
        if not p or p["user_id"] != user["id"]:
            raise HTTPException(404, "not found")
        return {"external_id": external_id, "status": p["status"], "plan": p["plan"]}

    @app.post("/v1/pay/play/verify")
    def play_verify(body: PlayPurchase, user=Depends(current_user)):
        try:
            return S().play.verify(user["id"], body.purchase_token)
        except (PlayError, ValueError) as e:
            raise HTTPException(400, str(e))

    @app.post("/v1/support")
    def support(body: SupportMsg, user=Depends(current_user)):
        return S().support.answer(body.message, user["phone"])

    @app.get("/v1/admin/report", dependencies=[Depends(admin)])
    def admin_report(advice: bool = False):
        s = S()
        return AnalystAgent(s.db, s.llm if advice else None, s.settings).report(with_advice=advice)

    return app


app = create_app()
