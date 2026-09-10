from __future__ import annotations

import asyncio
import time

from tests.audio_util import make_wav, make_wav_claiming_duration


async def _token(client, email="voice@example.com"):
    r = await client.post("/auth/register", json={"email": email, "password": "correct-horse-10"})
    assert r.status_code == 201, r.text
    return r.json()["access_token"]


async def _poll(client, token, job_id, timeout=30.0):
    headers = {"Authorization": f"Bearer {token}"}
    t0 = time.monotonic()
    while time.monotonic() - t0 < timeout:
        r = await client.get(f"/jobs/{job_id}", headers=headers)
        body = r.json()
        if body["status"] in {"done", "failed"}:
            return body
        await asyncio.sleep(0.05)
    raise TimeoutError(job_id)


async def test_voice_memo_searchable_and_cited(client):
    token = await _token(client)
    headers = {"Authorization": f"Bearer {token}"}
    wav = make_wav(seconds=2.0)
    r = await client.post(
        "/documents/ingest-file",
        files={"file": ("gym.wav", wav, "audio/wav")},
        data={"title": "Voice memo — gym plan"},
        headers=headers,
    )
    assert r.status_code == 202, r.text
    job = await _poll(client, token, r.json()["job_id"])
    assert job["status"] == "done", job
    doc_id = r.json()["document_id"]
    got = await client.get(f"/documents/{doc_id}", headers=headers)
    body = got.json()
    assert body["source_type"] == "voice"
    assert "Mon/Wed/Fri" in (body.get("text") or "")
    audio = await client.get(f"/documents/{doc_id}/audio", headers=headers)
    assert audio.status_code == 200
    assert audio.headers["content-type"].startswith("audio/")

    ask = await client.post(
        "/ask",
        json={
            "query": "In my voice memos from last week, what did I say about the gym?",
            "filters": {"source_types": ["voice"]},
        },
        headers=headers,
    )
    assert ask.status_code == 200, ask.text
    payload = ask.json()
    ans = payload["answer"]
    assert any(tok in ans for tok in ("Mon/Wed/Fri", "Monday", "Wednesday")), ans
    assert payload["citations"]
    assert payload["citations"][0]["document_id"] == doc_id


async def test_audio_12min_413(client):
    token = await _token(client, "long-audio@example.com")
    wav = make_wav_claiming_duration(12 * 60)
    r = await client.post(
        "/documents/ingest-file",
        files={"file": ("long.wav", wav, "audio/wav")},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert r.status_code == 413, r.text
    details = r.json()["error"]["details"]
    assert details.get("max_seconds") == 600


async def test_audio_not_audio_422(client):
    token = await _token(client, "nota@example.com")
    r = await client.post(
        "/documents/ingest-file",
        files={"file": ("x.bin", b"not-audio-or-pdf", "application/octet-stream")},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert r.status_code == 422
