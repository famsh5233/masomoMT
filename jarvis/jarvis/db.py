"""SQLite persistence. One file, zero ops; move to Postgres past ~10k DAU.

All timestamps are ISO-8601 UTC strings so they sort lexicographically.
"""
from __future__ import annotations

import hashlib
import secrets
import sqlite3
from collections.abc import Iterator
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone

SCHEMA = """
PRAGMA journal_mode=WAL;
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY,
    phone TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL DEFAULT '',
    native_lang TEXT NOT NULL DEFAULT 'sw',
    country TEXT NOT NULL DEFAULT 'TZ',
    level TEXT NOT NULL DEFAULT 'A2',
    token_hash TEXT NOT NULL,
    created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS subscriptions (
    id INTEGER PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id),
    plan TEXT NOT NULL,
    channel TEXT NOT NULL,
    starts_at TEXT NOT NULL,
    expires_at TEXT NOT NULL,
    source_ref TEXT UNIQUE NOT NULL,
    usd_net_monthly REAL NOT NULL,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_subs_user ON subscriptions(user_id, expires_at);
CREATE TABLE IF NOT EXISTS payments (
    id INTEGER PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id),
    plan TEXT NOT NULL,
    provider TEXT NOT NULL,
    msisdn TEXT NOT NULL,
    amount REAL NOT NULL,
    currency TEXT NOT NULL,
    external_id TEXT UNIQUE NOT NULL,
    provider_ref TEXT,
    status TEXT NOT NULL DEFAULT 'pending',
    detail TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS messages (
    id INTEGER PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id),
    role TEXT NOT NULL,
    content TEXT NOT NULL,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_messages_user ON messages(user_id, id);
CREATE TABLE IF NOT EXISTS usage (
    user_id INTEGER NOT NULL REFERENCES users(id),
    day TEXT NOT NULL,
    turns INTEGER NOT NULL DEFAULT 0,
    input_tokens INTEGER NOT NULL DEFAULT 0,
    output_tokens INTEGER NOT NULL DEFAULT 0,
    cost_usd REAL NOT NULL DEFAULT 0,
    PRIMARY KEY (user_id, day)
);
CREATE TABLE IF NOT EXISTS otps (
    phone TEXT PRIMARY KEY,
    code_hash TEXT NOT NULL,
    expires_at TEXT NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 0,
    window_start TEXT NOT NULL,
    sends INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS escalations (
    id INTEGER PRIMARY KEY,
    user_id INTEGER,
    contact TEXT NOT NULL,
    reason TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'open',
    created_at TEXT NOT NULL
);
"""


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).isoformat(timespec="seconds")


def parse(ts: str) -> datetime:
    return datetime.fromisoformat(ts)


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


