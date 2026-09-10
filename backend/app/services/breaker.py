from __future__ import annotations

import time

from app.core.metrics import ask_degraded_total, breaker_state

CLOSED, OPEN, HALF_OPEN = "closed", "open", "half_open"


class CircuitBreaker:
    """5 consecutive 429/5xx → OPEN 60s, half-open probe 1 req (01 §4.10)."""

    def __init__(self, name: str, fail_max: int = 5, reset_timeout: float = 60.0) -> None:
        self.name = name
        self.fail_max = fail_max
        self.reset_timeout = reset_timeout
        self.failures = 0
        self.state = CLOSED
        self.opened_at = 0.0
        self._force_open = False
        breaker_state.labels(provider=name).set(0)

    def force_open(self, on: bool = True) -> None:
        self._force_open = on
        if on:
            self.state = OPEN
            self.opened_at = time.monotonic()
            breaker_state.labels(provider=self.name).set(1)

    def allow(self) -> bool:
        if self._force_open:
            return False
        now = time.monotonic()
        if self.state == OPEN:
            if now - self.opened_at >= self.reset_timeout:
                self.state = HALF_OPEN
                return True
            return False
        return True

    def success(self) -> None:
        self.failures = 0
        self.state = CLOSED
        self._force_open = False
        breaker_state.labels(provider=self.name).set(0)

    def failure(self) -> None:
        self.failures += 1
        if self.failures >= self.fail_max or self.state == HALF_OPEN:
            self.state = OPEN
            self.opened_at = time.monotonic()
            breaker_state.labels(provider=self.name).set(1)

    def mark_degraded(self) -> None:
        ask_degraded_total.inc()


_breakers: dict[str, CircuitBreaker] = {}


def get_breaker(name: str = "gemini") -> CircuitBreaker:
    if name not in _breakers:
        _breakers[name] = CircuitBreaker(name)
    return _breakers[name]


def reset_breakers() -> None:
    _breakers.clear()
