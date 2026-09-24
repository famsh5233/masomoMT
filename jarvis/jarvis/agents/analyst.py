"""Analyst agent: the daily numbers that decide everything, plus what to do next.

Metrics are computed in plain Python (never by the model). The model only turns
them into a short action list.
"""
from __future__ import annotations

import math
from dataclasses import dataclass
from datetime import datetime, timedelta

from ..config import Settings
from ..db import DB, iso, parse, utcnow
from ..llm import LLM

TARGET_MRR = 1000.0


def compute_metrics(db: DB, now: datetime | None = None) -> dict:
    now = now or utcnow()
    now_s, d30 = iso(now), (now - timedelta(days=30))
    by_user: dict[int, list] = {}
    for s in db.subscriptions():
        by_user.setdefault(s["user_id"], []).append(s)

    mrr, paying, churned, new_paid = 0.0, 0, 0, 0
    plan_mix: dict[str, int] = {}
    for subs in by_user.values():
        active = [s for s in subs if s["starts_at"] <= now_s < s["expires_at"]]
        if active:
            cur = max(active, key=lambda s: s["expires_at"])
            mrr += cur["usd_net_monthly"]
            paying += 1
            plan_mix[cur["plan"]] = plan_mix.get(cur["plan"], 0) + 1
            if min(parse(s["created_at"]) for s in subs) >= d30:
                new_paid += 1
        else:
            last_end = max(parse(s["expires_at"]) for s in subs)
            if d30 <= last_end <= now:
                churned += 1

    day30 = d30.date().isoformat()
    ai_cost = db.ai_cost_since(day30)
    active30 = db.active_users_since(day30)
    arpu = mrr / paying if paying else 0.0
    start_of_period = paying - new_paid + churned
    return {
        "as_of": now_s,
        "mrr_usd": round(mrr, 2),
        "target_mrr_usd": TARGET_MRR,
        "progress_pct": round(100 * mrr / TARGET_MRR, 1),
        "paying_users": paying,
        "arpu_usd": round(arpu, 2),
        "paying_users_needed_at_current_arpu": math.ceil(TARGET_MRR / arpu) if arpu else None,
        "plan_mix": plan_mix,
        "new_paying_30d": new_paid,
        "churned_30d": churned,
        "churn_rate_30d_pct": round(100 * churned / start_of_period, 1) if start_of_period else 0.0,
        "total_users": db.user_count(),
        "active_users_30d": active30,
        "active_users_7d": db.active_users_since((now - timedelta(days=7)).date().isoformat()),
        "free_to_paid_pct": round(100 * paying / active30, 1) if active30 else 0.0,
        "ai_cost_30d_usd": round(ai_cost, 2),
        "gross_margin_pct": round(100 * (mrr - ai_cost) / mrr, 1) if mrr else None,
        "open_support_tickets": len(db.open_escalations()),
    }


SCHEMA = {
    "type": "object",
    "properties": {
        "headline": {"type": "string"},
        "diagnosis": {"type": "string", "description": "What the numbers say is the bottleneck: acquisition, activation, conversion, retention or cost."},
        "actions": {"type": "array", "minItems": 3, "maxItems": 5, "items": {"type": "string"},
                    "description": "Concrete things to do in the next 7 days, highest impact first."},
    },
    "required": ["headline", "diagnosis", "actions"],
}


@dataclass
class AnalystAgent:
    db: DB
    llm: LLM | None
    settings: Settings

    def report(self, with_advice: bool = True) -> dict:
        metrics = compute_metrics(self.db)
        out = {"metrics": metrics}
        if with_advice and self.llm is not None:
            system = ("You are a growth analyst for a low-price subscription app in emerging markets. "
                      "Benchmarks: freemium education apps convert ~2-5% of active users; weekly plans "
                      "churn fast; AI cost must stay under 35% of revenue. Be blunt and specific.")
            result = self.llm.structured(model=self.settings.office_model, system=system,
                                         messages=[{"role": "user", "content": f"Metrics: {metrics}"}],
                                         tool_name="growth_report", schema=SCHEMA, max_tokens=1200)
            out["advice"] = result.data
        return out


def format_report(rep: dict) -> str:
    m = rep["metrics"]
    lines = [
        f"MRR ${m['mrr_usd']:,.2f} / ${m['target_mrr_usd']:,.0f} ({m['progress_pct']}%)",
        f"Paying {m['paying_users']} | ARPU ${m['arpu_usd']} | need {m['paying_users_needed_at_current_arpu']} at this ARPU",
        f"New paid 30d {m['new_paying_30d']} | churned 30d {m['churned_30d']} ({m['churn_rate_30d_pct']}%)",
        (f"Users {m['total_users']} | active 7d {m['active_users_7d']} | active 30d {m['active_users_30d']} "
         f"| free->paid {m['free_to_paid_pct']}%"),
        f"AI cost 30d ${m['ai_cost_30d_usd']} | gross margin {m['gross_margin_pct']}%",
        f"Open support tickets {m['open_support_tickets']} | plan mix {m['plan_mix']}",
    ]
    if "advice" in rep:
        a = rep["advice"]
        lines += ["", a["headline"], a["diagnosis"], *[f"  {i}. {x}" for i, x in enumerate(a["actions"], 1)]]
    return "\n".join(lines)
