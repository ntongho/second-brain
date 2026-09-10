from __future__ import annotations

from sqlalchemy import select, update

from app.core.clock import utcnow
from app.core.logging import get_logger
from app.db import get_sessionmaker
from app.models.job import Job
from app.services.backup import snapshot

log = get_logger("backup_worker")
WORKER_ID = "bg-backup-1"


async def process_backup_job(job_id: str) -> None:
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
            return
        job = await db.scalar(select(Job).where(Job.id == job_id))
        if job is None:
            return
        try:
            row = await snapshot()
            job = await db.scalar(select(Job).where(Job.id == job_id))
            if job is None:
                return
            if row.sqlite_ok:
                job.status = "done"
                job.progress = 1.0
                job.error = None
            else:
                job.status = "failed"
                job.error = row.error or "snapshot failed"
            job.finished_at = utcnow()
            job.heartbeat_at = utcnow()
            job.updated_at = utcnow()
            await db.commit()
        except Exception as e:  # noqa: BLE001
            log.warning("backup_job_failed", job_id=job_id, error=str(e))
            await db.rollback()
            job = await db.scalar(select(Job).where(Job.id == job_id))
            if job:
                job.status = "failed"
                job.error = str(e)[:500]
                job.finished_at = utcnow()
                job.updated_at = utcnow()
                await db.commit()
