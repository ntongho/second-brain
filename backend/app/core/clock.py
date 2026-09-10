from __future__ import annotations

from datetime import datetime, timezone


def utcnow() -> datetime:
    """Single clock seam so freezegun (and tests) can freeze time."""
    return datetime.now(timezone.utc)
