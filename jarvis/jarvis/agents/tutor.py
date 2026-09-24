"""Mwalimu: the AI English speaking tutor. This is the product people pay for.

The app does speech-to-text and text-to-speech on the device (speech_to_text and
flutter_tts are already in pubspec.yaml), so the server only pays for text tokens.
That keeps the AI cost per paying user below the local price.
"""
from __future__ import annotations

from dataclasses import dataclass

from ..config import Settings
from ..db import DB
from ..llm import LLM
from . import LEVELS, lang_name

SCENARIOS = {
    "free_talk": "a friendly everyday conversation about the learner's life, work and plans",
    "job_interview": "a job interview for a role the learner wants; you are the interviewer",
    "customer_service": "the learner serves you as a customer in a shop, bank or office",
    "tourism": "the learner is a tour guide, hotel or restaurant worker and you are a foreign tourist",
    "phone_call": "a business phone call: booking, following up, or solving a problem",
    "small_business": "the learner pitches and sells their product or service to you, a foreign buyer",
}

SCHEMA = {
    "type": "object",
    "properties": {
        "reply": {"type": "string", "description": "Your spoken reply in simple English, max 45 words, ending with one question that keeps the conversation going."},
        "corrected": {"type": "string", "description": "The learner's last message rewritten in natural, correct English. Empty string if it was already correct."},
        "mistakes": {
            "type": "array", "maxItems": 3,
            "items": {"type": "object", "properties": {
                "wrong": {"type": "string"}, "right": {"type": "string"},
                "why": {"type": "string", "description": "One short sentence, in the learner's native language."}},
                "required": ["wrong", "right", "why"]}},
        "tip": {"type": "string", "description": "One short encouraging tip in the learner's native language."},
        "score": {"type": "integer", "minimum": 0, "maximum": 100, "description": "How clear and correct the learner's last message was."},
        "level": {"type": "string", "enum": LEVELS, "description": "Your estimate of the learner's CEFR level."},
    },
    "required": ["reply", "corrected", "mistakes", "tip", "score", "level"],
}


def system_prompt(native: str, level: str, scenario: str) -> str:
    return f"""You are Mwalimu, a warm and patient English speaking coach inside the Masomo app.
The learner's native language is {native}. Their current English level is {level} (CEFR).
Practice scenario: {SCENARIOS.get(scenario, SCENARIOS['free_talk'])}.

Rules:
- Speak only simple, natural English in `reply`, matched to level {level}. Short sentences. Max 45 words.
- Always end `reply` with exactly one question so the learner keeps speaking.
- The learner's text comes from speech recognition: ignore missing punctuation and capital letters, and do not count them as mistakes.
- Correct at most 3 real mistakes (grammar, word choice, word order). Explanations go in {native}, one short sentence each.
- If the learner writes in {native}, answer in English and show them how to say it in English in `corrected`.
- Be encouraging. Never shame. Praise one thing they did well in `tip` when possible.
- Only change `level` from {level} when the evidence is clear.
- Stay on English learning. Refuse politely anything unsafe, sexual, hateful or about cheating on exams."""


class LimitReached(Exception):
    pass


@dataclass
class TutorService:
    db: DB
    llm: LLM
    settings: Settings

    def daily_limit(self, user_id: int) -> int:
        paid = self.db.active_subscription(user_id) is not None
        return self.settings.paid_turns_per_day if paid else self.settings.free_turns_per_day

    def turns_left(self, user_id: int) -> int:
        used = self.db.usage_today(user_id)
        return max(0, self.daily_limit(user_id) - (used["turns"] if used else 0))

    def chat(self, user_id: int, text: str, scenario: str = "free_talk") -> dict:
        text = text.strip()[:600]
        if not text:
            raise ValueError("empty message")
        # Take the turn before calling the model, atomically, so parallel requests can't exceed the limit.
        if not self.db.reserve_turn(user_id, self.daily_limit(user_id)):
            raise LimitReached()
        user = self.db.user(user_id)
        messages = self.db.history(user_id, self.settings.history_turns)
        messages.append({"role": "user", "content": text})
        try:
            result = self.llm.structured(
                model=self.settings.tutor_model,
                system=system_prompt(lang_name(user["native_lang"]), user["level"], scenario),
                messages=messages, tool_name="tutor_turn", schema=SCHEMA, max_tokens=500)
        except Exception:
            self.db.refund_turn(user_id)  # a failed call should not cost the learner a turn
            raise
        data = result.data
        # Persist only after a successful call so history never has a dangling user turn.
        self.db.add_message(user_id, "user", text)
        self.db.add_message(user_id, "assistant", data["reply"])
        self.db.add_usage(user_id, result.input_tokens, result.output_tokens, result.cost_usd)
        if data.get("level") in LEVELS and data["level"] != user["level"]:
            self.db.set_level(user_id, data["level"])
        data["turns_left"] = self.turns_left(user_id)
        return data
