"""Growth agent: turns the marketing plan into ready-to-post content every day.

Output is a content calendar (Markdown + CSV) a human posts or schedules. It does
not auto-post: platform APIs for TikTok/WhatsApp/Facebook each need app review,
and a human glance before publishing protects the brand.
"""
from __future__ import annotations

import csv
import json
from dataclasses import dataclass
from datetime import date, timedelta
from pathlib import Path

from ..config import Settings
from ..llm import LLM
from . import lang_name

CHANNELS = ["tiktok", "instagram_reels", "youtube_shorts", "facebook", "whatsapp_status", "whatsapp_channel"]

SCHEMA = {
    "type": "object",
    "properties": {
        "posts": {"type": "array", "items": {"type": "object", "properties": {
            "day": {"type": "integer", "minimum": 1},
            "channel": {"type": "string", "enum": CHANNELS},
            "format": {"type": "string", "description": "e.g. 30s talking-head video, carousel, text status"},
            "hook": {"type": "string", "description": "first 2 seconds / first line; must stop the scroll"},
            "script": {"type": "string", "description": "full script or post body"},
            "caption": {"type": "string"},
            "hashtags": {"type": "array", "items": {"type": "string"}, "maxItems": 6},
            "cta": {"type": "string"},
        }, "required": ["day", "channel", "format", "hook", "script", "caption", "hashtags", "cta"]}},
        "ads": {"type": "array", "minItems": 3, "maxItems": 5, "items": {"type": "object", "properties": {
            "platform": {"type": "string", "enum": ["meta", "tiktok", "google_app_campaign"]},
            "headline": {"type": "string"}, "primary_text": {"type": "string"},
            "angle": {"type": "string", "description": "e.g. job, confidence, price, tourism income"}},
            "required": ["platform", "headline", "primary_text", "angle"]}},
    },
    "required": ["posts", "ads"],
}

BRIEF = """Product: Masomo - an app where you practise SPEAKING English with an AI teacher (Mwalimu)
that corrects you and explains in {native}. Also weekly video lessons for work English:
customers, tourists, phone calls, job interviews.
Price: free 10 conversations a day; Pro from TSh 2,000 per week via M-Pesa, Mixx by Yas, Airtel Money,
HaloPesa, or Google Play elsewhere.
Audience: {market}. Ages 18-35: job seekers, students leaving school, boda/bajaji and
shop workers, hotel and tourism staff, small business owners, people abroad for work.
Pain: understand English but freeze when speaking; scared of being laughed at; English = better job.
Brand voice: warm, funny, local, confident. Mix {native} and English naturally (code-switching).
Download link placeholder: {{LINK}}. Never promise guaranteed jobs or visas."""


@dataclass
class GrowthAgent:
    llm: LLM
    settings: Settings

    def plan(self, days: int = 7, native_lang: str = "sw",
             market: str = "Tanzania and Kenya (Swahili speakers)", start: date | None = None) -> dict:
        native = lang_name(native_lang)
        system = ("You are a performance marketer and short-video creator for consumer apps in emerging "
                  "markets. You write hooks that stop the scroll, scripts one person can film on a phone "
                  "in 10 minutes, and every post ends with a clear call to action.")
        prompt = (BRIEF.format(native=native, market=market) +
                  f"\n\nCreate a {days}-day content calendar: 2 posts per day across the channels "
                  "(mostly TikTok/Reels/Shorts; use WhatsApp for offers and reminders). Rotate formats: "
                  "'say this not that' corrections, funny mistakes skits, job-interview answers, "
                  "customer role-plays with the AI, learner success stories (as templates to fill with "
                  "real learners), price/offer posts max once every 3 days. Also write paid ad variants.")
        result = self.llm.structured(model=self.settings.office_model, system=system,
                                     messages=[{"role": "user", "content": prompt}],
                                     tool_name="content_calendar", schema=SCHEMA, max_tokens=8000)
        cal = result.data
        start = start or date.today() + timedelta(days=1)
        for p in cal["posts"]:
            p["date"] = (start + timedelta(days=p["day"] - 1)).isoformat()
        cal["posts"].sort(key=lambda p: (p["day"], p["channel"]))
        return cal

    def save(self, cal: dict, out_dir: str) -> tuple[Path, Path]:
        out = Path(out_dir)
        out.mkdir(parents=True, exist_ok=True)
        first = cal["posts"][0]["date"] if cal["posts"] else date.today().isoformat()
        md_path, csv_path = out / f"calendar_{first}.md", out / f"calendar_{first}.csv"
        lines = [f"# Content calendar from {first}\n"]
        for p in cal["posts"]:
            lines += [f"## {p['date']} - {p['channel']} ({p['format']})", f"**Hook:** {p['hook']}", "",
                      p["script"], "", f"**Caption:** {p['caption']}", f"**Hashtags:** {' '.join(p['hashtags'])}",
                      f"**CTA:** {p['cta']}", ""]
        lines.append("# Paid ad variants\n")
        for a in cal["ads"]:
            lines += [f"- **{a['platform']} / {a['angle']}**: {a['headline']} - {a['primary_text']}"]
        md_path.write_text("\n".join(lines), encoding="utf-8")
        with csv_path.open("w", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            w.writerow(["date", "channel", "format", "hook", "script", "caption", "hashtags", "cta"])
            for p in cal["posts"]:
                w.writerow([p["date"], p["channel"], p["format"], p["hook"], p["script"],
                            p["caption"], " ".join(p["hashtags"]), p["cta"]])
        (out / f"calendar_{first}.json").write_text(json.dumps(cal, ensure_ascii=False, indent=2),
                                                    encoding="utf-8")
        return md_path, csv_path
