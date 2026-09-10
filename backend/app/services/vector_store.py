from __future__ import annotations

from typing import Any, Protocol

from app.core.config import get_settings
from app.core.logging import get_logger

log = get_logger("vector_store")

COLLECTION = "sb_chunks_prod"


def chroma_where(where: dict[str, Any] | None) -> dict[str, Any] | None:
    """Chroma allows only one top-level operator. Flatten {a:1,b:2} → $and."""
    if not where:
        return None
    if any(str(k).startswith("$") for k in where):
        return where
    parts = [{k: v} for k, v in where.items()]
    if len(parts) == 1:
        return parts[0]
    return {"$and": parts}


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

    async def query(
        self,
        *,
        embedding: list[float],
        n_results: int,
        where: dict[str, Any],
    ) -> list[dict[str, Any]]: ...


class InMemoryVectorStore:
    """Used only if chromadb is unavailable. Tests prefer Chroma when installed."""

    def __init__(self) -> None:
        self._rows: dict[str, dict[str, Any]] = {}

    async def upsert(self, *, ids, embeddings, metadatas, documents) -> None:
        for i, _id in enumerate(ids):
            self._rows[_id] = {
                "embedding": embeddings[i],
                "metadata": metadatas[i],
                "document": documents[i],
            }

    async def delete(self, *, where: dict[str, Any]) -> None:
        drop = [
            k
            for k, v in self._rows.items()
            if all(v["metadata"].get(kk) == vv for kk, vv in where.items())
        ]
        for k in drop:
            del self._rows[k]

    async def count(self) -> int:
        return len(self._rows)

    async def query(self, *, embedding, n_results, where):
        import math

        def cos(a, b):
            dot = sum(x * y for x, y in zip(a, b, strict=False))
            na = math.sqrt(sum(x * x for x in a)) or 1.0
            nb = math.sqrt(sum(y * y for y in b)) or 1.0
            return dot / (na * nb)

        scored = []
        for _id, row in self._rows.items():
            md = row["metadata"]
            ok = True
            for k, v in (where or {}).items():
                if md.get(k) != v:
                    ok = False
                    break
            if not ok:
                continue
            scored.append((cos(embedding, row["embedding"]), _id, row))
        scored.sort(reverse=True)
        out = []
        for score, _id, row in scored[:n_results]:
            out.append(
                {
                    "id": _id,
                    "document": row["document"],
                    "metadata": row["metadata"],
                    "distance": 1.0 - score,
                }
            )
        return out


class ChromaVectorStore:
    def __init__(self, path: str) -> None:
        import chromadb
        from chromadb.config import Settings as ChromaSettings

        self._client = chromadb.PersistentClient(
            path=path,
            settings=ChromaSettings(anonymized_telemetry=False),
        )
        self._col = self._client.get_or_create_collection(
            name=COLLECTION,
            metadata={
                "hnsw:space": "cosine",
                "hnsw:M": 16,
                "hnsw:construction_ef": 200,
            },
        )

    async def upsert(self, *, ids, embeddings, metadatas, documents) -> None:
        import asyncio

        def _add() -> None:
            self._col.upsert(ids=ids, embeddings=embeddings, metadatas=metadatas, documents=documents)

        await asyncio.to_thread(_add)

    async def delete(self, *, where: dict[str, Any]) -> None:
        import asyncio

        def _del() -> None:
            if not where:
                return
            self._col.delete(where=chroma_where(where) or where)

        await asyncio.to_thread(_del)

    async def count(self) -> int:
        import asyncio

        return int(await asyncio.to_thread(self._col.count))

    async def query(self, *, embedding, n_results, where):
        import asyncio

        def _q():
            if n_results <= 0:
                return []
            total = self._col.count()
            if total == 0:
                return []
            n_results_local = min(n_results, total)
            res = self._col.query(
                query_embeddings=[embedding],
                n_results=n_results_local,
                where=chroma_where(where),
                include=["documents", "metadatas", "distances"],
            )
            ids = (res.get("ids") or [[]])[0]
            docs = (res.get("documents") or [[]])[0]
            metas = (res.get("metadatas") or [[]])[0]
            dists = (res.get("distances") or [[]])[0]
            out = []
            for i, _id in enumerate(ids):
                out.append(
                    {
                        "id": _id,
                        "document": docs[i] if i < len(docs) else "",
                        "metadata": metas[i] if i < len(metas) else {},
                        "distance": dists[i] if i < len(dists) else 0.0,
                    }
                )
            return out

        return await asyncio.to_thread(_q)


_store: VectorStore | None = None


def get_vector_store() -> VectorStore:
    global _store
    if _store is None:
        path = get_settings().chroma_path
        try:
            _store = ChromaVectorStore(path)
            log.info("vector_store_chroma", path=path)
        except Exception as e:  # noqa: BLE001
            log.warning("vector_store_memory_fallback", error=str(e))
            _store = InMemoryVectorStore()
    return _store


def reset_vector_store() -> None:
    global _store
    _store = None
