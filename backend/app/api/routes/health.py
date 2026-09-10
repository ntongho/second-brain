from __future__ import annotations

from fastapi import APIRouter, Response

from app.core.config import get_settings
from app.core.metrics import render_metrics
from app.services.jobs_sweep import sweep_status

router = APIRouter(tags=["ops"])


@router.get("/healthz")
async def healthz() -> dict:
    return {"ok": True}


@router.get("/readyz")
async def readyz() -> dict:
    s = get_settings()
    sweep = sweep_status()
    from datetime import datetime, timezone

    from app.services.backup import last_ok_unix

    last = last_ok_unix()
    last_iso = datetime.fromtimestamp(last, tz=timezone.utc).isoformat() if last else None
    return {
        "ready": bool(sweep["done"]),
        "models": {"embed": s.embed_model, "gen": s.gen_model},
        "sweep": {"done": sweep["done"], "duration_ms": sweep["duration_ms"], "requeued": sweep["requeued"]},
        "backup": {"last_ok": last_iso},
    }


@router.get("/metrics")
async def metrics() -> Response:
    payload, ctype = render_metrics()
    return Response(content=payload, media_type=ctype)
