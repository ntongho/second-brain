from __future__ import annotations

import hashlib
import secrets
import uuid


def new_id(prefix: str) -> str:
    return f"{prefix}_{uuid.uuid4().hex}"


def email_hash(email: str) -> str:
    return hashlib.sha256(email.strip().lower().encode("utf-8")).hexdigest()


def sha256_hex(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def new_refresh_token() -> str:
    # 32 bytes of entropy, url-safe (opaque token; only sha256 stored)
    return secrets.token_urlsafe(32)
