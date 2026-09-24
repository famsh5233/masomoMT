"""Phone numbers are stored as international digits only, e.g. 255754123456."""
from __future__ import annotations

import re

# Local trunk-prefix formats we accept without a country code (country -> calling code).
CALLING_CODES = {"TZ": "255", "KE": "254", "UG": "256", "RW": "250", "NG": "234", "GH": "233"}


class PhoneError(ValueError):
    pass


def normalize_phone(raw: str, country: str = "TZ") -> str:
    s = raw.strip()
    digits = re.sub(r"\D", "", s)
    if s.startswith("+"):
        pass
    elif digits.startswith("00"):
        digits = digits[2:]
    elif digits.startswith("0") and country.upper() in CALLING_CODES:
        digits = CALLING_CODES[country.upper()] + digits[1:]
    elif len(digits) == 9 and country.upper() in CALLING_CODES:
        digits = CALLING_CODES[country.upper()] + digits
    if not re.fullmatch(r"[1-9]\d{8,14}", digits):
        raise PhoneError(f"not a valid phone number: {raw!r}")
    return digits
