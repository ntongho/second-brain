from __future__ import annotations

import json
import re
import time
from dataclasses import dataclass, field

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.clock import utcnow
from app.core.ids import new_id
from app.core.logging import get_logger
from app.models.chat import Chat
from app.models.document import Document
from app.models.message import Message
from app.services.breaker import get_breaker
from app.services.embed_cache import embed_with_cache
from app.services.embedder import get_embedder
from app.services.fts import as_utc, bm25_search, parse_dt, tags_of
from app.services.llm import SYSTEM, LLMResult, get_llm, scan_leak
from app.services.vector_store import get_vector_store

log = get_logger("rag")
RRF_K = 60
REFUSAL_PREFIX = "Not in your library"


@dataclass
class Retrieved:
    chunk_id: str
    document_id: str
    title: str
    text: str
    page: int | None
    start_char: int | None
    end_char: int | None
    score: float
    source: str  # dense | sparse | rrf
    source_type: str = ""


@dataclass
class AskResult:
    answer: str
    citations: list[dict]
    degraded: bool
    mode: str
    chat_id: str
    message_id: str
    prompt_tokens: int
    completion_tokens: int
    latency_ms: int
    request_id: str
    chunks: list[Retrieved] = field(default_factory=list)


def rrf_fuse(dense: list[Retrieved], sparse: list[Retrieved], top_k: int) -> list[Retrieved]:
    scores: dict[str, float] = {}
    items: dict[str, Retrieved] = {}
    for rank, r in enumerate(dense):
        scores[r.chunk_id] = scores.get(r.chunk_id, 0.0) + 1.0 / (RRF_K + rank + 1)
        items[r.chunk_id] = r
    for rank, r in enumerate(sparse):
        scores[r.chunk_id] = scores.get(r.chunk_id, 0.0) + 1.0 / (RRF_K + rank + 1)
        if r.chunk_id not in items:
            items[r.chunk_id] = r
        else:
            # mark fused
            items[r.chunk_id].source = "rrf"
    ranked = sorted(scores.items(), key=lambda kv: kv[1], reverse=True)
    out = []
    for cid, sc in ranked[:top_k]:
        item = items[cid]
        item.score = sc
        if item.source != "rrf":
            # keep original source if only one list hit
            pass
        out.append(item)
    return out


async def hybrid_retrieve(
    db: AsyncSession,
    *,
    user_id: str,
    query: str,
    top_k: int = 6,
    filters: dict | None = None,
) -> list[Retrieved]:
    filters = filters or {}
    source_types = filters.get("source_types")
    document_ids = filters.get("document_ids")
    tags = filters.get("tags")
    from_dt = parse_dt(filters.get("from") or filters.get("from_"))
    to_dt = parse_dt(filters.get("to"))
    sparse_rows = await bm25_search(
        db,
        user_id=user_id,
        query=query,
        limit=12,
        source_types=source_types,
        document_ids=document_ids,
        tags=tags,
        from_dt=from_dt,
        to_dt=to_dt,
    )
    sparse = [
        Retrieved(
            chunk_id=r["chunk_id"],
            document_id=r["document_id"],
            title=r["title"],
            text=r["text"],
            page=r["page"],
            start_char=r["start_char"],
            end_char=r["end_char"],
            score=1.0 / (RRF_K + r["rank"] + 1),
            source="sparse",
            source_type=str(r.get("source_type") or ""),
        )
        for r in sparse_rows
    ]
    dense: list[Retrieved] = []
    try:
        embedder = get_embedder()
        qvec = (await embed_with_cache(db, embedder, [query]))[0]
        where: dict = {"user_id": user_id}
        if source_types and len(source_types) == 1:
            where["source_type"] = source_types[0]
        store = get_vector_store()
        hits = await store.query(embedding=qvec, n_results=12, where=where)
        for rank, h in enumerate(hits):
            md = h.get("metadata") or {}
            if document_ids and md.get("document_id") not in document_ids:
                continue
            if source_types and md.get("source_type") not in source_types:
                continue
            ts = md.get("created_at_ts")
            if from_dt is not None and isinstance(ts, (int, float)) and ts < from_dt.timestamp():
                continue
            if to_dt is not None and isinstance(ts, (int, float)) and ts > to_dt.timestamp():
                continue
            if tags:
                csv = str(md.get("tags_csv") or "").lower()
                if not all(str(t).lower() in csv for t in tags):
                    continue
            dense.append(
                Retrieved(
                    chunk_id=h["id"],
                    document_id=str(md.get("document_id") or ""),
                    title="",  # filled below
                    text=h.get("document") or "",
                    page=md.get("page") if md.get("page", -1) != -1 else None,
                    start_char=md.get("start_char"),
                    end_char=md.get("end_char"),
                    score=1.0 / (RRF_K + rank + 1),
                    source="dense",
                )
            )
    except Exception as e:  # noqa: BLE001
        log.warning("dense_retrieve_failed", error=str(e))

    fused = rrf_fuse(dense, sparse, top_k)
    ids = [r.document_id for r in fused if r.document_id]
    if ids:
        docs = (await db.scalars(select(Document).where(Document.id.in_(ids), Document.user_id == user_id))).all()
        by_id = {d.id: d for d in docs}
        kept: list[Retrieved] = []
        for r in fused:
            d = by_id.get(r.document_id)
            if d is None:
                continue
            r.title = d.title
            r.source_type = d.source_type
            if source_types and d.source_type not in source_types:
                continue
            created = as_utc(d.created_at)
            if from_dt is not None and created is not None and created < from_dt:
                continue
            if to_dt is not None and created is not None and created > to_dt:
                continue
            if tags:
                have = {t.lower() for t in tags_of(d.tags)}
                if not all(str(t).lower() in have for t in tags):
                    continue
            kept.append(r)
        fused = kept
    log.info("retrieve", user_id=user_id, dense=len(dense), sparse=len(sparse), fused=len(fused))
    return fused


