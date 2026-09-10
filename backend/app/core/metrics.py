from __future__ import annotations

from prometheus_client import CONTENT_TYPE_LATEST, Counter, Gauge, generate_latest

auth_failures = Counter("auth_failures_total", "Failed auth events", ["reason"])
auth_lockouts = Counter("auth_lockouts_total", "Accounts locked")
refresh_reuse = Counter("refresh_reuse_total", "Rotated refresh token replays")
breaker_state = Gauge("breaker_state", "Circuit breaker (0 closed, 1 open)", ["provider"])
jobs_requeued = Counter("jobs_requeued_total", "Jobs requeued by sweeper")
backup_last_ok = Gauge("backup_last_ok_seconds", "Unix time of last successful backup")
ask_degraded_total = Counter("ask_degraded_total", "Ask requests served in degraded mode")
cache_dim_mismatch_total = Counter(
    "cache_dim_mismatch_total", "embedding_cache rows dropped for dim mismatch"
)


def render_metrics() -> tuple[bytes, str]:
    return generate_latest(), CONTENT_TYPE_LATEST
