from __future__ import annotations

from typing import Protocol

import httpx
from tenacity import AsyncRetrying, retry_if_exception, stop_after_attempt, wait_exponential_jitter, wait_none

from app.core.config import get_settings
from app.core.logging import get_logger

log = get_logger("transcribe")

GYM_FIXTURE = (
    "[transcript 2026-08-28, 2min] Gym plan: Mon/Wed/Fri 7am, legs/push/pull. "
    "Goal: 3x/week through September. Note: bring lock, towel. Protein after workout."
)


class Transcriber(Protocol):
    provider: str
    model: str

    async def transcribe(self, blob: bytes, *, filename: str = "memo.wav") -> str: ...


class _Retryable(Exception):
    def __init__(self, status: int) -> None:
        self.status = status
        super().__init__(f"groq HTTP {status}")


def _retryable(exc: BaseException) -> bool:
    return isinstance(exc, _Retryable) and exc.status in {429, 500, 502, 503, 504}


class FakeTranscriber:
    """Tests + dummy GROQ_API_KEY. Deterministic transcript so Q5 can cite."""

    provider = "extractive"
    model = "whisper-large-v3@PINNED"

    async def transcribe(self, blob: bytes, *, filename: str = "memo.wav") -> str:
        if not blob:
            return ""
        return GYM_FIXTURE


class GroqWhisper:
    def __init__(self, api_key: str) -> None:
        self.provider = "groq"
        self.model = "whisper-large-v3"
        self.api_key = api_key

    async def transcribe(self, blob: bytes, *, filename: str = "memo.wav") -> str:
        wait = wait_none() if get_settings().app_env == "test" else wait_exponential_jitter(initial=1, max=20)
        async for attempt in AsyncRetrying(
            wait=wait, stop=stop_after_attempt(5), retry=retry_if_exception(_retryable), reraise=True
        ):
            with attempt:
                return await self._call(blob, filename)
        raise RuntimeError("unreachable")

    async def _call(self, blob: bytes, filename: str) -> str:
        url = "https://api.groq.com/openai/v1/audio/transcriptions"
        lower = filename.lower()
        mime = "application/octet-stream"
        if lower.endswith(".wav"):
            mime = "audio/wav"
        elif lower.endswith(".webm"):
            mime = "audio/webm"
        elif lower.endswith(".mp3"):
            mime = "audio/mpeg"
        elif lower.endswith(".m4a") or lower.endswith(".mp4"):
            mime = "audio/mp4"
        elif lower.endswith(".ogg") or lower.endswith(".opus"):
            mime = "audio/ogg"
        files = {"file": (filename, blob, mime)}
        data = {
            "model": self.model,
            "response_format": "verbose_json",
            "temperature": "0",
        }
        async with httpx.AsyncClient(timeout=120.0) as client:
            r = await client.post(
                url,
                headers={"Authorization": f"Bearer {self.api_key}"},
                files=files,
                data=data,
            )
            if r.status_code == 400:
                log.warning("groq_verbose_rejected", body=r.text[:300])
                data = {"model": self.model, "response_format": "json"}
                r = await client.post(
                    url,
                    headers={"Authorization": f"Bearer {self.api_key}"},
                    files=files,
                    data=data,
                )
        if r.status_code in {429, 500, 502, 503, 504}:
            log.warning("groq_retryable", status=r.status_code)
            raise _Retryable(r.status_code)
        if r.status_code >= 400:
            log.warning("groq_http_error", status=r.status_code, body=r.text[:400])
            raise RuntimeError(f"groq {r.status_code}: {r.text[:300]}")
        payload = r.json()
        text = str(payload.get("text") or "").strip()
        if not text:
            segs = payload.get("segments") or []
            text = " ".join(str(s.get("text") or "").strip() for s in segs if isinstance(s, dict)).strip()
        log.info("groq_transcript", chars=len(text), duration=payload.get("duration"), filename=filename)
        return text


def looks_like_real_groq_key(key: str) -> bool:
    k = key.strip()
    if not k or k.startswith("test-") or k.startswith("replace-me"):
        return False
    return len(k) >= 20


def get_transcriber() -> Transcriber:
    s = get_settings()
    if s.app_env == "test" or not looks_like_real_groq_key(s.groq_api_key):
        log.warning("transcribe_fake", reason="test_or_dummy_key")
        return FakeTranscriber()
    return GroqWhisper(api_key=s.groq_api_key)
