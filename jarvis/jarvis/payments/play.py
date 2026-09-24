"""Google Play subscription verification: the global payment channel.

Play handles cards, carrier billing and local wallets in 170+ countries, taxes
and currency conversion; Tanzania-registered developers can be Play merchants.
The app buys the subscription with Play Billing, then sends us the purchase
token; we verify it with the Android Publisher API and grant Pro until expiry.

Setup: Play Console > Users and permissions > invite a Google Cloud service
account with "View financial data" + "Manage orders", set
PLAY_SERVICE_ACCOUNT_FILE and PLAY_PACKAGE_NAME. Requires `google-auth`.
"""
from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime

from ..config import Settings
from ..db import DB
from ..plans import get_plan

API = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications"
ACTIVE_STATES = {"SUBSCRIPTION_STATE_ACTIVE", "SUBSCRIPTION_STATE_IN_GRACE_PERIOD"}


class PlayError(Exception):
    pass


def parse_rfc3339(ts: str) -> datetime:
    # Google returns e.g. 2026-10-24T12:00:00.123456789Z; Python wants <= 6 fraction digits.
    ts = ts.replace("Z", "+00:00")
    if "." in ts:
        head, rest = ts.split(".", 1)
        frac, _, tz = rest.partition("+")
        ts = f"{head}.{frac[:6]}+{tz}"
    return datetime.fromisoformat(ts)


def _default_session(settings: Settings):
    from google.auth.transport.requests import AuthorizedSession
    from google.oauth2 import service_account
    creds = service_account.Credentials.from_service_account_file(
        settings.play_service_account_file, scopes=["https://www.googleapis.com/auth/androidpublisher"])
    return AuthorizedSession(creds)


@dataclass
class PlayVerifier:
    settings: Settings
    db: DB
    session_factory: Callable = _default_session

    def verify(self, user_id: int, purchase_token: str) -> dict:
        s = self.settings
        if not (s.play_package_name and s.play_service_account_file) and self.session_factory is _default_session:
            raise PlayError("Google Play verification is not configured")
        session = self.session_factory(s)
        base = f"{API}/{s.play_package_name}/purchases/subscriptionsv2/tokens/{purchase_token}"
        r = session.get(base)
        if r.status_code != 200:
            raise PlayError(f"Play API {r.status_code}: {r.text[:300]}")
        data = r.json()
        state = data.get("subscriptionState")
        items = data.get("lineItems") or []
        if state not in ACTIVE_STATES or not items:
            return {"active": False, "state": state}
        item = max(items, key=lambda i: i.get("expiryTime", ""))
        product_id = item["productId"]
        plan = get_plan(product_id)  # Play product IDs must match plan codes (pro_monthly, pro_yearly)
        expires = parse_rfc3339(item["expiryTime"])
        sub = self.db.grant(user_id, plan.code, "play", plan.days, source_ref=f"play:{purchase_token}",
                            usd_net_monthly=plan.usd_net_monthly, expires_at=expires)
        if sub["user_id"] != user_id:
            raise PlayError("this purchase is already linked to another account")
        if data.get("acknowledgementState") == "ACKNOWLEDGEMENT_STATE_PENDING":
            # Unacknowledged purchases are refunded by Google after 3 days.
            ack = session.post(f"{API}/{s.play_package_name}/purchases/subscriptions/"
                               f"{product_id}/tokens/{purchase_token}:acknowledge", json={})
            if ack.status_code not in (200, 204):
                raise PlayError(f"acknowledge failed {ack.status_code}: {ack.text[:300]}")
        return {"active": True, "state": state, "plan": plan.code, "expires_at": sub["expires_at"]}
