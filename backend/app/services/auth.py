from __future__ import annotations

from datetime import timedelta

from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.clock import utcnow
from app.core.config import Settings, get_settings
from app.core.errors import AppError
from app.core.ids import email_hash, new_id, new_refresh_token, sha256_hex
from app.core.logging import get_logger
from app.core.metrics import auth_failures, auth_lockouts, refresh_reuse
from app.core.security import (
    dummy_verify,
    encode_access_token,
    hash_password,
    verify_password,
)
from app.models.refresh_token import RefreshToken
from app.models.user import User
from app.schemas.auth import TokenPair, UserOut

log = get_logger("auth")

LOGIN_FAIL_MESSAGE = "Incorrect email or password"
LOCKOUT_MESSAGE = "Account locked. Try again later."


def _aware(dt):
    if dt is None:
        return None
    if dt.tzinfo is None:
        from datetime import timezone

        return dt.replace(tzinfo=timezone.utc)
    return dt


class AuthService:
    def __init__(self, db: AsyncSession, settings: Settings | None = None) -> None:
        self.db = db
        self.settings = settings or get_settings()

    def _user_out(self, user: User) -> UserOut:
        return UserOut(
            id=user.id,
            email=user.email,
            display_name=user.display_name or "",
            created_at=_aware(user.created_at),
        )

    async def _issue_pair(self, user: User) -> TokenPair:
        now = utcnow()
        raw = new_refresh_token()
        row = RefreshToken(
            id=new_id("rt"),
            user_id=user.id,
            token_sha256=sha256_hex(raw),
            expires_at=now + timedelta(days=self.settings.refresh_ttl_days),
            revoked=False,
            created_at=now,
        )
        self.db.add(row)
        await self.db.commit()
        access = encode_access_token(self.settings, user.id)
        return TokenPair(
            access_token=access,
            refresh_token=raw,
            token_type="Bearer",
            expires_in=self.settings.access_ttl_seconds,
            user=self._user_out(user),
        )

    async def register(self, email: str, password: str, display_name: str | None) -> TokenPair:
        email = email.strip().lower()
        existing = await self.db.scalar(select(User).where(User.email == email))
        if existing:
            raise AppError(409, "CONFLICT", "Email already registered", details={"email": email})
        now = utcnow()
        user = User(
            id=new_id("u"),
            email=email,
            email_hash=email_hash(email),
            password_hash=hash_password(password),
            display_name=(display_name or "").strip(),
            failed_attempts=0,
            locked_until=None,
            created_at=now,
            updated_at=now,
        )
        self.db.add(user)
        try:
            await self.db.flush()
        except IntegrityError:
            await self.db.rollback()
            raise AppError(409, "CONFLICT", "Email already registered")
        log.info("user_registered", user_id=user.id, email_hash=user.email_hash)
        return await self._issue_pair(user)

    async def _get_by_email(self, email: str) -> User | None:
        return await self.db.scalar(select(User).where(User.email == email))

    def _locked(self, user: User) -> bool:
        until = _aware(user.locked_until)
        if until is None:
            return False
        return until > utcnow()

    async def _raise_locked(self, user: User) -> None:
        until = _aware(user.locked_until)
        iso = until.isoformat() if until else None
        retry_after = None
        if until:
            retry_after = max(1, int((until - utcnow()).total_seconds()))
        raise AppError(
            429,
            "ACCOUNT_LOCKED",
            LOCKOUT_MESSAGE,
            details={"locked_until": iso},
            retryable=True,
            retry_after=retry_after,
        )

    async def login(self, email: str, password: str) -> TokenPair:
        email = email.strip().lower()
        user = await self._get_by_email(email)
        if user is None:
            dummy_verify(password)
            auth_failures.labels(reason="unknown_or_bad").inc()
            log.info("login_failed", email_hash=email_hash(email), reason="unknown")
            raise AppError(401, "AUTH", LOGIN_FAIL_MESSAGE)

        # Expired lockout window → reset counter (fresh 5 tries).
        until = _aware(user.locked_until)
        if until is not None and until <= utcnow():
            user.failed_attempts = 0
            user.locked_until = None
            user.updated_at = utcnow()
            await self.db.flush()

        if self._locked(user):
            auth_failures.labels(reason="locked").inc()
            await self._raise_locked(user)

        if not verify_password(password, user.password_hash):
            user.failed_attempts = int(user.failed_attempts or 0) + 1
            user.updated_at = utcnow()
            if user.failed_attempts >= self.settings.lockout_failures:
                user.locked_until = utcnow() + timedelta(minutes=self.settings.lockout_minutes)
                auth_lockouts.inc()
                log.warning("account_locked", user_id=user.id, email_hash=user.email_hash)
            await self.db.commit()
            auth_failures.labels(reason="unknown_or_bad").inc()
            log.info("login_failed", email_hash=user.email_hash, reason="bad_password")
            raise AppError(401, "AUTH", LOGIN_FAIL_MESSAGE)

        user.failed_attempts = 0
        user.locked_until = None
        user.updated_at = utcnow()
        await self.db.flush()
        log.info("login_ok", user_id=user.id, email_hash=user.email_hash)
        return await self._issue_pair(user)

    async def _revoke_user_chain(self, user_id: str, reason: str) -> None:
        now = utcnow()
        await self.db.execute(
            update(RefreshToken)
            .where(RefreshToken.user_id == user_id, RefreshToken.revoked.is_(False))
            .values(revoked=True, revoked_reason=reason, last_used_at=now)
        )

    async def refresh(self, refresh_token: str) -> TokenPair:
        digest = sha256_hex(refresh_token)
        row = await self.db.scalar(select(RefreshToken).where(RefreshToken.token_sha256 == digest))
        if row is None:
            auth_failures.labels(reason="refresh_unknown").inc()
            raise AppError(401, "AUTH", "Invalid refresh token")

        # Reuse of a *rotated* token (already replaced) → theft detection.
        if row.replaced_by is not None:
            refresh_reuse.inc()
            await self._revoke_user_chain(row.user_id, "reuse")
            await self.db.commit()
            log.warning("refresh_reuse_revoked_chain", user_id=row.user_id)
            raise AppError(401, "AUTH", "Invalid refresh token", details={"reused": True})

        if row.revoked:
            raise AppError(401, "AUTH", "Invalid refresh token")

        if _aware(row.expires_at) <= utcnow():
            row.revoked = True
            row.revoked_reason = "expired"
            await self.db.commit()
            raise AppError(401, "AUTH", "Invalid refresh token")

        user = await self.db.scalar(select(User).where(User.id == row.user_id))
        if user is None:
            raise AppError(401, "AUTH", "Invalid refresh token")

        now = utcnow()
        new_raw = new_refresh_token()
        new_row = RefreshToken(
            id=new_id("rt"),
            user_id=user.id,
            token_sha256=sha256_hex(new_raw),
            expires_at=now + timedelta(days=self.settings.refresh_ttl_days),
            revoked=False,
            created_at=now,
        )
        self.db.add(new_row)
        await self.db.flush()
        row.revoked = True
        row.revoked_reason = "rotated"
        row.replaced_by = new_row.id
        row.last_used_at = now
        await self.db.commit()

        access = encode_access_token(self.settings, user.id)
        return TokenPair(
            access_token=access,
            refresh_token=new_raw,
            token_type="Bearer",
            expires_in=self.settings.access_ttl_seconds,
            user=self._user_out(user),
        )

    async def logout(self, user_id: str, refresh_token: str | None, *, all_devices: bool) -> None:
        if all_devices:
            await self._revoke_user_chain(user_id, "logout_all")
            await self.db.commit()
            return
        if not refresh_token:
            await self.db.commit()
            return
        digest = sha256_hex(refresh_token)
        row = await self.db.scalar(
            select(RefreshToken).where(RefreshToken.token_sha256 == digest, RefreshToken.user_id == user_id)
        )
        if row and not row.revoked:
            row.revoked = True
            row.revoked_reason = "logout"
            row.last_used_at = utcnow()
        await self.db.commit()

    async def me(self, user_id: str) -> UserOut:
        user = await self.db.scalar(select(User).where(User.id == user_id))
        if user is None:
            raise AppError(401, "AUTH", "Invalid access token")
        return self._user_out(user)
