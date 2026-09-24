"""Support agent: answers customer messages (WhatsApp, in-app) in their language.

It never guesses about money: the customer's real subscription and payment rows
are looked up first and handed to the model, and anything it cannot resolve
(refunds, charged-but-not-activated, abuse) is escalated to a human queue.
"""
from __future__ import annotations

from dataclasses import dataclass

from ..config import Settings
from ..db import DB
from ..llm import LLM
from ..plans import PLANS

FAQ = """- Free plan: 10 AI conversations per day and week 1 lessons.
- Pro: more AI conversations per day ({paid}/day) and all weekly lessons.
- Prices: {prices}.
- Pay in the app: choose plan, choose network, enter phone number, confirm the PIN prompt on your phone.
- If money was taken but Pro is not active after 10 minutes: support will check with the transaction ID.
- Google Play subscriptions are cancelled in Google Play > Payments & subscriptions.
- Mobile-money plans do not auto-renew; nothing to cancel.
- Speech not recognised: allow microphone permission, speak close to the phone, check internet."""

SCHEMA = {
    "type": "object",
    "properties": {
        "reply": {"type": "string", "description": "Reply to the customer in the language they wrote in. Short, kind, concrete."},
        "escalate": {"type": "boolean", "description": "True if a human must act (refund, missing payment, bug, abuse, anything you cannot solve with the facts given)."},
        "reason": {"type": "string", "description": "For the human: what happened and what to check. Empty if not escalating."},
    },
    "required": ["reply", "escalate", "reason"],
}


@dataclass
class SupportAgent:
    db: DB
    llm: LLM
    settings: Settings

    def _account_facts(self, phone: str) -> str:
        user = self.db.user_by_phone(phone) if phone else None
        if not user:
            return "No account found for this phone number."
        sub = self.db.active_subscription(user["id"])
        pays = self.db.payments_for(user["id"])
        lines = [f"Account: {user['name'] or '(no name)'}, joined {user['created_at'][:10]}, level {user['level']}.",
                 f"Pro active until {sub['expires_at']} ({sub['plan']})." if sub else "Pro: not active."]
        for p in pays:
            lines.append(f"Payment {p['external_id']}: {p['amount']:.0f} {p['currency']} via {p['provider']}, "
                         f"status {p['status']}, at {p['created_at']}.")
        return "\n".join(lines)

    def answer(self, message: str, phone: str = "") -> dict:
        prices = ", ".join(f"{p.label_en} {p.amount:,.0f} {p.currency}" for p in PLANS.values()
                           if p.channel == "mobile_money")
        system = ("You are the customer support assistant for Masomo, an English speaking-practice app. "
                  "Answer ONLY from the FAQ and the account facts. Never invent prices, promises or refunds. "
                  "If the customer says they paid but Pro is not active, or asks for a refund, escalate.\n\n"
                  "FAQ:\n" + FAQ.format(paid=self.settings.paid_turns_per_day, prices=prices))
        facts = self._account_facts(phone)
        result = self.llm.structured(
            model=self.settings.tutor_model, system=system,
            messages=[{"role": "user", "content": f"<account_facts>\n{facts}\n</account_facts>\n\n"
                                                  f"<customer_message>\n{message[:2000]}\n</customer_message>"}],
            tool_name="support_reply", schema=SCHEMA, max_tokens=600)
        data = result.data
        if data["escalate"]:
            user = self.db.user_by_phone(phone) if phone else None
            data["ticket_id"] = self.db.escalate(phone or "unknown", data["reason"] or message[:500],
                                                 user["id"] if user else None)
        return data
