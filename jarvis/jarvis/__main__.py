"""JARVIS command line: the back-office agents you (or cron) run every day.

  python -m jarvis daily                     # report + tomorrow's posts + next missing lessons
  python -m jarvis lessons --weeks 1-12 --lang sw
  python -m jarvis growth --days 7 --lang sw --market "Tanzania and Kenya"
  python -m jarvis report --advice
  python -m jarvis support "Nimelipa lakini Pro haijawaka" --phone 255754000000
  python -m jarvis tutor --lang sw           # talk to Mwalimu in the terminal
  python -m jarvis grant --phone 2557... --plan tz_month --ref manual-001   # manual payment fix
"""
from __future__ import annotations

import argparse
import json
import sys
from datetime import date
from pathlib import Path

from .agents.analyst import AnalystAgent, format_report
from .agents.content import CURRICULUM, LessonAgent
from .agents.growth import GrowthAgent
from .agents.support import SupportAgent
from .agents.tutor import SCENARIOS, LimitReached, TutorService
from .config import get_settings
from .db import DB
from .llm import AnthropicLLM
from .plans import get_plan


def _weeks(spec: str) -> list[int]:
    if "-" in spec:
        a, b = spec.split("-", 1)
        return list(range(int(a), int(b) + 1))
    return [int(x) for x in spec.split(",")]


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="jarvis", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    d = sub.add_parser("daily", help="run the daily routine")
    d.add_argument("--lang", default="sw")
    d.add_argument("--out", default="ops")
    d.add_argument("--lessons-per-day", type=int, default=1)

    l = sub.add_parser("lessons", help="generate weekly lesson packs")
    l.add_argument("--weeks", default=f"1-{len(CURRICULUM)}")
    l.add_argument("--lang", default="sw")
    l.add_argument("--level", default="A2")
    l.add_argument("--overwrite", action="store_true")

    g = sub.add_parser("growth", help="generate a marketing content calendar")
    g.add_argument("--days", type=int, default=7)
    g.add_argument("--lang", default="sw")
    g.add_argument("--market", default="Tanzania and Kenya (Swahili speakers)")
    g.add_argument("--out", default="ops/marketing")

    r = sub.add_parser("report", help="MRR / churn / cost report")
    r.add_argument("--advice", action="store_true")
    r.add_argument("--json", action="store_true")

    s = sub.add_parser("support", help="answer one customer message")
    s.add_argument("message")
    s.add_argument("--phone", default="")

    t = sub.add_parser("tutor", help="chat with the tutor in the terminal")
    t.add_argument("--lang", default="sw")
    t.add_argument("--scenario", default="free_talk", choices=list(SCENARIOS))
    t.add_argument("--phone", default="000-local-demo")

    gr = sub.add_parser("grant", help="manually grant Pro after checking a payment")
    gr.add_argument("--phone", required=True)
    gr.add_argument("--plan", required=True)
    gr.add_argument("--ref", required=True, help="unique reference, e.g. the M-Pesa transaction ID")

    a = ap.parse_args(argv)
    settings = get_settings()
    db = DB(settings.db_path)

    if a.cmd == "grant":
        user = db.user_by_phone(a.phone)
        if not user:
            print(f"no user with phone {a.phone}", file=sys.stderr)
            return 1
        plan = get_plan(a.plan)
        row = db.grant(user["id"], plan.code, plan.channel, plan.days, f"manual:{a.ref}", plan.usd_net_monthly)
        print(f"Pro until {row['expires_at']} for {a.phone}")
        return 0

    if a.cmd == "report" and not a.advice:
        rep = AnalystAgent(db, None, settings).report(with_advice=False)
        print(json.dumps(rep, indent=2) if a.json else format_report(rep))
        return 0

    llm = AnthropicLLM(settings.anthropic_api_key)

    if a.cmd == "report":
        rep = AnalystAgent(db, llm, settings).report(with_advice=True)
        print(json.dumps(rep, indent=2, ensure_ascii=False) if a.json else format_report(rep))
    elif a.cmd == "lessons":
        agent = LessonAgent(llm, settings)
        for w in _weeks(a.weeks):
            print(f"week {w}: {agent.generate_and_save(w, a.lang, a.level, a.overwrite)}")
    elif a.cmd == "growth":
        agent = GrowthAgent(llm, settings)
        md, csv_path = agent.save(agent.plan(a.days, a.lang, a.market), a.out)
        print(f"wrote {md} and {csv_path}")
    elif a.cmd == "support":
        print(json.dumps(SupportAgent(db, llm, settings).answer(a.message, a.phone), indent=2, ensure_ascii=False))
    elif a.cmd == "tutor":
        user = db.user_by_phone(a.phone)
        uid = user["id"] if user else db.create_user(a.phone, "Demo", a.lang)[0]
        tutor = TutorService(db, llm, settings)
        print("Mwalimu is listening. Type English (or your language). Ctrl-D to quit.")
        for line in sys.stdin:
            if not line.strip():
                continue
            try:
                out = tutor.chat(uid, line, a.scenario)
            except LimitReached:
                print("Daily limit reached.")
                break
            if out["corrected"]:
                print(f"  ✔ {out['corrected']}")
            for m in out["mistakes"]:
                print(f"  ✗ {m['wrong']} → {m['right']}  ({m['why']})")
            print(f"  💡 {out['tip']}   [score {out['score']}, level {out['level']}]")
            print(f"Mwalimu: {out['reply']}")
    elif a.cmd == "daily":
        rep = AnalystAgent(db, llm, settings).report(with_advice=True)
        print(format_report(rep))
        agent = LessonAgent(llm, settings)
        made = 0
        for w, _, _ in CURRICULUM:
            if made >= a.lessons_per_day:
                break
            if not agent.path(w, a.lang).exists():
                print(f"lesson: {agent.generate_and_save(w, a.lang)}")
                made += 1
        growth = GrowthAgent(llm, settings)
        md, _ = growth.save(growth.plan(1, a.lang), f"{a.out}/marketing")
        print(f"posts: {md}")
        tickets = db.open_escalations()
        if tickets:
            print(f"\n{len(tickets)} support ticket(s) need a human:")
            for t_ in tickets:
                print(f"  #{t_['id']} {t_['contact']}: {t_['reason']}")
        Path(a.out).mkdir(parents=True, exist_ok=True)
        (Path(a.out) / f"report_{date.today().isoformat()}.txt").write_text(format_report(rep), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