_CITE_RE = re.compile(r"\[(\d+)\]")
MAX_CITATIONS = 4


def _overlaps(a: Retrieved, b: Retrieved) -> bool:
    if a.document_id != b.document_id:
        return False
    if a.page is not None and b.page is not None and a.page == b.page:
        return True
    if a.start_char is None or b.start_char is None:
        return bool(a.text and b.text and a.text[:80] == b.text[:80])
    a1, a2 = a.start_char, a.end_char if a.end_char is not None else a.start_char + len(a.text or "")
    b1, b2 = b.start_char, b.end_char if b.end_char is not None else b.start_char + len(b.text or "")
    overlap = min(a2, b2) - max(a1, b1)
    if overlap <= 0:
        return abs(a1 - b1) < 400
    span = max(1, min(a2 - a1, b2 - b1))
    return overlap / span >= 0.35


def compact_chunks(chunks: list[Retrieved], *, limit: int = MAX_CITATIONS) -> list[Retrieved]:
    """Keep the strongest unique passages (one per page / overlapping span)."""
    ranked = sorted(chunks, key=lambda c: -c.score)
    out: list[Retrieved] = []
    for c in ranked:
        if any(_overlaps(c, kept) for kept in out):
            continue
        out.append(c)
        if len(out) >= limit:
            break
    order = {c.chunk_id: i for i, c in enumerate(chunks)}
    out.sort(key=lambda c: order.get(c.chunk_id, 99))
    return out


def citations_for_answer(answer: str, chunks: list[Retrieved], *, retrieval: str) -> list[dict]:
    used = {int(n) for n in _CITE_RE.findall(answer or "")}
    picked: list[Retrieved] = []
    if used:
        for i, c in enumerate(chunks, start=1):
            if i in used:
                picked.append(c)
    if not picked:
        picked = list(chunks)
    return _citations(compact_chunks(picked), retrieval)


def _citations(chunks: list[Retrieved], retrieval: str) -> list[dict]:
    out = []
    for r in chunks:
        snippet = r.text[:400]
        out.append(
            {
                "chunk_id": r.chunk_id,
                "document_id": r.document_id,
                "title": r.title,
                "page": r.page,
                "start_char": r.start_char,
                "end_char": r.end_char,
                "score": round(r.score, 4),
                "retrieval": retrieval if retrieval != "rrf" else r.source,
                "snippet": snippet,
            }
        )
    return out


def _context_block(chunks: list[Retrieved]) -> str:
    if not chunks:
        return "<retrieved_context>(none)</retrieved_context>"
    parts = []
    for i, c in enumerate(chunks, start=1):
        page = f"p.{c.page}" if c.page else "p.?"
        parts.append(f"[{i}]={c.title} {page}\n{c.text}")
    return "<retrieved_context>\n" + "\n\n".join(parts) + "\n</retrieved_context>"


def _degraded_answer(chunks: list[Retrieved], provider: str) -> str:
    if not chunks:
        return (
            f"AI generation is unavailable (provider: {provider}). "
            "No keyword matches in your library. Full AI answer can be retried later."
        )
    lines = []
    docs = []
    for i, c in enumerate(chunks, start=1):
        lines.append(f"{i}. {c.snippet if hasattr(c, 'snippet') else c.text[:240]}")
        docs.append(c.title)
    return (
        f"AI generation is unavailable (provider: {provider}). "
        "These are direct keyword matches from your library:\n"
        + "\n".join(lines)
        + f"\n({len(set(docs))} docs). Full AI answer can be retried later."
    )


