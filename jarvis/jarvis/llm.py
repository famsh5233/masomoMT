"""Thin LLM layer. Every agent asks for *structured* output through a forced tool
call, so callers always get a validated dict back, never free text to parse.

Swap providers by implementing `LLM.structured`; agents never import a vendor SDK.
"""
from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from typing import Any, Protocol

# USD per 1M tokens: (input, output, cache_read). Estimates for cost tracking;
# confirm against the provider's current price page and override if needed.
PRICES: dict[str, tuple[float, float, float]] = {
    "claude-haiku-4-5": (1.00, 5.00, 0.10),
    "claude-sonnet-5": (3.00, 15.00, 0.30),
}
DEFAULT_PRICE = (3.00, 15.00, 0.30)


@dataclass
class LLMResult:
    data: dict[str, Any]
    input_tokens: int = 0
    output_tokens: int = 0
    cost_usd: float = 0.0


class LLM(Protocol):
    def structured(self, *, model: str, system: str, messages: list[dict], tool_name: str,
                   schema: dict, max_tokens: int = 1024) -> LLMResult: ...


def estimate_cost(model: str, input_tokens: int, output_tokens: int, cache_read: int = 0,
                  cache_write: int = 0) -> float:
    pin, pout, pcache = PRICES.get(model, DEFAULT_PRICE)
    return (input_tokens * pin + cache_write * pin * 1.25 + cache_read * pcache
            + output_tokens * pout) / 1_000_000


class AnthropicLLM:
    def __init__(self, api_key: str):
        if not api_key:
            raise RuntimeError("ANTHROPIC_API_KEY is not set")
        import anthropic  # imported lazily so tests don't need the key or network
        self.client = anthropic.Anthropic(api_key=api_key, max_retries=3)

    def structured(self, *, model: str, system: str, messages: list[dict], tool_name: str,
                   schema: dict, max_tokens: int = 1024) -> LLMResult:
        resp = self.client.messages.create(
            model=model,
            max_tokens=max_tokens,
            # Cache the (static) system prompt; it only kicks in above the model's
            # minimum cacheable length, below that it is a harmless no-op.
            system=[{"type": "text", "text": system, "cache_control": {"type": "ephemeral"}}],
            messages=messages,
            tools=[{"name": tool_name, "description": f"Return the {tool_name} result.",
                    "input_schema": schema}],
            tool_choice={"type": "tool", "name": tool_name},
        )
        block = next((b for b in resp.content if b.type == "tool_use"), None)
        if block is None:
            raise RuntimeError(f"model returned no {tool_name} tool call (stop_reason={resp.stop_reason})")
        u = resp.usage
        cache_read = getattr(u, "cache_read_input_tokens", 0) or 0
        cache_write = getattr(u, "cache_creation_input_tokens", 0) or 0
        return LLMResult(
            data=dict(block.input),
            input_tokens=u.input_tokens + cache_read + cache_write,
            output_tokens=u.output_tokens,
            cost_usd=estimate_cost(model, u.input_tokens, u.output_tokens, cache_read, cache_write),
        )


class FakeLLM:
    """Deterministic stand-in for tests and offline demos.

    `responders` maps tool_name -> function(messages) -> dict.
    """

    def __init__(self, responders: dict[str, Callable[[list[dict]], dict]]):
        self.responders = responders
        self.calls: list[dict] = []

    def structured(self, *, model: str, system: str, messages: list[dict], tool_name: str,
                   schema: dict, max_tokens: int = 1024) -> LLMResult:
        self.calls.append({"model": model, "system": system, "messages": messages, "tool": tool_name})
        data = self.responders[tool_name](messages)
        missing = [k for k in schema.get("required", []) if k not in data]
        if missing:
            raise AssertionError(f"fake {tool_name} response missing {missing}")
        return LLMResult(data=data, input_tokens=100, output_tokens=50,
                         cost_usd=estimate_cost(model, 100, 50))


class DemoLLM:
    """Rule-based stand-in used when JARVIS_LLM=demo (development only).

    It lets the app be demonstrated and tested end to end without an API key.
    The corrections are a handful of common learner mistakes, not real tutoring.
    """

    RULES = [
        (r"\bI working\b", "I am working", "Tumia 'am' kabla ya kitenzi chenye -ing."),
        (r"\b(he|she|it) (go|want|like|work|live)\b", None, "Kwa he/she/it ongeza -s kwenye kitenzi."),
        (r"\bI have (\d+) years\b", r"I am \1 years old", "Kwa umri tunasema 'I am ... years old'."),
        (r"\bI am agree\b", "I agree", "'Agree' ni kitenzi; hatutumii 'am' hapa."),
    ]
    QUESTIONS = [
        "Nice to meet you! What do you do every day?",
        "That sounds interesting. What do you like most about it?",
        "Great. Can you tell me about your plans for next year?",
        "Good answer! How would you greet a new customer?",
        "Well done. What English do you need most at work?",
    ]

    def structured(self, *, model: str, system: str, messages: list[dict], tool_name: str,
                   schema: dict, max_tokens: int = 1024) -> LLMResult:
        import re
        last = messages[-1]["content"] if messages else ""
        if tool_name == "tutor_turn":
            text, mistakes = last.strip(), []
            for pattern, repl, why in self.RULES:
                m = re.search(pattern, text, flags=re.IGNORECASE)
                if not m:
                    continue
                if repl is None:  # third-person -s
                    right = f"{m.group(1)} {m.group(2)}es" if m.group(2) == "go" else f"{m.group(1)} {m.group(2)}s"
                else:
                    right = m.expand(repl) if "\\" in repl else repl
                mistakes.append({"wrong": m.group(0), "right": right, "why": why})
                text = text[:m.start()] + right + text[m.end():]
            turn = sum(1 for m in messages if m["role"] == "user")
            data = {"reply": self.QUESTIONS[(turn - 1) % len(self.QUESTIONS)],
                    "corrected": text if mistakes else "", "mistakes": mistakes[:3],
                    "tip": "Umejitahidi! Endelea kuongea kila siku." if mistakes else "Safi sana! Sentensi yako ni sahihi.",
                    "score": max(40, 95 - 15 * len(mistakes)), "level": "A2"}
        elif tool_name == "support_reply":
            paid = any(w in last.lower() for w in ("lipa", "paid", "pesa", "refund"))
            data = {"reply": "Asante kwa ujumbe wako. Timu yetu itakagua na kukujibu hivi punde." if paid
                    else "Asante! Fungua Pro kwenye app kupata mazungumzo zaidi na masomo yote.",
                    "escalate": paid, "reason": f"Customer message: {last[:300]}" if paid else ""}
        elif tool_name == "growth_report":
            data = {"headline": "Demo mode", "diagnosis": "Demo data only.",
                    "actions": ["Connect a real API key", "Launch to existing users", "Track conversion daily"]}
        else:
            raise RuntimeError(f"demo LLM does not implement {tool_name}; set ANTHROPIC_API_KEY")
        return LLMResult(data=data)
