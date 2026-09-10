from __future__ import annotations

import asyncio
import json
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

from tests.audio_util import make_wav

SEED = json.loads((Path(__file__).resolve().parents[2] / "fixtures" / "docs-seed.json").read_text(encoding="utf-8"))
BY_ID = {d["local_id"]: d for d in SEED}


async def _token(client, email="search@example.com"):
    r = await client.post("/auth/register", json={"email": email, "password": "correct-horse-10"})
    assert r.status_code == 201, r.text
    return r.json()["access_token"]


async def _ingest_ids(client, token, local_ids):
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
            st = (await client.get(f"/jobs/{jid}", headers=headers)).json()["status"]
            if st == "failed":
                raise AssertionError(jid)
            if st == "done":
                done += 1
        if done == len(jobs):
            return
        await asyncio.sleep(0.05)
    raise TimeoutError(jobs)


async def test_inv_9082_is_rank_one(client):
    token = await _token(client, "invrank@example.com")
    await _ingest_ids(client, token, ["D6", "D11"])
    headers = {"Authorization": f"Bearer {token}"}
    r = await client.get("/search", params={"q": "INV-9082"}, headers=headers)
    assert r.status_code == 200, r.text
    data = r.json()["data"]
    assert data, r.text
    assert "9082" in data[0]["title"]
    assert "9083" not in data[0]["title"]


async def test_q16_q17_invoice_disambiguation(client):
    token = await _token(client, "q16q17@example.com")
    await _ingest_ids(client, token, ["D6", "D11"])
    headers = {"Authorization": f"Bearer {token}"}
    q16 = await client.post(
        "/ask",
        json={"query": "What is the total due on invoice INV-9082?"},
        headers=headers,
    )
    assert q16.status_code == 200, q16.text
    a16 = q16.json()["answer"]
    assert "1,204" in a16 or "1204" in a16, a16
    assert q16.json()["citations"]
    assert "9082" in (q16.json()["citations"][0].get("title") or "")

    q17 = await client.post(
        "/ask",
        json={"query": "What is the total due on the Beta invoice INV-9083?"},
        headers=headers,
    )
    assert q17.status_code == 200, q17.text
    a17 = q17.json()["answer"]
    assert "860" in a17, a17
    assert q17.json()["citations"]
    assert "9083" in (q17.json()["citations"][0].get("title") or "")


async def test_voice_only_last_week_filter(client):
    token = await _token(client, "voicelastweek@example.com")
    headers = {"Authorization": f"Bearer {token}"}
    await _ingest_ids(client, token, ["D6"])
    wav = make_wav(seconds=2.0)
    up = await client.post(
        "/documents/ingest-file",
        files={"file": ("gym.wav", wav, "audio/wav")},
        data={"title": "Voice memo gym"},
        headers=headers,
    )
    assert up.status_code == 202, up.text
    job_id = up.json()["job_id"]
    t0 = time.monotonic()
    while time.monotonic() - t0 < 30:
        st = (await client.get(f"/jobs/{job_id}", headers=headers)).json()["status"]
        if st == "done":
            break
        if st == "failed":
            raise AssertionError("voice ingest failed")
        await asyncio.sleep(0.05)
    else:
        raise TimeoutError("voice")

    doc_id = up.json()["document_id"]
    body = (await client.get(f"/documents/{doc_id}", headers=headers)).json()
    blob = body.get("text") or body.get("title") or "gym"
    toks = [t for t in __import__("re").findall(r"[A-Za-z0-9]{3,}", blob)]
    q = toks[0] if toks else "gym"

    since = (datetime.now(timezone.utc) - timedelta(days=7)).strftime("%Y-%m-%dT%H:%M:%SZ")
    old = (datetime.now(timezone.utc) - timedelta(days=40)).strftime("%Y-%m-%dT%H:%M:%SZ")
    older_to = (datetime.now(timezone.utc) - timedelta(days=30)).strftime("%Y-%m-%dT%H:%M:%SZ")

    hits = await client.get(
        "/search",
        params={"q": q, "source_type": "voice", "from": since},
        headers=headers,
    )
    assert hits.status_code == 200, hits.text
    data = hits.json()["data"]
    assert data, hits.text
    assert all((h.get("source_type") or "voice") == "voice" for h in data)

    none = await client.get(
        "/search",
        params={"q": "gym", "source_type": "voice", "from": old, "to": older_to},
        headers=headers,
    )
    assert none.status_code == 200
    assert none.json()["data"] == []

    listed = await client.get("/documents", params={"source_type": "voice", "from": since}, headers=headers)
    assert listed.status_code == 200
    assert listed.json()["data"]
    assert all(d["source_type"] == "voice" for d in listed.json()["data"])


async def test_patch_rename_and_retag(client):
    token = await _token(client, "retag@example.com")
    headers = {"Authorization": f"Bearer {token}"}
    r = await client.post(
        "/documents/ingest-text",
        json={"title": "Old name", "text": "A note about invoices and Acme.", "tags": ["draft"]},
        headers=headers,
    )
    assert r.status_code == 202, r.text
    doc_id = r.json()["document_id"]
    t0 = time.monotonic()
    while time.monotonic() - t0 < 20:
        if (await client.get(f"/jobs/{r.json()['job_id']}", headers=headers)).json()["status"] == "done":
            break
        await asyncio.sleep(0.05)
    patched = await client.patch(
        f"/documents/{doc_id}",
        json={"title": "Acme invoice note", "tags": ["finance", "invoice"]},
        headers=headers,
    )
    assert patched.status_code == 200, patched.text
    body = patched.json()
    assert body["title"] == "Acme invoice note"
    assert "finance" in body["tags"]
    listed = await client.get("/documents", params={"tag": "invoice"}, headers=headers)
    assert listed.status_code == 200
    ids = [d["id"] for d in listed.json()["data"]]
    assert doc_id in ids