async def _ensure_chat(db: AsyncSession, user_id: str, chat_id: str | None, title_hint: str) -> Chat:
    if chat_id:
        chat = await db.scalar(select(Chat).where(Chat.id == chat_id, Chat.user_id == user_id))
        if chat:
            return chat
    chat = Chat(id=new_id("chat"), user_id=user_id, title=title_hint[:80] or "New chat", created_at=utcnow())
    db.add(chat)
    await db.flush()
    return chat


async def _last6(db: AsyncSession, chat_id: str) -> list[Message]:
    rows = (
        await db.scalars(
            select(Message).where(Message.chat_id == chat_id).order_by(Message.created_at.desc()).limit(6)
        )
    ).all()
    return list(reversed(rows))


async def ask(
    db: AsyncSession,
    *,
    user_id: str,
    query: str,
    chat_id: str | None,
    top_k: int,
    filters: dict | None,
    request_id: str,
    force_degraded: bool = False,
) -> AskResult:
    t0 = time.perf_counter()
    top_k = max(1, min(top_k or 6, 12))
    chat = await _ensure_chat(db, user_id, chat_id, query)
    history = await _last6(db, chat.id)
    chunks = compact_chunks(
        await hybrid_retrieve(db, user_id=user_id, query=query, top_k=top_k, filters=filters)
    )

    breaker = get_breaker("gemini")
    if force_degraded:
        breaker.force_open(True)
    use_llm = breaker.allow()
    llm = get_llm()

    degraded = False
    mode = "full"
    prompt_tokens = 0
    completion_tokens = 0
    citations: list[dict] = []
    answer = ""

    if not use_llm:
        degraded = True
        mode = "keyword_only"
        breaker.mark_degraded()
        answer = _degraded_answer(chunks, llm.provider)
        citations = citations_for_answer(answer, chunks, retrieval="sparse")
        for c in citations:
            c["retrieval"] = "sparse"
        completion_tokens = 0
    else:
        hist = "\n".join(f"{m.role}: {m.content[:400]}" for m in history)
        user_payload = (
            f"QUESTION: {query}\n\nHISTORY (last 6):\n{hist or '(none)'}\n\n{_context_block(chunks)}"
        )
        try:
            result: LLMResult = await llm.generate(system=SYSTEM, user=user_payload)
            breaker.success()
            answer = scan_leak(result.text or "")
            prompt_tokens = result.prompt_tokens
            completion_tokens = result.completion_tokens
        except Exception as e:  # noqa: BLE001
            log.warning("llm_failed", error=str(e), error_type=type(e).__name__)
            breaker.failure()
            degraded = True
            mode = "keyword_only"
            breaker.mark_degraded()
            answer = _degraded_answer(chunks, llm.provider)
            citations = citations_for_answer(answer, chunks, retrieval="sparse")
            for c in citations:
                c["retrieval"] = "sparse"
            completion_tokens = 0

    if not degraded:
        if answer.startswith(REFUSAL_PREFIX) or REFUSAL_PREFIX in answer[:80]:
            citations = []
        else:
            citations = citations_for_answer(answer, chunks, retrieval="rrf")

    user_msg = Message(
        id=new_id("msg"),
        chat_id=chat.id,
        user_id=user_id,
        role="user",
        content=query,
        cited_chunk_ids="[]",
        degraded=False,
        created_at=utcnow(),
    )
    asst = Message(
        id=new_id("msg"),
        chat_id=chat.id,
        user_id=user_id,
        role="assistant",
        content=answer,
        cited_chunk_ids=json.dumps([c["chunk_id"] for c in citations]),
        degraded=degraded,
        prompt_tokens=prompt_tokens,
        completion_tokens=completion_tokens,
        latency_ms=int((time.perf_counter() - t0) * 1000),
        created_at=utcnow(),
    )
    db.add(user_msg)
    db.add(asst)
    await db.commit()
    latency_ms = int((time.perf_counter() - t0) * 1000)
    asst.latency_ms = latency_ms
    return AskResult(
        answer=answer,
        citations=citations,
        degraded=degraded,
        mode=mode,
        chat_id=chat.id,
        message_id=asst.id,
        prompt_tokens=prompt_tokens,
        completion_tokens=completion_tokens,
        latency_ms=latency_ms,
        request_id=request_id,
        chunks=chunks,
    )
