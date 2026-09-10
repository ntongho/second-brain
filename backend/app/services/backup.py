from __future__ import annotations

import json
import shutil
import sqlite3
from pathlib import Path

from sqlalchemy import func, select

from app.core.clock import utcnow
from app.core.config import get_settings
from app.core.ids import new_id
from app.core.logging import get_logger
from app.core.metrics import backup_last_ok
from app.db import get_sessionmaker
from app.models.backup import Backup
from app.models.user import User

log = get_logger("backup")
_last_ok: float | None = None


def last_ok_unix() -> float | None:
    return _last_ok


def sqlite_path() -> Path:
    url = get_settings().database_url
    if ":///" not in url:
        raise RuntimeError("restore/backup only supports on-disk sqlite")
    return Path(url.split(":///", 1)[1]).expanduser().resolve()


def _dir_size(path: Path) -> int:
    if not path.exists():
        return 0
    if path.is_file():
        return path.stat().st_size
    total = 0
    for p in path.rglob("*"):
        if p.is_file():
            total += p.stat().st_size
    return total


async def latest_backup() -> Backup | None:
    Session = get_sessionmaker()
    async with Session() as db:
        return await db.scalar(select(Backup).where(Backup.sqlite_ok == 1).order_by(Backup.created_at.desc()))


async def list_backups(limit: int = 20) -> list[Backup]:
    Session = get_sessionmaker()
    async with Session() as db:
        rows = (
            await db.scalars(select(Backup).order_by(Backup.created_at.desc()).limit(limit))
        ).all()
    return list(rows)


async def snapshot() -> Backup:
    """Copy sqlite (VACUUM INTO) + chroma into BACKUPS_PATH. Records a row."""
    settings = get_settings()
    bid = new_id("bak")
    now = utcnow()
    stamp = now.strftime("%Y%m%dT%H%M%SZ")
    dest = Path(settings.backups_path).resolve() / f"snap-{stamp}-{bid}"
    dest.mkdir(parents=True, exist_ok=True)
    sqlite_ok = 0
    chroma_ok = 0
    err: str | None = None
    try:
        src = sqlite_path()
        target = dest / "app.db"
        if not src.exists():
            raise FileNotFoundError(str(src))
        # VACUUM INTO needs a connection that isn't mid-WAL-checkpoint-fail.
        conn = sqlite3.connect(str(src), timeout=10)
        try:
            conn.execute("PRAGMA wal_checkpoint(PASSIVE)")
            dest_sql = str(target).replace("'", "''")
            conn.execute(f"VACUUM INTO '{dest_sql}'")
        finally:
            conn.close()
        sqlite_ok = 1 if target.exists() and target.stat().st_size > 0 else 0

        chroma_src = Path(settings.chroma_path).resolve()
        chroma_dst = dest / "chroma"
        if chroma_src.exists():
            shutil.copytree(chroma_src, chroma_dst, dirs_exist_ok=True)
        else:
            chroma_dst.mkdir(exist_ok=True)
        chroma_ok = 1

        (dest / "manifest.json").write_text(
            json.dumps(
                {
                    "id": bid,
                    "created_at": now.isoformat(),
                    "sqlite": "app.db",
                    "chroma": "chroma",
                },
                indent=2,
            ),
            encoding="utf-8",
        )
    except Exception as e:  # noqa: BLE001
        err = str(e)[:500]
        log.warning("snapshot_failed", error=err, backup_id=bid)

    size = _dir_size(dest)
    row = Backup(
        id=bid,
        path=str(dest),
        size_bytes=size,
        sqlite_ok=sqlite_ok,
        chroma_ok=chroma_ok,
        error=err,
        created_at=now,
    )
    Session = get_sessionmaker()
    async with Session() as db:
        db.add(row)
        await db.commit()
    if sqlite_ok:
        global _last_ok
        _last_ok = now.timestamp()
        backup_last_ok.set(_last_ok)
        log.info("snapshot_ok", backup_id=bid, bytes=size)
    return row


async def users_empty() -> bool:
    Session = get_sessionmaker()
    async with Session() as db:
        n = int(await db.scalar(select(func.count()).select_from(User)) or 0)
    return n == 0


async def restore(*, backup_id: str | None = None) -> dict:
    """Replace sqlite+chroma from a snapshot. Refused unless users table is empty."""
    if not await users_empty():
        raise PermissionError("restore only allowed when users table is empty")

    Session = get_sessionmaker()
    async with Session() as db:
        if backup_id:
            row = await db.scalar(select(Backup).where(Backup.id == backup_id))
        else:
            row = await db.scalar(
                select(Backup).where(Backup.sqlite_ok == 1).order_by(Backup.created_at.desc())
            )
    if row is None or not row.sqlite_ok:
        raise FileNotFoundError("no successful backup to restore")

    snap = Path(row.path)
    src_db = snap / "app.db"
    if not src_db.exists():
        raise FileNotFoundError(str(src_db))

    from app.db import get_engine, reset_engine
    from app.services.vector_store import reset_vector_store

    engine = get_engine()
    await engine.dispose()
    reset_engine()
    reset_vector_store()

    dest_db = sqlite_path()
    dest_db.parent.mkdir(parents=True, exist_ok=True)
    for extra in (dest_db, Path(str(dest_db) + "-wal"), Path(str(dest_db) + "-shm")):
        if extra.exists():
            extra.unlink()
    shutil.copy2(src_db, dest_db)

    chroma_src = snap / "chroma"
    chroma_dst = Path(get_settings().chroma_path).resolve()
    if chroma_src.exists():
        if chroma_dst.exists():
            shutil.rmtree(chroma_dst)
        shutil.copytree(chroma_src, chroma_dst)

    from app.db import init_db

    await init_db()
    log.info("restore_ok", backup_id=row.id)
    return {"restored": True, "backup_id": row.id, "path": row.path}
