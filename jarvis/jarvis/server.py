"""HTTP API for the Masomo app. Run: uvicorn jarvis.server:app --host 0.0.0.0 --port 8000"""
from __future__ import annotations

import hmac
import sqlite3
from dataclasses import dataclass
from functools import lru_cache

from fastapi import Depends, FastAPI, Header, HTTPException, Query, Request
from pydantic import BaseModel, Field

from .agents import LANGUAGES, LEVELS
from .agents.analyst import AnalystAgent
from .agents.content import load_lesson
from .agents.support import SupportAgent
from .agents.tutor import SCENARIOS, LimitReached, TutorService
from .config import Settings, get_settings
from .db import DB
from .llm import LLM, AnthropicLLM
from .payments.azampay import AzamPay, PaymentError
from .payments.play import PlayError, PlayVerifier
from .plans import PLANS


class SignUp(BaseModel):
    phone: str = Field(min_length=7, max_length=20)
    name: str = Field(default="", max_length=80)
    native_lang: str = Field(default="sw")
    country: str = Field(default="TZ", min_length=2, max_length=2)
    level: str = Field(default="A2")


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


def build_services(settings: Settings, llm: LLM | None = None) -> Services:
    db = DB(settings.db_path)
    llm = llm or AnthropicLLM(settings.anthropic_api_key)
    return Services(settings, db, llm, TutorService(db, llm, settings), SupportAgent(db, llm, settings),
                    AzamPay(settings, db), PlayVerifier(settings, db))


@lru_cache
def _default_services() -> Services:
    return build_services(get_settings())


def create_app(services: Services | None = None) -> FastAPI:
    app = FastAPI(title="Masomo JARVIS API", version="1.0.0")
    svc = services or None

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

    @app.post("/v1/users", status_code=201)
    def sign_up(body: SignUp):
        # NOTE: add SMS OTP verification before relying on phone ownership.
        if body.native_lang not in LANGUAGES or body.level not in LEVELS:
            raise HTTPException(422, "unsupported native_lang or level")
        if S().db.user_by_phone(body.phone):
            raise HTTPException(409, "phone already registered")
        user_id, token = S().db.create_user(body.phone, body.name, body.native_lang,
                                            body.country.upper(), body.level)
        return {"user_id": user_id, "token": token}

    @app.get("/v1/me")
    def me(user=Depends(current_user)):
        sub = S().db.active_subscription(user["id"])
        return {"id": user["id"], "name": user["name"], "phone": user["phone"], "level": user["level"],
                "native_lang": user["native_lang"], "pro": bool(sub),
                "pro_until": sub["expires_at"] if sub else None,
                "turns_left_today": S().tutor.turns_left(user["id"])}

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