class DB:
    def __init__(self, path: str):
        self.path = path
        with self.conn() as c:
            c.executescript(SCHEMA)

    @contextmanager
    def conn(self) -> Iterator[sqlite3.Connection]:
        c = sqlite3.connect(self.path, timeout=10)
        c.row_factory = sqlite3.Row
        c.execute("PRAGMA foreign_keys=ON")
        try:
            yield c
            c.commit()
        except Exception:
            c.rollback()
            raise
        finally:
            c.close()

    # ---------- users ----------
    def create_user(self, phone: str, name: str = "", native_lang: str = "sw",
                    country: str = "TZ", level: str = "A2") -> tuple[int, str]:
        """Returns (user_id, bearer_token). The token is shown once; only its hash is stored."""
        token = secrets.token_urlsafe(32)
        with self.conn() as c:
            cur = c.execute(
                "INSERT INTO users(phone,name,native_lang,country,level,token_hash,created_at)"
                " VALUES(?,?,?,?,?,?,?)",
                (phone, name, native_lang, country, level, hash_token(token), iso(utcnow())))
            return cur.lastrowid, token

    def rotate_token(self, user_id: int) -> str:
        token = secrets.token_urlsafe(32)
        with self.conn() as c:
            c.execute("UPDATE users SET token_hash=? WHERE id=?", (hash_token(token), user_id))
        return token

    def user_by_token(self, token: str) -> sqlite3.Row | None:
        with self.conn() as c:
            return c.execute("SELECT * FROM users WHERE token_hash=?", (hash_token(token),)).fetchone()

    def user_by_phone(self, phone: str) -> sqlite3.Row | None:
        with self.conn() as c:
            return c.execute("SELECT * FROM users WHERE phone=?", (phone,)).fetchone()

    def user(self, user_id: int) -> sqlite3.Row | None:
        with self.conn() as c:
            return c.execute("SELECT * FROM users WHERE id=?", (user_id,)).fetchone()

    def update_profile(self, user_id: int, **fields: str) -> None:
        allowed = {k: v for k, v in fields.items() if k in ("name", "native_lang", "level", "country") and v is not None}
        if allowed:
            cols = ", ".join(f"{k}=?" for k in allowed)
            with self.conn() as c:
                c.execute(f"UPDATE users SET {cols} WHERE id=?", (*allowed.values(), user_id))

    # ---------- one-time login codes ----------
    def otp_issue(self, phone: str, code: str, ttl_minutes: int, max_sends_per_hour: int,
                  now: datetime | None = None) -> bool:
        """Stores a new code. Returns False when the phone has hit its hourly send limit."""
        now = now or utcnow()
        with self.conn() as c:
            row = c.execute("SELECT * FROM otps WHERE phone=?", (phone,)).fetchone()
            window_start, sends = iso(now), 0
            if row and parse(row["window_start"]) > now - timedelta(hours=1):
                window_start, sends = row["window_start"], row["sends"]
            if sends >= max_sends_per_hour:
                return False
            c.execute(
                "INSERT INTO otps(phone,code_hash,expires_at,attempts,window_start,sends) VALUES(?,?,?,0,?,?)"
                " ON CONFLICT(phone) DO UPDATE SET code_hash=excluded.code_hash, expires_at=excluded.expires_at,"
                " attempts=0, window_start=excluded.window_start, sends=excluded.sends",
                (phone, hash_token(f"{phone}:{code}"), iso(now + timedelta(minutes=ttl_minutes)),
                 window_start, sends + 1))
            return True

    def otp_check(self, phone: str, code: str, max_attempts: int, now: datetime | None = None) -> bool:
        """True once per issued code; wrong guesses count towards max_attempts."""
        now = now or utcnow()
        with self.conn() as c:
            row = c.execute("SELECT * FROM otps WHERE phone=?", (phone,)).fetchone()
            if not row or row["code_hash"] == "" or parse(row["expires_at"]) < now \
                    or row["attempts"] >= max_attempts:
                return False
            if not secrets.compare_digest(row["code_hash"], hash_token(f"{phone}:{code}")):
                c.execute("UPDATE otps SET attempts=attempts+1 WHERE phone=?", (phone,))
                return False
            c.execute("UPDATE otps SET code_hash='' WHERE phone=?", (phone,))
            return True

    def set_level(self, user_id: int, level: str) -> None:
        with self.conn() as c:
            c.execute("UPDATE users SET level=? WHERE id=?", (level, user_id))

    # ---------- subscriptions ----------
    def active_subscription(self, user_id: int, now: datetime | None = None) -> sqlite3.Row | None:
        now_s = iso(now or utcnow())
        with self.conn() as c:
            return c.execute(
                "SELECT * FROM subscriptions WHERE user_id=? AND starts_at<=? AND expires_at>?"
                " ORDER BY expires_at DESC LIMIT 1", (user_id, now_s, now_s)).fetchone()

    def grant(self, user_id: int, plan: str, channel: str, days: int, source_ref: str,
              usd_net_monthly: float, now: datetime | None = None,
              expires_at: datetime | None = None) -> sqlite3.Row:
        """Idempotent on source_ref. Mobile-money purchases stack on top of remaining time."""
        now = now or utcnow()
        with self.conn() as c:
            existing = c.execute("SELECT * FROM subscriptions WHERE source_ref=?", (source_ref,)).fetchone()
            if existing:
                if expires_at is not None and iso(expires_at) > existing["expires_at"]:
                    # Play renewals keep the same purchase token but move expiry forward.
                    c.execute("UPDATE subscriptions SET expires_at=? WHERE id=?",
                              (iso(expires_at), existing["id"]))
                    return c.execute("SELECT * FROM subscriptions WHERE id=?", (existing["id"],)).fetchone()
                return existing
            last = c.execute("SELECT MAX(expires_at) m FROM subscriptions WHERE user_id=?",
                             (user_id,)).fetchone()["m"]
            start = max(now, parse(last)) if last else now
            end = expires_at or (start + timedelta(days=days))
            cur = c.execute(
                "INSERT INTO subscriptions(user_id,plan,channel,starts_at,expires_at,source_ref,"
                "usd_net_monthly,created_at) VALUES(?,?,?,?,?,?,?,?)",
                (user_id, plan, channel, iso(start), iso(end), source_ref, usd_net_monthly, iso(now)))
            return c.execute("SELECT * FROM subscriptions WHERE id=?", (cur.lastrowid,)).fetchone()

    def subscriptions(self) -> list[sqlite3.Row]:
        with self.conn() as c:
            return c.execute("SELECT * FROM subscriptions ORDER BY id").fetchall()

    # ---------- payments ----------
    def create_payment(self, user_id: int, plan: str, provider: str, msisdn: str,
                       amount: float, currency: str) -> str:
        external_id = "MSM" + secrets.token_hex(8).upper()
        now = iso(utcnow())
        with self.conn() as c:
            c.execute(
                "INSERT INTO payments(user_id,plan,provider,msisdn,amount,currency,external_id,"
                "status,created_at,updated_at) VALUES(?,?,?,?,?,?,?,'pending',?,?)",
                (user_id, plan, provider, msisdn, amount, currency, external_id, now, now))
        return external_id

    def payment(self, external_id: str) -> sqlite3.Row | None:
        with self.conn() as c:
            return c.execute("SELECT * FROM payments WHERE external_id=?", (external_id,)).fetchone()

    def update_payment(self, external_id: str, status: str, provider_ref: str | None = None,
                       detail: str | None = None) -> None:
        with self.conn() as c:
            c.execute(
                "UPDATE payments SET status=?, provider_ref=COALESCE(?,provider_ref),"
                " detail=COALESCE(?,detail), updated_at=? WHERE external_id=?",
                (status, provider_ref, detail, iso(utcnow()), external_id))

    def set_provider_ref(self, external_id: str, provider_ref: str | None) -> None:
        if provider_ref:
            with self.conn() as c:
                c.execute("UPDATE payments SET provider_ref=? WHERE external_id=? AND provider_ref IS NULL",
                          (provider_ref, external_id))

    def payments_for(self, user_id: int, limit: int = 5) -> list[sqlite3.Row]:
        with self.conn() as c:
            return c.execute("SELECT * FROM payments WHERE user_id=? ORDER BY id DESC LIMIT ?",
                             (user_id, limit)).fetchall()

    # ---------- conversation + usage ----------
    def add_message(self, user_id: int, role: str, content: str) -> None:
        with self.conn() as c:
            c.execute("INSERT INTO messages(user_id,role,content,created_at) VALUES(?,?,?,?)",
                      (user_id, role, content, iso(utcnow())))

    def history(self, user_id: int, turns: int) -> list[dict]:
        with self.conn() as c:
            rows = c.execute("SELECT role, content FROM messages WHERE user_id=? ORDER BY id DESC LIMIT ?",
                             (user_id, turns * 2)).fetchall()
        msgs = [{"role": r["role"], "content": r["content"]} for r in reversed(rows)]
        # The API requires the first message to be from the user.
        while msgs and msgs[0]["role"] != "user":
            msgs.pop(0)
        return msgs

    def usage_today(self, user_id: int, day: str | None = None) -> sqlite3.Row | None:
        day = day or utcnow().date().isoformat()
        with self.conn() as c:
            return c.execute("SELECT * FROM usage WHERE user_id=? AND day=?", (user_id, day)).fetchone()

    def add_usage(self, user_id: int, input_tokens: int, output_tokens: int, cost_usd: float,
                  day: str | None = None) -> None:
        day = day or utcnow().date().isoformat()
        with self.conn() as c:
            c.execute(
                "INSERT INTO usage(user_id,day,turns,input_tokens,output_tokens,cost_usd) VALUES(?,?,1,?,?,?)"
                " ON CONFLICT(user_id,day) DO UPDATE SET turns=turns+1,"
                " input_tokens=input_tokens+excluded.input_tokens,"
                " output_tokens=output_tokens+excluded.output_tokens,"
                " cost_usd=cost_usd+excluded.cost_usd",
                (user_id, day, input_tokens, output_tokens, cost_usd))

    def ai_cost_since(self, day: str) -> float:
        with self.conn() as c:
            return c.execute("SELECT COALESCE(SUM(cost_usd),0) s FROM usage WHERE day>=?", (day,)).fetchone()["s"]

    def active_users_since(self, day: str) -> int:
        with self.conn() as c:
            return c.execute("SELECT COUNT(DISTINCT user_id) n FROM usage WHERE day>=?", (day,)).fetchone()["n"]

    def user_count(self) -> int:
        with self.conn() as c:
            return c.execute("SELECT COUNT(*) n FROM users").fetchone()["n"]

    # ---------- support ----------
    def escalate(self, contact: str, reason: str, user_id: int | None = None) -> int:
        with self.conn() as c:
            cur = c.execute("INSERT INTO escalations(user_id,contact,reason,created_at) VALUES(?,?,?,?)",
                            (user_id, contact, reason, iso(utcnow())))
            return cur.lastrowid

    def open_escalations(self) -> list[sqlite3.Row]:
        with self.conn() as c:
            return c.execute("SELECT * FROM escalations WHERE status='open' ORDER BY id").fetchall()
