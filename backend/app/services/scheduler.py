from __future__ import annotations

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger
from apscheduler.triggers.interval import IntervalTrigger

from app.core.config import get_settings
from app.core.logging import get_logger

log = get_logger("scheduler")

_scheduler: AsyncIOScheduler | None = None


async def _sweep_tick() -> None:
    from app.services.jobs_sweep import heartbeat_sweep, resume_queued_jobs

    await heartbeat_sweep()
    await resume_queued_jobs()


async def _daily_backup() -> None:
    from app.services.backup import snapshot

    await snapshot()


def start_scheduler() -> None:
    global _scheduler
    if get_settings().app_env == "test":
        return
    if _scheduler is not None:
        return
    sched = AsyncIOScheduler(timezone="UTC")
    sched.add_job(_sweep_tick, IntervalTrigger(seconds=30), id="heartbeat_sweep", replace_existing=True)
    sched.add_job(_daily_backup, CronTrigger(hour=3, minute=15), id="daily_backup", replace_existing=True)
    sched.start()
    _scheduler = sched
    log.info("scheduler_started")


def stop_scheduler() -> None:
    global _scheduler
    if _scheduler is None:
        return
    _scheduler.shutdown(wait=False)
    _scheduler = None
