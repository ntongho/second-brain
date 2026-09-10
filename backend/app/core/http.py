from __future__ import annotations

import httpx

_client: httpx.AsyncClient | None = None


def http_client() -> httpx.AsyncClient:
    """Reuse one client so TLS/TCP isn't set up on every embed/ask."""
    global _client
    if _client is None or _client.is_closed:
        _client = httpx.AsyncClient(timeout=60.0)
    return _client
