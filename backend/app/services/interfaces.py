from __future__ import annotations

from typing import Any, Protocol

from app.schemas.auth import TokenPair, UserOut


class AuthProvider(Protocol):
    async def register(self, email: str, password: str, display_name: str | None) -> TokenPair: ...
    async def login(self, email: str, password: str, ip: str) -> TokenPair: ...
    async def refresh(self, refresh_token: str) -> TokenPair: ...
    async def logout(self, user_id: str, refresh_token: str | None, *, all_devices: bool) -> None: ...
    async def me(self, user_id: str) -> UserOut: ...


class Embedder(Protocol):
    model: str
    dim: int

    async def embed(self, texts: list[str]) -> list[list[float]]: ...


class VectorStore(Protocol):
    async def upsert(
        self,
        *,
        ids: list[str],
        embeddings: list[list[float]],
        metadatas: list[dict[str, Any]],
        documents: list[str],
    ) -> None: ...

    async def delete(self, *, where: dict[str, Any]) -> None: ...

    async def count(self) -> int: ...


class JobQueue(Protocol):
    def enqueue_ingest(self, job_id: str) -> None: ...
