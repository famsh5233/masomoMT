"""AzamPay mobile-money checkout (Tanzania): one integration covers M-Pesa,
Mixx by Yas (Tigo Pesa), Airtel Money, HaloPesa and AzamPesa.

Replaces the current manual flow (customer sends money to a personal number and
pastes the SMS), which cannot scale, is easy to fake and needs a human to check.

Flow: app -> POST /v1/pay/mobile -> we create a pending payment and ask AzamPay to
push a PIN prompt to the customer's phone -> customer enters PIN -> AzamPay calls
our callback -> we match reference + amount and grant Pro.

Field names follow AzamPay's public API (see the official docs and the community
SDKs such as github.com/Golang-Tanzania/azampay). Test end to end in the sandbox
before switching AZAMPAY_*_URL to production.
"""
from __future__ import annotations

import hmac
import re
import time
from dataclasses import dataclass, field

import httpx

from ..config import Settings
from ..db import DB
from ..plans import get_plan

MIN_CALLBACK_SECRET_LENGTH = 24

PROVIDERS = {"mpesa": "Mpesa", "tigo": "Tigo", "mixx": "Tigo", "airtel": "Airtel",
             "halopesa": "Halopesa", "azampesa": "Azampesa"}


class PaymentError(Exception):
    """public=True: safe to show the customer. False: gateway detail, for our logs only."""

    def __init__(self, message: str, public: bool = True):
        super().__init__(message)
        self.public = public


def normalize_tz_msisdn(phone: str) -> str:
    digits = re.sub(r"\D", "", phone)
    if digits.startswith("0") and len(digits) == 10:
        digits = "255" + digits[1:]
    elif len(digits) == 9:
        digits = "255" + digits
    if not re.fullmatch(r"255[67]\d{8}", digits):
        raise PaymentError(f"not a Tanzanian mobile number: {phone!r}")
    return digits


@dataclass
class AzamPay:
    settings: Settings
    db: DB
    http: httpx.Client = field(default_factory=lambda: httpx.Client(timeout=30))
    _token: str = ""
    _token_exp: float = 0.0

    def _auth(self) -> str:
        if self._token and time.time() < self._token_exp:
            return self._token
        s = self.settings
        if not (s.azampay_app_name and s.azampay_client_id and s.azampay_client_secret):
            raise PaymentError("AzamPay credentials are not configured", public=False)
        r = self.http.post(f"{s.azampay_auth_url}/AppRegistration/GenerateToken", json={
            "appName": s.azampay_app_name, "clientId": s.azampay_client_id,
            "clientSecret": s.azampay_client_secret})
        r.raise_for_status()
        token = (r.json().get("data") or {}).get("accessToken")
        if not token:
            raise PaymentError(f"AzamPay auth failed: {r.text[:300]}", public=False)
        self._token, self._token_exp = token, time.time() + 50 * 60
        return token

    def start_checkout(self, user_id: int, plan_code: str, provider: str, phone: str) -> dict:
        plan = get_plan(plan_code)
        if plan.channel != "mobile_money":
            raise PaymentError(f"plan {plan_code} is not sold via mobile money")
        prov = PROVIDERS.get(provider.lower())
        if not prov:
            raise PaymentError(f"unknown provider {provider!r}; valid: {sorted(PROVIDERS)}")
        msisdn = normalize_tz_msisdn(phone)
        active = self.db.active_subscription(user_id)
        if active is not None and active["channel"] == "play":
            # Mobile-money time would run alongside the renewing Play subscription and be wasted.
            raise PaymentError("Pro is already active through Google Play")
        external_id = self.db.create_payment(user_id, plan.code, prov, msisdn, plan.amount, plan.currency)
        try:
            r = self.http.post(
                f"{self.settings.azampay_checkout_url}/azampay/mno/checkout",
                headers={"Authorization": f"Bearer {self._auth()}", "X-API-Key": self.settings.azampay_api_key},
                json={"accountNumber": msisdn, "amount": str(int(plan.amount)), "currency": plan.currency,
                      "externalId": external_id, "provider": prov})
            body = r.json() if r.content else {}
            if r.status_code >= 400 or not body.get("success", False):
                raise PaymentError(f"checkout rejected ({r.status_code}): {str(body)[:300]}", public=False)
        except (httpx.HTTPError, PaymentError, ValueError) as e:
            self.db.update_payment(external_id, "failed", detail=str(e)[:500])
            raise PaymentError(str(e), public=False) from e
        # Only attach the reference: the callback may already have marked it paid.
        self.db.set_provider_ref(external_id, body.get("transactionId"))
        return {"external_id": external_id, "status": "pending",
                "message_sw": "Angalia simu yako na uweke PIN kuthibitisha malipo.",
                "message_en": "Check your phone and enter your PIN to confirm the payment."}

    def handle_callback(self, payload: dict, key: str) -> dict:
        """Idempotent. Returns {"ok": bool, "status": ...}. Never raises on bad input."""
        secret = self.settings.azampay_callback_secret
        # A short secret could be guessed and used to fake "paid" callbacks, so it disables callbacks.
        if len(secret) < MIN_CALLBACK_SECRET_LENGTH or not hmac.compare_digest((key or "").encode(), secret.encode()):
            return {"ok": False, "status": "unauthorized"}
        ref = str(payload.get("utilityref") or payload.get("externalId") or "")
        pay = self.db.payment(ref)
        if not pay:
            return {"ok": False, "status": "unknown_reference"}
        if pay["status"] == "success":
            return {"ok": True, "status": "already_processed"}
        status = str(payload.get("transactionstatus", "")).lower()
        provider_ref = str(payload.get("reference") or "") or None
        if status != "success":
            self.db.update_payment(ref, "failed", provider_ref, detail=str(payload.get("message", ""))[:500])
            return {"ok": True, "status": "failed"}
        try:
            paid = float(payload.get("amount", 0))
        except (TypeError, ValueError):
            paid = 0.0
        if paid + 0.5 < pay["amount"]:
            self.db.update_payment(ref, "review", provider_ref, detail=f"amount mismatch: got {paid}")
            self.db.escalate(pay["msisdn"], f"AzamPay {ref}: paid {paid}, expected {pay['amount']}", pay["user_id"])
            return {"ok": True, "status": "amount_mismatch"}
        plan = get_plan(pay["plan"])
        self.db.grant(pay["user_id"], plan.code, plan.channel, plan.days, source_ref=f"azampay:{ref}",
                      usd_net_monthly=plan.usd_net_monthly)
        self.db.update_payment(ref, "success", provider_ref)
        return {"ok": True, "status": "success"}
