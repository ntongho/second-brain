from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError

from app.core.config import Settings
from app.core.ids import new_id

# 01 §2: time_cost=2, memory=19MB, parallelism=1
_hasher = PasswordHasher(time_cost=2, memory_cost=19456, parallelism=1, hash_len=32, salt_len=16)

# Dummy PHC string so unknown-email login takes the same Argon2 verify path (AUTH-04).
# Generated once at import against a random secret — never compared for equality with user input.
_DUMMY_HASH = _hasher.hash(new_id("dummy"))


def hash_password(password: str) -> str:
    return _hasher.hash(password)


def verify_password(password: str, password_hash: str) -> bool:
    try:
        return _hasher.verify(password_hash, password)
    except VerifyMismatchError:
        return False
    except Exception:
        return False


def dummy_verify(password: str) -> None:
    """Constant-ish work for unknown emails. Result discarded."""
    try:
        _hasher.verify(_DUMMY_HASH, password)
    except Exception:
        return


def encode_access_token(settings: Settings, user_id: str) -> str:
    now = datetime.now(timezone.utc)
    payload = {
        "sub": user_id,
        "jti": new_id("jti"),
        "iat": int(now.timestamp()),
        "exp": int((now + timedelta(seconds=settings.access_ttl_seconds)).timestamp()),
        "typ": "access",
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm="HS256")


def decode_access_token(settings: Settings, token: str) -> dict[str, Any]:
    last_err: Exception | None = None
    for secret in settings.verify_secrets:
        try:
            return jwt.decode(token, secret, algorithms=["HS256"])
        except jwt.PyJWTError as e:
            last_err = e
    raise last_err or jwt.InvalidTokenError("invalid token")
