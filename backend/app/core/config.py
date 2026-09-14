from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path

from pydantic import Field, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=("../.env", ".env"),
        env_file_encoding="utf-8",
        extra="ignore",
    )

    app_env: str = "dev"
    log_level: str = "INFO"

    jwt_secret: str = Field(min_length=32)
    jwt_secrets: str | None = None  # JSON list [new, old]

    gemini_api_key: str = Field(min_length=1)
    groq_api_key: str = Field(min_length=1)
    restore_token: str = Field(min_length=20)

    # Pack locked text-embedding-004; Google shut it down 2026-01-14 → gemini-embedding-001.
    # Request outputDimensionality=768 so Chroma dim stays pack-locked.
    embed_model: str = "gemini-embedding-001@PINNED"
    # Pack locked gemini-2.5-flash; Google 404s that for new keys (2026-09) and
    # instructs gemini-3.6-flash. Still @PINNED. Override via GEN_MODEL.
    gen_model: str = "gemini-3.6-flash@PINNED"

    database_url: str = "sqlite+aiosqlite:///./data/sqlite/app.db"
    chroma_path: str = "./data/chroma"
    backups_path: str = "./data/backups"
    files_path: str = "./data/files"

    cors_origins: str = "*"

    access_ttl_seconds: int = 900  # 15 min
    refresh_ttl_days: int = 30
    lockout_failures: int = 5
    lockout_minutes: int = 15
    google_client_id: str = ""
    smtp_host: str = "smtp.gmail.com"
    smtp_port: int = 587
    smtp_user: str = ""
    smtp_password: str = ""
    smtp_from: str = ""
    resend_api_key: str = ""
    brevo_api_key: str = ""
    gmail_webapp_url: str = ""
    gmail_webapp_secret: str = ""
    admin_email: str = ""

    auth_ip_limit_per_min: int = 10
    refresh_ip_limit_per_min: int = 30
    ingest_limit_per_min: int = 20
    embed_dim: int = 768

    @field_validator("embed_model", "gen_model")
    @classmethod
    def must_be_pinned(cls, v: str) -> str:
        if "@PINNED" not in v:
            raise ValueError(f"unpinned model string is forbidden: {v}")
        return v

    @model_validator(mode="after")
    def jwt_secret_strength(self) -> "Settings":
        if len(self.jwt_secret.encode()) < 32:
            raise ValueError("JWT_SECRET must be ≥32 bytes")
        return self

    @property
    def verify_secrets(self) -> list[str]:
        if not self.jwt_secrets:
            return [self.jwt_secret]
        raw = self.jwt_secrets.strip()
        if raw.startswith("["):
            values = json.loads(raw)
        else:
            values = [s.strip() for s in raw.split(",") if s.strip()]
        # signing key always accepted
        out = []
        for s in [self.jwt_secret, *values]:
            if s and s not in out:
                out.append(s)
        return out

    @property
    def cors_origin_list(self) -> list[str]:
        if self.cors_origins.strip() == "*":
            return ["*"]
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]

    @property
    def smtp_configured(self) -> bool:
        return bool((self.smtp_user or "").strip() and self.smtp_password_clean)

    @property
    def mail_configured(self) -> bool:
        return (
            self.gmail_webapp_configured
            or self.smtp_configured
            or bool((self.resend_api_key or "").strip())
            or bool((self.brevo_api_key or "").strip())
        )

    @property
    def gmail_webapp_configured(self) -> bool:
        return bool((self.gmail_webapp_url or "").strip() and (self.gmail_webapp_secret or "").strip())

    @property
    def smtp_sender(self) -> str:
        return (self.smtp_from or self.smtp_user or "").strip()

    @property
    def mail_from_email(self) -> str:
        raw = self.smtp_sender
        if "<" in raw and ">" in raw:
            return raw.split("<", 1)[1].split(">", 1)[0].strip()
        return raw

    @property
    def mail_from_name(self) -> str:
        raw = (self.smtp_from or "").strip()
        if "<" in raw:
            name = raw.split("<", 1)[0].strip().strip('"')
            return name or "Second Brain"
        return "Second Brain"

    @property
    def resend_from_address(self) -> str:
        raw = (self.smtp_from or "").strip()
        low = raw.lower()
        if raw and "gmail.com" not in low and "googlemail.com" not in low:
            return raw if "<" in raw else f"Second Brain <{raw}>"
        return "Second Brain <onboarding@resend.dev>"

    @property
    def smtp_password_clean(self) -> str:
        return "".join((self.smtp_password or "").split())

    @property
    def admin_email_normalized(self) -> str:
        return (self.admin_email or "").strip().lower()

    def is_admin_email(self, email: str) -> bool:
        admin = self.admin_email_normalized
        return bool(admin) and (email or "").strip().lower() == admin


@lru_cache
def get_settings() -> Settings:
    settings = Settings()  # type: ignore[call-arg]
    for p in (settings.chroma_path, settings.backups_path, settings.files_path):
        Path(p).mkdir(parents=True, exist_ok=True)
    db_url = settings.database_url
    if db_url.startswith("sqlite") and ":///" in db_url:
        db_path = db_url.split(":///", 1)[1]
        if db_path not in {":memory:", ""} and not db_path.startswith(":memory:"):
            Path(db_path).parent.mkdir(parents=True, exist_ok=True)
    return settings
