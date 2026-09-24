"""Runtime configuration, read once from environment variables.

Every value has a safe default so tests and local runs work without a .env file.
Secrets (API keys) default to empty strings; features that need them fail loudly
at call time instead of at import time.
"""
from __future__ import annotations

import os
from dataclasses import dataclass, field


def _int(name: str, default: int) -> int:
    return int(os.environ.get(name, default))


@dataclass(frozen=True)
class Settings:
    # --- LLM ---
    anthropic_api_key: str = field(default_factory=lambda: os.environ.get("ANTHROPIC_API_KEY", ""))
    # Cheap, fast model for the high-volume tutor loop.
    tutor_model: str = field(default_factory=lambda: os.environ.get("JARVIS_TUTOR_MODEL", "claude-haiku-4-5"))
    # Stronger model for low-volume back-office work (lessons, marketing, reports).
    office_model: str = field(default_factory=lambda: os.environ.get("JARVIS_OFFICE_MODEL", "claude-sonnet-5"))

    # --- Storage ---
    db_path: str = field(default_factory=lambda: os.environ.get("JARVIS_DB", "jarvis.db"))
    content_dir: str = field(default_factory=lambda: os.environ.get("JARVIS_CONTENT_DIR", "content"))

    # --- Usage limits (protect margins: AI cost must stay well under price) ---
    free_turns_per_day: int = field(default_factory=lambda: _int("JARVIS_FREE_TURNS", 10))
    paid_turns_per_day: int = field(default_factory=lambda: _int("JARVIS_PAID_TURNS", 40))
    history_turns: int = field(default_factory=lambda: _int("JARVIS_HISTORY_TURNS", 6))
    free_lesson_weeks: int = field(default_factory=lambda: _int("JARVIS_FREE_WEEKS", 1))

    # --- Environment ---
    # "dev" allows the demo LLM and returns login codes in API responses; never use it in production.
    env: str = field(default_factory=lambda: os.environ.get("JARVIS_ENV", "prod"))
    llm_mode: str = field(default_factory=lambda: os.environ.get("JARVIS_LLM", "anthropic"))
    cors_origins: str = field(default_factory=lambda: os.environ.get("JARVIS_CORS_ORIGINS", ""))

    # --- Login by SMS code ---
    sms_provider: str = field(default_factory=lambda: os.environ.get("JARVIS_SMS_PROVIDER", "console"))
    # Only send codes to these country calling codes; protects against SMS-pumping fraud.
    otp_country_codes: str = field(default_factory=lambda: os.environ.get("JARVIS_OTP_COUNTRIES", "255,254,256"))
    otp_ttl_minutes: int = field(default_factory=lambda: _int("JARVIS_OTP_TTL_MIN", 10))
    otp_max_sends_per_hour: int = field(default_factory=lambda: _int("JARVIS_OTP_SENDS_PER_HOUR", 3))
    otp_max_attempts: int = field(default_factory=lambda: _int("JARVIS_OTP_ATTEMPTS", 5))
    # Spend guards against SMS-pumping fraud: per network address per hour, and across everyone per day.
    otp_per_ip_per_hour: int = field(default_factory=lambda: _int("JARVIS_OTP_PER_IP_HOUR", 10))
    otp_daily_cap: int = field(default_factory=lambda: _int("JARVIS_OTP_DAILY_CAP", 1000))
    support_per_day: int = field(default_factory=lambda: _int("JARVIS_SUPPORT_PER_DAY", 20))
    at_username: str = field(default_factory=lambda: os.environ.get("AFRICASTALKING_USERNAME", ""))
    at_api_key: str = field(default_factory=lambda: os.environ.get("AFRICASTALKING_API_KEY", ""))
    at_sender_id: str = field(default_factory=lambda: os.environ.get("AFRICASTALKING_SENDER_ID", ""))

    # --- Existing Masomo video lessons (old masomo.co.tz backend) ---
    legacy_videos_url: str = field(default_factory=lambda: os.environ.get(
        "JARVIS_LEGACY_VIDEOS_URL", "https://masomo.co.tz/api/week_videos?week={week}"))
    video_weeks: int = field(default_factory=lambda: _int("JARVIS_VIDEO_WEEKS", 12))
    free_video_weeks: int = field(default_factory=lambda: _int("JARVIS_FREE_VIDEO_WEEKS", 1))

    # --- Admin ---
    admin_key: str = field(default_factory=lambda: os.environ.get("JARVIS_ADMIN_KEY", ""))

    # --- AzamPay (Tanzania mobile money: M-Pesa, Tigo/Mixx, Airtel, Halopesa, AzamPesa) ---
    azampay_app_name: str = field(default_factory=lambda: os.environ.get("AZAMPAY_APP_NAME", ""))
    azampay_client_id: str = field(default_factory=lambda: os.environ.get("AZAMPAY_CLIENT_ID", ""))
    azampay_client_secret: str = field(default_factory=lambda: os.environ.get("AZAMPAY_CLIENT_SECRET", ""))
    azampay_api_key: str = field(default_factory=lambda: os.environ.get("AZAMPAY_API_KEY", ""))
    azampay_auth_url: str = field(default_factory=lambda: os.environ.get(
        "AZAMPAY_AUTH_URL", "https://authenticator-sandbox.azampay.co.tz"))
    azampay_checkout_url: str = field(default_factory=lambda: os.environ.get(
        "AZAMPAY_CHECKOUT_URL", "https://sandbox.azampay.co.tz"))
    # AzamPay callbacks are not signed, so the callback URL registered with
    # AzamPay must carry this secret as ?key=... and we also match amount + reference.
    azampay_callback_secret: str = field(default_factory=lambda: os.environ.get("AZAMPAY_CALLBACK_SECRET", ""))

    # --- Google Play (global card / carrier billing) ---
    play_package_name: str = field(default_factory=lambda: os.environ.get("PLAY_PACKAGE_NAME", ""))
    play_service_account_file: str = field(default_factory=lambda: os.environ.get("PLAY_SERVICE_ACCOUNT_FILE", ""))


def get_settings() -> Settings:
    return Settings()
