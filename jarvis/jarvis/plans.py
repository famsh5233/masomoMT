"""Price book. One place to change prices; everything else reads from here.

Prices are purchasing-power adjusted:
  * Tanzania mobile money keeps the price customers already pay today
    (TSh 2,000 / week) and adds cheaper-per-day monthly/quarterly plans.
  * Google Play products are priced in Play Console with regional pricing;
    `usd_net` below is only used to estimate MRR (after Play's 15% fee).
"""
from __future__ import annotations

from dataclasses import dataclass

# Approximate FX used for reporting only (update monthly). 1 USD = N units.
FX_PER_USD = {"USD": 1.0, "TZS": 2640.0, "KES": 129.0, "UGX": 3700.0}

# Payment-processor fee assumptions used for net revenue estimates.
MOBILE_MONEY_FEE = 0.03   # aggregator collection fee (negotiate; 2-3.5% typical)
PLAY_FEE = 0.15           # Google Play fee on auto-renewing subscriptions


@dataclass(frozen=True)
class Plan:
    code: str
    channel: str        # "mobile_money" | "play"
    currency: str
    amount: float       # in major currency units (TZS has no minor unit in practice)
    days: int
    label_sw: str
    label_en: str

    @property
    def usd_gross(self) -> float:
        return self.amount / FX_PER_USD[self.currency]

    @property
    def usd_net(self) -> float:
        fee = MOBILE_MONEY_FEE if self.channel == "mobile_money" else PLAY_FEE
        return self.usd_gross * (1 - fee)

    @property
    def usd_net_monthly(self) -> float:
        """Normalised to a 30-day month; this is what MRR is built from."""
        return self.usd_net * 30.0 / self.days


PLANS: dict[str, Plan] = {p.code: p for p in [
    Plan("tz_week", "mobile_money", "TZS", 2_000, 7, "Wiki 1", "1 week"),
    Plan("tz_month", "mobile_money", "TZS", 7_000, 30, "Mwezi 1", "1 month"),
    Plan("tz_quarter", "mobile_money", "TZS", 18_000, 90, "Miezi 3", "3 months"),
    # Google Play: amount is the US list price; regional prices are set in Play Console.
    Plan("pro_monthly", "play", "USD", 4.99, 30, "Mwezi 1", "Monthly"),
    Plan("pro_yearly", "play", "USD", 29.99, 365, "Mwaka 1", "Yearly"),
]}


def get_plan(code: str) -> Plan:
    try:
        return PLANS[code]
    except KeyError:
        raise ValueError(f"unknown plan {code!r}; valid: {sorted(PLANS)}") from None
