from __future__ import annotations

import time
from datetime import timedelta

from sqlalchemy import or_, select, update

from app.core.clock import utcnow
from app.core.logging import get_logger
from app.core.metrics import jobs_requeued
from app.db import get_sessionmaker
from app.models.job import Job

log = get_logger("jobs_sweep")

_sweep = {"done": False, "duration_ms": 0, "requeued": 0}

# Stuck worker: no heartbeat for this long → requeue (attempts kept).
STALE_AFTER = timedelta(seconds=90)


def sweep_status() -> dict:
    return dict(_sweep)


def mark_sweep(*, done: bool, duration_ms: int = 0, requeued: int = 0) -> None:
    _sweep["done"] = done
    _sweep["duration_ms"] = duration_ms
    _sweep["requeued"] = requeued


async def boot_sweep() -> dict:
    """processing → queued (attempts preserved). Worker wipe-before-reprocess on claim."""
    t0 = time.perf_counter()
    Session = get_sessionmaker()
    async with Session() as db:
        now = utcnow()
        result = await db.execute(
            update(Job)
            .where(Job.status == "processing")
            .values(status="queued", worker_id=None, error=None, updated_at=now)
        )
        await db.commit()
        n = int(result.rowcount or 0)
    if n:
        jobs_requeued.inc(n)
    duration_ms = int((time.perf_counter() - t0) * 1000)
    log.info("boot_sweep", requeued=n, duration_ms=duration_ms)
    mark_sweep(done=True, duration_ms=duration_ms, requeued=n)
    return {"requeued": n, "duration_ms": duration_ms}


async def heartbeat_sweep() -> dict:
    """Requeue processing jobs whose heartbeat is stale (live process, not boot)."""
    Session = get_sessionmaker()
    async with Session() as db:
        now = utcnow()
        cutoff = now - STALE_AFTER
        result = await db.execute(
            update(Job)
            .where(
                Job.status == "processing",
                or_(Job.heartbeat_at.is_(None), Job.heartbeat_at < cutoff),
            )
            .values(status="queued", worker_id=None, error="stale heartbeat", updated_at=now)
        )
        await db.commit()
        n = int(result.rowcount or 0)
    if n:
        jobs_requeued.inc(n)
        log.info("heartbeat_sweep", requeued=n)
    return {"requeued": n}


async def queued_jobs() -> list[tuple[str, str]]:
    Session = get_sessionmaker()
    async with Session() as db:
        rows = (await db.execute(select(Job.id, Job.kind).where(Job.status == "queued"))).all()
    return [(r[0], r[1]) for r in rows]


async def queued_job_ids() -> list[str]:
    return [jid for jid, _ in await queued_jobs()]


async def resume_queued_jobs() -> None:
    import asyncio

    from app.workers.backup import process_backup_job
    from app.workers.ingest import process_ingest_job

    for jid, kind in await queued_jobs():
        if kind == "backup":
            asyncio.create_task(process_backup_job(jid))
        else:
            asyncio.create_task(process_ingest_job(jid))
