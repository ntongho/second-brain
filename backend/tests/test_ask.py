from __future__ import annotations

import asyncio
import json
import time
from pathlib import Path

SEED = json.loads(
    (Path(__file__).resolve().parents[2] / "fixtures" / "docs-seed.json").read_text(encoding="utf-8")
)
BY_ID = {d["local_id"]: d for d in SEED}


async def _token(client, email="ask@example.com"):
    r = await client.post(
        "/auth/register",
        json={"email": email, "password": "correct-horse-10", "display_name": "Ask"},
    )
    assert r.status_code == 201, r.text
    return r.json()["access_token"]


async def _ingest(client, token, local_ids):
    headers = {"Authorization": f"Bearer {token}"}
    jobs = []
    for lid in local_ids:
        d = BY_ID[lid]
        r = await client.post(
            "/documents/ingest-text",
            json={"title": d["title"], "text": d["text"], "tags": d["tags"]},
            headers=headers,
        )
        assert r.status_code == 202, r.text
        jobs.append(r.json()["job_id"])
    t0 = time.monotonic()
    while time.monotonic() - t0 < 30:
        done = 0
        for jid in jobs:
            jr = await client.get(f"/jobs/{jid}", headers=headers)
            st = jr.json()["status"]
            if st == "failed":
                raise AssertionError(jr.json())
            if st == "done":
                done += 1
        if done == len(jobs):
            return
        await asyncio.sleep(0.05)
    raise TimeoutError(jobs)


async def test_q1_q2_q3_cite_and_q6_refusal(client):
    token = await _token(client)
    await _ingest(client, token, ["D1", "D2", "D3", "D4", "D5", "D10"])
    headers = {"Authorization": f"Bearer {token}"}

    q1 = await client.post(
        "/ask",
        json={"query": "According to the compound-interest article, what is the rule of 72?"},
        headers=headers,
    )
    assert q1.status_code == 200, q1.text
    a1 = q1.json()["answer"]
    assert "72" in a1 and "doubles" in a1 and "12 years" in a1
    assert q1.json()["citations"]

    q2 = await client.post(
        "/ask",
        json={"query": "Summarize everything I've saved about my Japan trip, with total food spend."},
        headers=headers,
    )
    assert q2.status_code == 200, q2.text
    a2 = q2.json()["answer"]
    assert "¥18,200" in a2 and "Kyoto" in a2
    assert q2.json()["citations"]

    q3 = await client.post(
        "/ask",
        json={"query": "What did we decide about the Q3 budget in the Aug 20 meeting?"},
        headers=headers,
    )
    assert q3.status_code == 200, q3.text
    assert "freeze hiring" in q3.json()["answer"]
    assert q3.json()["citations"]

    q6 = await client.post(
        "/ask",
        json={"query": "What does my library say about crypto taxes?"},
        headers=headers,
    )
    assert q6.status_code == 200, q6.text
    assert "Not in your library" in q6.json()["answer"]
    assert q6.json()["citations"] == []


async def test_empty_query_400(client):
    token = await _token(client, "empty@example.com")
    r = await client.post("/ask", json={"query": ""}, headers={"Authorization": f"Bearer {token}"})
    assert r.status_code == 400


async def test_degraded_keyword_only(client):
    token = await _token(client, "deg@example.com")
    await _ingest(client, token, ["D1"])
    t0 = time.perf_counter()
    r = await client.post(
        "/ask",
        json={"query": "What is the rule of 72?"},
        headers={"Authorization": f"Bearer {token}", "X-Test-Force-Breaker": "open"},
    )
    ms = (time.perf_counter() - t0) * 1000
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["degraded"] is True
    assert body["mode"] == "keyword_only"
    assert body["usage"]["completion_tokens"] == 0
    assert "AI generation is unavailable" in body["answer"] or "keyword" in body["answer"].lower()
    assert all(c.get("retrieval") == "sparse" for c in body["citations"])
    assert ms < 6000  # ASGITransport includes retrieve; live gate is <600ms


async def test_ask_idempotency_replay_no_dup(client):
    token = await _token(client, "idem@example.com")
    await _ingest(client, token, ["D1"])
    headers = {
        "Authorization": f"Bearer {token}",
        "X-Idempotency-Key": "ask-key-1",
    }
    body = {"query": "What is the rule of 72?"}
    r1 = await client.post("/ask", json=body, headers=headers)
    assert r1.status_code == 200, r1.text
    r2 = await client.post("/ask", json=body, headers=headers)
    assert r2.status_code == 200, r2.text
    assert r1.json()["message_id"] == r2.json()["message_id"]
    assert r1.json()["chat_id"] == r2.json()["chat_id"]
    msgs = await client.get(f"/chats/{r1.json()['chat_id']}/messages", headers={"Authorization": f"Bearer {token}"})
    assert msgs.status_code == 200
    # one user + one assistant, not doubled
    assert len(msgs.json()["data"]) == 2

    conflict = await client.post(
        "/ask",
        json={"query": "totally different question about invoices"},
        headers=headers,
    )
    assert conflict.status_code == 409
    assert conflict.json()["error"]["code"] == "CONFLICT"


async def test_ask_stream_events(client):
    token = await _token(client, "sse@example.com")
    await _ingest(client, token, ["D1"])
    r = await client.post(
        "/ask/stream",
        json={"query": "What is the rule of 72?"},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert r.status_code == 200
    text = r.text
    assert "event: meta" in text
    assert "event: citation" in text
    assert "event: done" in text
    assert "event: token" in text
