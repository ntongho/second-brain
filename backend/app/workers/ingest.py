from __future__ import annotations

import json

from sqlalchemy import delete, func, select, text, update

from app.core.clock import utcnow
from app.core.ids import new_id
from app.core.logging import get_logger
from app.db import get_sessionmaker
from app.models.chunk import Chunk
from app.models.document import Document
from app.models.job import Job
from app.services.chunker import chunk_text
from app.services.embed_cache import embed_with_cache
from app.services.embedder import get_embedder
from app.services.pdf_extract import page_for_char
from app.services.vector_store import get_vector_store

log = get_logger("ingest_worker")
WORKER_ID = "bg-local-1"


async def process_ingest_job(job_id: str) -> None:
    Session = get_sessionmaker()
    async with Session() as db:
        now = utcnow()
        claimed = await db.execute(
            update(Job)
            .where(Job.id == job_id, Job.status == "queued")
            .values(
                status="processing",
                worker_id=WORKER_ID,
                started_at=now,
                heartbeat_at=now,
                attempts=Job.attempts + 1,
                updated_at=now,
            )
        )
        await db.commit()
        if claimed.rowcount != 1:
            log.info("job_not_claimed", job_id=job_id)
            return

        job = await db.scalar(select(Job).where(Job.id == job_id))
        if job is None or not job.document_id:
            return
        doc = await db.scalar(select(Document).where(Document.id == job.document_id))
        if doc is None:
            job.status = "failed"
            job.error = "document missing"
            job.finished_at = utcnow()
            await db.commit()
            return

        doc.status = "processing"
        doc.updated_at = utcnow()
        await db.commit()

        try:
            await _wipe_partial(db, doc.id)
            leftover = await db.scalar(select(func.count()).select_from(Chunk).where(Chunk.document_id == doc.id))
            if int(leftover or 0) != 0:
                raise RuntimeError(f"wipe-before-reprocess left {leftover} chunks")
            if doc.source_type == "voice":
                from app.services.audio import load_media_bytes
                from app.services.transcribe import get_transcriber

                loaded = load_media_bytes(doc.id)
                if loaded is None:
                    raise ValueError("audio file missing")
                blob, ext = loaded
                job.progress = 0.15
                job.heartbeat_at = utcnow()
                await db.commit()
                transcript = await get_transcriber().transcribe(blob, filename=f"{doc.id}.{ext}")
                if not (transcript or "").strip():
                    raise ValueError("empty transcript")
                job.progress = 0.45
                job.heartbeat_at = utcnow()
                await db.commit()
                doc.raw_text = transcript.strip()
                doc.char_count = len(doc.raw_text)
                doc.updated_at = utcnow()
                await db.commit()
            tags = json.loads(doc.tags or "[]")
            is_code = "code" in [str(t).lower() for t in tags]
            spans = chunk_text(doc.raw_text, is_code=is_code)
            if not spans:
                raise ValueError("no chunks produced")

            embedder = get_embedder()
            store = get_vector_store()
            texts = [s.text for s in spans]
            vectors: list[list[float]] = []
            # batch ≤100 inside embedder; cache wraps full list in 100s
            for i in range(0, len(texts), 100):
                part = await embed_with_cache(db, embedder, texts[i : i + 100])
                vectors.extend(part)
                job.progress = min(0.9, (i + len(part)) / max(len(texts), 1))
                job.heartbeat_at = utcnow()
                job.updated_at = utcnow()
                await db.commit()

            now = utcnow()
            chunk_rows: list[Chunk] = []
            for span, vec in zip(spans, vectors, strict=True):
                row = Chunk(
                    id=new_id("chk"),
                    document_id=doc.id,
                    user_id=doc.user_id,
                    ord=span.ord,
                    text=span.text,
                    start_char=span.start_char,
                    end_char=span.end_char,
                    page=page_for_char(doc.raw_text, span.start_char, doc.source_type),
                    token_count=max(1, len(span.text) // 4),
                    created_at=now,
                )
                chunk_rows.append(row)
                db.add(row)
            await db.flush()

            for row in chunk_rows:
                await db.execute(
                    text(
                        "INSERT INTO chunks_fts(chunk_id, document_id, user_id, text) "
                        "VALUES (:cid, :did, :uid, :txt)"
                    ),
                    {"cid": row.id, "did": row.document_id, "uid": row.user_id, "txt": row.text},
                )

            await store.upsert(
                ids=[r.id for r in chunk_rows],
                embeddings=vectors,
                metadatas=[
                    {
                        "user_id": doc.user_id,
                        "document_id": doc.id,
                        "source_type": doc.source_type,
                        "tags_csv": ",".join(tags),
                        "page": r.page if r.page is not None else -1,
                        "start_char": r.start_char,
                        "end_char": r.end_char,
                        "created_at_ts": int(now.timestamp()),
                    }
                    for r in chunk_rows
                ],
                documents=[r.text for r in chunk_rows],
            )

            doc.status = "ready"
            doc.error = None
            doc.updated_at = utcnow()
            job.status = "done"
            job.progress = 1.0
            job.finished_at = utcnow()
            job.updated_at = utcnow()
            await db.commit()
            log.info("ingest_done", job_id=job.id, document_id=doc.id, chunks=len(chunk_rows))
        except Exception as e:  # noqa: BLE001
            log.warning("ingest_failed", job_id=job_id, error=str(e))
            await db.rollback()
            job = await db.scalar(select(Job).where(Job.id == job_id))
            doc = await db.scalar(select(Document).where(Document.id == job.document_id)) if job else None
            if job:
                job.status = "failed"
                job.error = str(e)[:500]
                job.finished_at = utcnow()
                job.updated_at = utcnow()
            if doc:
                doc.status = "failed"
                doc.error = str(e)[:500]
                doc.updated_at = utcnow()
            await db.commit()


async def _wipe_partial(db, document_id: str) -> None:
    await db.execute(text("DELETE FROM chunks_fts WHERE document_id = :d"), {"d": document_id})
    await db.execute(delete(Chunk).where(Chunk.document_id == document_id))
    await db.commit()
    try:
        await get_vector_store().delete(where={"document_id": document_id})
    except Exception:  # noqa: BLE001
        pass
