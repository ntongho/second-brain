from __future__ import annotations

import re
from datetime import datetime

from pydantic import EmailStr, Field, field_validator, model_validator

from app.schemas.common import StrictModel

_EMAIL_LIKE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


class RegisterRequest(StrictModel):
    email: EmailStr = Field(max_length=254)
    password: str = Field(min_length=10, max_length=72)
    display_name: str | None = Field(default=None, max_length=80)

    @field_validator("email")
    @classmethod
    def ddl_email_shape(cls, v: EmailStr) -> str:
        s = str(v).strip().lower()
        if not _EMAIL_LIKE.match(s):
            raise ValueError("invalid email")
        return s

    @field_validator("password")
    @classmethod
    def password_printable(cls, v: str) -> str:
        if not v or v.strip() != v:
            # allow internal spaces (correct-horse-10 style) but not leading/trailing
            if len(v) < 10:
                raise ValueError("password too short")
        return v


class LoginRequest(StrictModel):
    email: EmailStr
    password: str = Field(min_length=1, max_length=72)

    @field_validator("email")
    @classmethod
    def norm_email(cls, v: EmailStr) -> str:
        return str(v).strip().lower()


class RefreshRequest(StrictModel):
    refresh_token: str = Field(min_length=20)


class LogoutRequest(StrictModel):
    refresh_token: str | None = Field(default=None, min_length=20)


class UserOut(StrictModel):
    id: str
    email: str
    display_name: str = ""
    created_at: datetime


class TokenPair(StrictModel):
    access_token: str
    refresh_token: str
    token_type: str = "Bearer"
    expires_in: int
    user: UserOut


class ForgotPasswordRequest(StrictModel):
    email: EmailStr

    @field_validator("email")
    @classmethod
    def norm_email(cls, v: EmailStr) -> str:
        return str(v).strip().lower()


class ForgotPasswordResponse(StrictModel):
    ok: bool = True
    emailed: bool = False
    dev_code: str | None = None


class ResetPasswordRequest(StrictModel):
    email: EmailStr
    code: str = Field(min_length=6, max_length=6)
    password: str = Field(min_length=10, max_length=72)

    @field_validator("email")
    @classmethod
    def norm_email(cls, v: EmailStr) -> str:
        return str(v).strip().lower()

    @field_validator("code")
    @classmethod
    def digits_only(cls, v: str) -> str:
        if not v.isdigit():
            raise ValueError("invalid code")
        return v


class GoogleLoginRequest(StrictModel):
    id_token: str | None = Field(default=None, max_length=8192)
    access_token: str | None = Field(default=None, max_length=8192)

    @model_validator(mode="after")
    def one_token(self) -> "GoogleLoginRequest":
        idt = (self.id_token or "").strip() or None
        at = (self.access_token or "").strip() or None
        self.id_token, self.access_token = idt, at
        if not idt and not at:
            raise ValueError("id_token or access_token required")
        if idt and len(idt) < 20:
            raise ValueError("id_token too short")
        if at and len(at) < 20:
            raise ValueError("access_token too short")
        return self
