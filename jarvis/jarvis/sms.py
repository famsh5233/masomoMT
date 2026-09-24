"""SMS delivery for login codes.

console         prints the code to the server log (development only)
africastalking  Africa's Talking bulk SMS (Tanzania, Kenya, Uganda and more)
"""
from __future__ import annotations

import logging
from dataclasses import dataclass, field

import httpx

from .config import Settings

log = logging.getLogger("jarvis.sms")

AT_URL = "https://api.africastalking.com/version1/messaging"
AT_SANDBOX_URL = "https://api.sandbox.africastalking.com/version1/messaging"


class SMSError(Exception):
    pass


@dataclass
class SMSSender:
    settings: Settings
    http: httpx.Client = field(default_factory=lambda: httpx.Client(timeout=20))
    sent: list[tuple[str, str]] = field(default_factory=list)  # console provider keeps a copy (tests)

    def send(self, phone: str, text: str) -> None:
        provider = self.settings.sms_provider
        if provider == "console":
            if self.settings.env != "dev":
                raise SMSError("SMS provider is not configured")
            log.warning("SMS to +%s: %s", phone, text)
            self.sent.append((phone, text))
            return
        if provider == "africastalking":
            s = self.settings
            if not (s.at_username and s.at_api_key):
                raise SMSError("Africa's Talking credentials are not configured")
            data = {"username": s.at_username, "to": f"+{phone}", "message": text}
            if s.at_sender_id:
                data["from"] = s.at_sender_id
            url = AT_SANDBOX_URL if s.at_username == "sandbox" else AT_URL
            try:
                r = self.http.post(url, data=data, headers={"apiKey": s.at_api_key, "Accept": "application/json"})
                r.raise_for_status()
                recipients = r.json().get("SMSMessageData", {}).get("Recipients", [])
            except (httpx.HTTPError, ValueError) as e:
                raise SMSError(f"SMS send failed: {e}") from e
            if not recipients or recipients[0].get("status") != "Success":
                raise SMSError(f"SMS rejected: {str(recipients)[:200]}")
            return
        raise SMSError(f"unknown SMS provider {provider!r}")
