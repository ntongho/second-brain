from __future__ import annotations

import time
from collections import defaultdict, deque

from app.core.errors import AppError


class SlidingWindowLimiter:
    def __init__(self) -> None:
        self._hits: dict[str, deque[float]] = defaultdict(deque)

    def check(self, key: str, limit: int, window_s: float = 60.0) -> None:
        now = time.monotonic()
        q = self._hits[key]
        cutoff = now - window_s
        while q and q[0] < cutoff:
            q.popleft()
        if len(q) >= limit:
            retry_after = max(1, int(window_s - (now - q[0])) + 1)
            raise AppError(
                429,
                "RATE_LIMITED",
                "Too many requests. Try again shortly.",
                details={"limit": limit, "window_s": int(window_s)},
                retryable=True,
                retry_after=retry_after,
            )
        q.append(now)


limiter = SlidingWindowLimiter()
