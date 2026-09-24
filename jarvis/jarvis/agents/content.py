"""Lesson factory: writes one week of lessons as JSON the app (and the tutor) can use.

The curriculum is built around English that earns money: jobs, customers, tourists,
phone calls. That is the promise people pay for, not grammar for its own sake.
"""
from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

from ..config import Settings
from ..llm import LLM
from . import lang_name

CURRICULUM = [
    # (week, theme, practice scenario for the tutor)
    (1, "Introducing yourself and small talk", "free_talk"),
    (2, "Talking about your work and daily routine", "free_talk"),
    (3, "Serving a customer politely", "customer_service"),
    (4, "Numbers, prices and money", "customer_service"),
    (5, "Welcoming tourists and giving directions", "tourism"),
    (6, "Hotels, restaurants and food", "tourism"),
    (7, "Making and answering phone calls", "phone_call"),
    (8, "Solving problems and handling complaints", "customer_service"),
    (9, "Job interview: talking about your experience", "job_interview"),
    (10, "Job interview: strengths, weaknesses and questions", "job_interview"),
    (11, "Selling your product or service", "small_business"),
    (12, "Writing short professional messages and emails", "small_business"),
]

SCHEMA = {
    "type": "object",
    "properties": {
        "title": {"type": "string"},
        "objectives": {"type": "array", "items": {"type": "string"}, "minItems": 3, "maxItems": 4},
        "vocabulary": {"type": "array", "minItems": 10, "maxItems": 12, "items": {
            "type": "object", "properties": {
                "word": {"type": "string"}, "meaning": {"type": "string", "description": "in the learner's language"},
                "example": {"type": "string"}}, "required": ["word", "meaning", "example"]}},
        "phrases": {"type": "array", "minItems": 6, "maxItems": 8, "items": {
            "type": "object", "properties": {
                "english": {"type": "string"}, "meaning": {"type": "string"}},
            "required": ["english", "meaning"]}},
        "dialogue": {"type": "array", "minItems": 8, "maxItems": 12, "items": {
            "type": "object", "properties": {"speaker": {"type": "string"}, "line": {"type": "string"}},
            "required": ["speaker", "line"]}},
        "grammar": {"type": "object", "properties": {
            "point": {"type": "string"}, "explanation": {"type": "string", "description": "in the learner's language"},
            "examples": {"type": "array", "items": {"type": "string"}, "minItems": 3, "maxItems": 5}},
            "required": ["point", "explanation", "examples"]},
        "speaking_tasks": {"type": "array", "minItems": 3, "maxItems": 5, "items": {"type": "string"}},
        "quiz": {"type": "array", "minItems": 5, "maxItems": 8, "items": {
            "type": "object", "properties": {
                "question": {"type": "string"}, "options": {"type": "array", "items": {"type": "string"},
                                                            "minItems": 3, "maxItems": 4},
                "answer_index": {"type": "integer", "minimum": 0}},
            "required": ["question", "options", "answer_index"]}},
    },
    "required": ["title", "objectives", "vocabulary", "phrases", "dialogue", "grammar", "speaking_tasks", "quiz"],
}


@dataclass
class LessonAgent:
    llm: LLM
    settings: Settings

    def generate(self, week: int, native_lang: str = "sw", level: str = "A2") -> dict:
        try:
            _, theme, scenario = CURRICULUM[week - 1]
        except IndexError:
            raise ValueError(f"week must be 1..{len(CURRICULUM)}") from None
        native = lang_name(native_lang)
        system = (
            "You are a senior ESL curriculum designer who writes practical English lessons for adults "
            f"in emerging markets whose native language is {native}. Lessons must be culturally relevant "
            "(local names, places, jobs, prices), accurate, and immediately useful at work. "
            f"Translations and explanations go in {native}; everything else in clear English at CEFR {level}.")
        prompt = (f"Write week {week} of the Masomo speaking course. Theme: {theme}. "
                  "The dialogue must model exactly the situation the learner will role-play next "
                  "with the AI tutor. Quiz answers must be unambiguous.")
        result = self.llm.structured(model=self.settings.office_model, system=system,
                                     messages=[{"role": "user", "content": prompt}],
                                     tool_name="lesson", schema=SCHEMA, max_tokens=4000)
        lesson = result.data
        for q in lesson["quiz"]:
            if not 0 <= q["answer_index"] < len(q["options"]):
                raise ValueError(f"invalid quiz answer_index in week {week}: {q}")
        lesson.update({"week": week, "theme": theme, "scenario": scenario,
                       "native_lang": native_lang, "level": level})
        return lesson

    def path(self, week: int, native_lang: str = "sw") -> Path:
        return Path(self.settings.content_dir) / native_lang / f"week_{week:02d}.json"

    def generate_and_save(self, week: int, native_lang: str = "sw", level: str = "A2",
                          overwrite: bool = False) -> Path:
        path = self.path(week, native_lang)
        if path.exists() and not overwrite:
            return path
        lesson = self.generate(week, native_lang, level)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(lesson, ensure_ascii=False, indent=2), encoding="utf-8")
        return path


# Hand-written lessons that ship with the server, so the free tier works before any
# lesson has been generated. Generated or edited files in content_dir take precedence.
SEED_DIR = Path(__file__).resolve().parent.parent / "seed_content"


def load_lesson(content_dir: str, week: int, native_lang: str = "sw") -> dict | None:
    name = f"week_{week:02d}.json"
    for path in (Path(content_dir) / native_lang / name, SEED_DIR / native_lang / name):
        if path.exists():
            return json.loads(path.read_text(encoding="utf-8"))
    return None


def lesson_index(content_dir: str, native_lang: str, free_weeks: int, pro: bool) -> list[dict]:
    out = []
    for week, theme, scenario in CURRICULUM:
        published = load_lesson(content_dir, week, native_lang) is not None or \
            load_lesson(content_dir, week, "sw") is not None
        out.append({"week": week, "theme": theme, "scenario": scenario, "published": published,
                    "locked": week > free_weeks and not pro})
    return out
