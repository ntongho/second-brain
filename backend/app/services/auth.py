from __future__ import annotations

import asyncio
import secrets
from datetime import timedelta
from email.message import EmailMessage

from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.clock import utcnow
from app.core.config import Settings, get_settings
from app.core.errors import AppError
from app.core.http import http_client
from app.core.ids import email_hash, new_id, new_refresh_token, sha256_hex
from app.core.logging import get_logger
from app.core.metrics import auth_failures, auth_lockouts, refresh_reuse
from app.core.security import (
    dummy_verify,
    encode_access_token,
    hash_password,
    verify_password,
)
from app.models.password_reset import PasswordReset
from app.models.refresh_token import RefreshToken
from app.models.user import User
from app.schemas.auth import ForgotPasswordResponse, TokenPair, UserOut

log = get_logger("auth")
_reset_locks: dict[str, asyncio.Lock] = {}

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
            is_admin=self.settings.is_admin_email(user.email),
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

    async def request_password_reset(self, email: str) -> ForgotPasswordResponse:
        email = email.strip().lower()
        lock = _reset_locks.setdefault(email, asyncio.Lock())
        async with lock:
            return await self._request_password_reset_locked(email)

    async def _request_password_reset_locked(self, email: str) -> ForgotPasswordResponse:
        user = await self._get_by_email(email)
        if user is None:
            dummy_verify("reset-dummy-xx")
            return ForgotPasswordResponse(ok=True, emailed=False, dev_code=None)

        now = utcnow()
        recent = await self.db.scalar(
            select(PasswordReset)
            .where(PasswordReset.email == email, PasswordReset.used.is_(False))
            .order_by(PasswordReset.created_at.desc())
        )
        if recent is not None and _aware(recent.created_at) is not None:
            age = (now - _aware(recent.created_at)).total_seconds()
            if 0 <= age < 20:
                # Same tap storm / double-click: do not mint a second code.
                return ForgotPasswordResponse(ok=True, emailed=True, dev_code=None)

        code = f"{secrets.randbelow(1_000_000):06d}"
        row = PasswordReset(
            id=new_id("pw"),
            email=email,
            code_sha256=sha256_hex(f"{email}:{code}"),
            expires_at=now + timedelta(minutes=15),
            used=False,
            created_at=now,
        )
        self.db.add(row)
        await self.db.commit()

        emailed = False
        if self.settings.app_env == "test":
            return ForgotPasswordResponse(ok=True, emailed=False, dev_code=code)

        if not self.settings.mail_configured:
            raise AppError(
                503,
                "UPSTREAM_DEGRADED",
                "Password reset email is not configured. Add GMAIL_WEBAPP_URL and GMAIL_WEBAPP_SECRET (see SMTP-SETUP.md).",
                retryable=False,
            )

        try:
            await self._send_reset_email(email, code)
            emailed = True
            await self.db.execute(
                update(PasswordReset)
                .where(
                    PasswordReset.email == email,
                    PasswordReset.used.is_(False),
                    PasswordReset.id != row.id,
                )
                .values(used=True)
            )
            await self.db.commit()
        except Exception as e:
            log.warning("reset_email_failed", email_hash=email_hash(email), err=type(e).__name__, detail=str(e)[:180])
            import smtplib

            detail = str(e).lower()
            if "gmail_webapp" in detail or (
                self.settings.gmail_webapp_configured and "brevo" not in detail and "resend" not in detail
            ):
                msg = (
                    "Google mail relay failed. Redeploy the Apps Script as a Web app "
                    "(Execute as: Me, Who has access: Anyone), match GMAIL_WEBAPP_SECRET, restart the API."
                )
            elif "brevo" in detail or (
                (self.settings.brevo_api_key or "").strip() and "resend" not in detail
            ):
                if "401" in detail or "unauthorized" in detail:
                    msg = "Brevo rejected the API key. Check BREVO_API_KEY in .env and restart the API."
                elif "sender" in detail or "400" in detail:
                    msg = (
                        "Brevo sender is not verified. In Brevo → Senders, add SMTP_FROM "
                        "(your Gmail) and confirm the code they email you."
                    )
                else:
                    msg = "Brevo could not send the email. Check the API log line reset_email_failed."
            elif "resend" in detail or (self.settings.resend_api_key or "").strip():
                if "401" in detail:
                    msg = "Resend rejected the API key. Check RESEND_API_KEY in .env and restart the API."
                elif "403" in detail or "testing emails" in detail:
                    msg = (
                        "Resend test mode can only email the address you signed up with. "
                        "Use Brevo (BREVO_API_KEY) to send to any inbox without buying a domain."
                    )
                else:
                    msg = "Resend could not send the email. Check the API log line reset_email_failed."
            elif isinstance(e, smtplib.SMTPAuthenticationError):
                msg = (
                    "Gmail rejected the mailbox login. SMTP_USER must be the full Gmail address, "
                    "SMTP_PASSWORD must be a 16-character App password (not your normal Gmail password). Restart the API after changing .env."
                )
            elif isinstance(e, (TimeoutError, OSError, smtplib.SMTPConnectError, smtplib.SMTPServerDisconnected)):
                msg = (
                    "This network cannot reach Gmail SMTP (port 587 blocked). "
                    "Use GMAIL_WEBAPP_URL (Google Apps Script, HTTPS) — see SMTP-SETUP.md."
                )
            else:
                msg = "Could not send the reset email. Check mail settings in .env and restart the API."
            raise AppError(503, "UPSTREAM_DEGRADED", msg, retryable=True) from e
        return ForgotPasswordResponse(ok=True, emailed=emailed, dev_code=None)

    async def reset_password(self, email: str, code: str, password: str) -> TokenPair:
        email = email.strip().lower()
        digest = sha256_hex(f"{email}:{code}")
        row = await self.db.scalar(
            select(PasswordReset)
            .where(PasswordReset.email == email, PasswordReset.code_sha256 == digest)
            .order_by(PasswordReset.created_at.desc())
        )
        if row is None or row.used or _aware(row.expires_at) <= utcnow():
            dummy_verify(password)
            raise AppError(401, "AUTH", "Invalid or expired code")

        user = await self._get_by_email(email)
        if user is None:
            raise AppError(401, "AUTH", "Invalid or expired code")

        row.used = True
        user.password_hash = hash_password(password)
        user.failed_attempts = 0
        user.locked_until = None
        user.updated_at = utcnow()
        await self._revoke_user_chain(user.id, "password_reset")
        await self.db.commit()
        log.info("password_reset_ok", user_id=user.id, email_hash=user.email_hash)
        return await self._issue_pair(user)

    async def login_google(self, id_token: str | None = None, access_token: str | None = None) -> TokenPair:
        if id_token:
            info = await self._google_userinfo(id_token)
        elif access_token:
            info = await self._google_userinfo_access(access_token)
        else:
            raise AppError(400, "VALIDATION", "Google sign-in failed")
        email = str(info.get("email") or "").strip().lower()
        if not email or "@" not in email:
            raise AppError(401, "AUTH", "Google sign-in failed")
        name = str(info.get("name") or "").strip()[:80]
        user = await self._get_by_email(email)
        if user is None:
            now = utcnow()
            user = User(
                id=new_id("u"),
                email=email,
                email_hash=email_hash(email),
                password_hash=hash_password(secrets.token_urlsafe(32)),
                display_name=name,
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
                user = await self._get_by_email(email)
                if user is None:
                    raise AppError(401, "AUTH", "Google sign-in failed")
        else:
            if self._locked(user):
                await self._raise_locked(user)
            user.failed_attempts = 0
            user.locked_until = None
            if name and not (user.display_name or "").strip():
                user.display_name = name
            user.updated_at = utcnow()
            await self.db.flush()
        log.info("google_login_ok", user_id=user.id, email_hash=user.email_hash)
        return await self._issue_pair(user)

    async def _google_userinfo(self, id_token: str) -> dict:
        audience = (self.settings.google_client_id or "").strip()
        if not audience:
            raise AppError(400, "VALIDATION", "Google sign-in is not configured")
        try:
            res = await http_client().get(
                "https://oauth2.googleapis.com/tokeninfo",
                params={"id_token": id_token},
                timeout=10.0,
            )
        except Exception as e:
            log.warning("google_tokeninfo_network", err=str(e))
            raise AppError(401, "AUTH", "Google sign-in failed") from e
        if res.status_code != 200:
            log.warning("google_tokeninfo_http", status=res.status_code)
            raise AppError(401, "AUTH", "Google sign-in failed")
        data = res.json()
        allowed = {a.strip() for a in audience.split(",") if a.strip()}
        aud = data.get("aud")
        if aud not in allowed:
            log.warning("google_aud_mismatch")
            raise AppError(401, "AUTH", "Google sign-in failed")
        verified = data.get("email_verified")
        if verified not in (True, "true", "1", 1, None, ""):
            raise AppError(401, "AUTH", "Google sign-in failed")
        if verified in (None, "") and not data.get("email"):
            raise AppError(401, "AUTH", "Google sign-in failed")
        return data

    async def _google_userinfo_access(self, access_token: str) -> dict:
        if not (self.settings.google_client_id or "").strip():
            raise AppError(400, "VALIDATION", "Google sign-in is not configured")
        try:
            res = await http_client().get(
                "https://www.googleapis.com/oauth2/v3/userinfo",
                headers={"Authorization": f"Bearer {access_token}"},
                timeout=10.0,
            )
        except Exception as e:
            log.warning("google_userinfo_network", err=str(e))
            raise AppError(401, "AUTH", "Google sign-in failed") from e
        if res.status_code != 200:
            log.warning("google_userinfo_http", status=res.status_code)
            raise AppError(401, "AUTH", "Google sign-in failed")
        data = res.json()
        verified = data.get("email_verified")
        if verified not in (True, "true", "1", 1, None, ""):
            raise AppError(401, "AUTH", "Google sign-in failed")
        return data

    async def _send_reset_email(self, to: str, code: str) -> None:
        import smtplib
        import socket
        import ssl

        s = self.settings
        subject = "Your Second Brain reset code"
        text = (
            f"Your Second Brain password reset code is:\n\n{code}\n\n"
            "It expires in 15 minutes. If you didn't ask for this, ignore this email.\n"
        )
        html = (
            f"<p>Your Second Brain password reset code is:</p>"
            f"<p style='font-size:24px;letter-spacing:4px'><b>{code}</b></p>"
            f"<p>It expires in 15 minutes. If you didn't ask for this, ignore this email.</p>"
        )

        if s.gmail_webapp_configured:
            payload = {
                "secret": s.gmail_webapp_secret.strip(),
                "to": to,
                "subject": subject,
                "text": text,
                "html": html,
            }
            last = "gmail_webapp no attempt"
            for attempt in range(3):
                try:
                    res = await http_client().post(
                        s.gmail_webapp_url.strip(),
                        json=payload,
                        timeout=45.0,
                        follow_redirects=True,
                    )
                except Exception as e:
                    last = f"gmail_webapp network: {type(e).__name__}: {e}"
                    await asyncio.sleep(1.5 * (attempt + 1))
                    continue
                body = (res.text or "")[:300]
                if res.status_code >= 300:
                    last = f"gmail_webapp http {res.status_code}: {body}"
                    await asyncio.sleep(1.5 * (attempt + 1))
                    continue
                data = None
                try:
                    data = res.json()
                except Exception:
                    data = None
                if isinstance(data, dict) and data.get("ok") is True:
                    return
                last = f"gmail_webapp bad body: {body}"
                await asyncio.sleep(1.5 * (attempt + 1))
            raise RuntimeError(last)

        brevo = (s.brevo_api_key or "").strip()
        if brevo:
            from_email = s.mail_from_email
            if not from_email or "@" not in from_email:
                raise RuntimeError("brevo needs SMTP_FROM set to your verified sender Gmail")
            res = await http_client().post(
                "https://api.brevo.com/v3/smtp/email",
                headers={
                    "api-key": brevo,
                    "accept": "application/json",
                    "content-type": "application/json",
                },
                json={
                    "sender": {"name": s.mail_from_name, "email": from_email},
                    "to": [{"email": to}],
                    "subject": subject,
                    "htmlContent": html,
                    "textContent": text,
                },
                timeout=20.0,
            )
            if res.status_code >= 300:
                raise RuntimeError(f"brevo http {res.status_code}: {res.text[:220]}")
            return

        key = (s.resend_api_key or "").strip()
        if key:
            res = await http_client().post(
                "https://api.resend.com/emails",
                headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
                json={
                    "from": s.resend_from_address,
                    "to": [to],
                    "subject": subject,
                    "text": text,
                    "html": html,
                },
                timeout=20.0,
            )
            if res.status_code >= 300:
                raise RuntimeError(f"resend http {res.status_code}: {res.text[:220]}")
            return

        sender = s.smtp_sender
        if not sender:
            raise RuntimeError("no smtp sender")
        msg = EmailMessage()
        msg["Subject"] = subject
        msg["From"] = sender
        msg["To"] = to
        msg.set_content(text)
        msg.add_alternative(html, subtype="html")

        def _ipv4_socket(host: str, port: int, timeout: float):
            last: OSError | None = None
            for info in socket.getaddrinfo(host, port, socket.AF_INET, socket.SOCK_STREAM):
                af, socktype, proto, _, sa = info
                sock = socket.socket(af, socktype, proto)
                sock.settimeout(timeout)
                try:
                    sock.connect(sa)
                    return sock
                except OSError as e:
                    last = e
                    sock.close()
            raise last or OSError("ipv4 connect failed")

        class _SMTP4(smtplib.SMTP):
            def _get_socket(self, host, port, timeout):  # type: ignore[no-untyped-def]
                return _ipv4_socket(host, port, timeout)

        class _SMTP_SSL4(smtplib.SMTP_SSL):
            def _get_socket(self, host, port, timeout):  # type: ignore[no-untyped-def]
                raw = _ipv4_socket(host, port, timeout)
                return self.context.wrap_socket(raw, server_hostname=host)

        def _send() -> None:
            host = (s.smtp_host or "smtp.gmail.com").strip()
            user = (s.smtp_user or "").strip()
            pw = s.smtp_password_clean
            ctx = ssl.create_default_context()
            ports = [s.smtp_port]
            for extra in (465, 587):
                if extra not in ports:
                    ports.append(extra)
            last: Exception | None = None
            for port in ports:
                try:
                    if port == 465:
                        with _SMTP_SSL4(host, port, timeout=20, context=ctx) as smtp:
                            smtp.login(user, pw)
                            smtp.send_message(msg)
                        return
                    with _SMTP4(host, port, timeout=20) as smtp:
                        smtp.ehlo()
                        smtp.starttls(context=ctx)
                        smtp.ehlo()
                        smtp.login(user, pw)
                        smtp.send_message(msg)
                    return
                except Exception as e:
                    last = e
            if last:
                raise last
            raise OSError("smtp send failed")

        await asyncio.to_thread(_send)
