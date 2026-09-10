from __future__ import annotations

import hashlib
import math
import struct
import time
from typing import Protocol

import httpx
from tenacity import (
    AsyncRetrying,
    retry_if_exception,
    stop_after_attempt,
    wait_exponential_jitter,
    wait_none,
)

from app.core.config import get_settings
from app.core.logging import get_logger

log = get_logger("embedder")


class Embedder(Protocol):
    model: str
    dim: int

    async def embed(self, texts: list[str]) -> list[list[float]]: ...


def l2_normalize(vec: list[float]) -> list[float]:
    s = math.sqrt(sum(x * x for x in vec)) or 1.0
    return [x / s for x in vec]


def unpack_f32(blob: bytes) -> list[float]:
    n = len(blob) // 4
    return list(struct.unpack(f"<{n}f", blob))


def pack_f32(vec: list[float]) -> bytes:
    return struct.pack(f"<{len(vec)}f", *vec)


class FakeEmbedder:
    """Deterministic 768-d (or dim) unit vectors. Tests + dummy-key local dev."""

    def __init__(self, model: str, dim: int = 768) -> None:
        self.model = model
        self.dim = dim

    async def embed(self, texts: list[str]) -> list[list[float]]:
        out = []
        for t in texts:
            digest = hashlib.sha256(f"{self.model}:{t}".encode()).digest()
            raw = [((digest[i % len(digest)] / 255.0) - 0.5) for i in range(self.dim)]
            out.append(l2_normalize(raw))
        return out


class _RetryableHTTP(Exception):
    def __init__(self, status: int, body: str) -> None:
        self.status = status
        super().__init__(f"embed HTTP {status}: {body[:200]}")


def _is_retryable(exc: BaseException) -> bool:
    if isinstance(exc, _RetryableHTTP):
        return exc.status in {429, 500, 502, 503, 504}
    if isinstance(exc, httpx.HTTPStatusError):
        return exc.response.status_code in {429, 500, 502, 503, 504}
    if isinstance(exc, (httpx.TimeoutException, httpx.NetworkError)):
        return True
    return False


class TokenBucket:
    def __init__(self, rpm: int = 90) -> None:
        self.rpm = rpm
        self._hits: list[float] = []

    async def take(self) -> None:
        import asyncio

        while True:
            now = time.monotonic()
            self._hits = [t for t in self._hits if now - t < 60.0]
            if len(self._hits) < self.rpm:
                self._hits.append(now)
                return
            await asyncio.sleep(0.2)


class GeminiEmbedder:
    """Gemini embeddings via REST. Pack pin was text-embedding-004 (retired 2026-01)."""

    def __init__(self, api_key: str, model: str, dim: int = 768, rpm: int = 90) -> None:
        self.api_key = api_key
        self.model = model
        self.dim = dim
        self._bucket = TokenBucket(rpm)
        primary = model.split("@", 1)[0]
        self._models: list[str] = []
        for m in (primary, "gemini-embedding-001"):
            if m not in self._models:
                self._models.append(m)
        self._api_model = self._models[0]

    async def _post(self, model: str, batch: list[str]) -> httpx.Response:
        url = (
            f"https://generativelanguage.googleapis.com/v1beta/models/"
            f"{model}:batchEmbedContents"
        )
        payload = {
            "requests": [
                {
                    "model": f"models/{model}",
                    "content": {"parts": [{"text": t}]},
                    "outputDimensionality": self.dim,
                    "taskType": "RETRIEVAL_DOCUMENT",
                }
                for t in batch
            ]
        }
        from app.core.http import http_client

        return await http_client().post(url, headers={"x-goog-api-key": self.api_key}, json=payload, timeout=30.0)

    async def _call(self, batch: list[str]) -> list[list[float]]:
        await self._bucket.take()
        last_body = ""
        for model in self._models:
            r = await self._post(model, batch)
            if r.status_code in {429, 500, 502, 503, 504}:
                raise _RetryableHTTP(r.status_code, r.text)
            if r.status_code == 404:
                log.warning("embed_model_unavailable", model=model, body=r.text[:240])
                last_body = r.text[:300]
                continue
            if r.status_code >= 400:
                log.warning("embed_http_error", status=r.status_code, model=model, body=r.text[:400])
                r.raise_for_status()
            self._api_model = model
            data = r.json()
            embeddings = data.get("embeddings") or []
            vecs = [e["values"] for e in embeddings]
            if len(vecs) != len(batch):
                raise RuntimeError(f"embed count mismatch {len(vecs)} != {len(batch)}")
            return [l2_normalize(v) for v in vecs]
        raise RuntimeError(f"embed no working model {self._models}: {last_body}")

    async def _batch(self, batch: list[str]) -> list[list[float]]:
        # Production: exp jitter 1–20s, 5 attempts. Tests skip sleep.
        wait = wait_none() if get_settings().app_env == "test" else wait_exponential_jitter(initial=1, max=20)
        async for attempt in AsyncRetrying(
            wait=wait,
            stop=stop_after_attempt(5),
            retry=retry_if_exception(_is_retryable),
            reraise=True,
        ):
            with attempt:
                return await self._call(batch)
        raise RuntimeError("unreachable")

    async def embed(self, texts: list[str]) -> list[list[float]]:
        if not texts:
            return []
        out: list[list[float]] = []
        for i in range(0, len(texts), 100):
            out.extend(await self._batch(texts[i : i + 100]))
        return out


def looks_like_real_gemini_key(key: str) -> bool:
    k = key.strip()
    if not k or k.startswith("test-") or k.startswith("replace-me"):
        return False
    return k.startswith("AIza") or len(k) >= 24


def get_embedder() -> Embedder:
    s = get_settings()
    dim = 768
    if s.app_env == "test" or not looks_like_real_gemini_key(s.gemini_api_key):
        log.warning("embedder_fake", reason="test_or_dummy_key", model=s.embed_model)
        return FakeEmbedder(model=s.embed_model, dim=dim)
    return GeminiEmbedder(api_key=s.gemini_api_key, model=s.embed_model, dim=dim)
