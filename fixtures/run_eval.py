"""Eval runner — smoke-10 / full-40. Usage:
  python fixtures/run_eval.py --base http://localhost:8000/v1 --suite smoke
"""
from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).parent
GOLDEN = ROOT / "qa-golden.json"
SEED = ROOT / "docs-seed.json"


def _req(base: str, method: str, path: str, token: str | None = None, body=None, extra=None):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(base + path, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    if extra:
        for k, v in extra.items():
            req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read()
            return r.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"raw": raw.decode("utf-8", "replace")}


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--base", default="http://localhost:8000/v1")
    p.add_argument("--suite", choices=("smoke", "full"), default="smoke")
    p.add_argument("--email", default="eval.phase8@example.com")
    p.add_argument("--password", default="correct-horse-10")
    args = p.parse_args()
    base = args.base.rstrip("/")
    if not base.endswith("/v1"):
        base = base + "/v1"

    golden = json.loads(GOLDEN.read_text(encoding="utf-8"))
    items = golden if args.suite == "full" else [q for q in golden if q.get("suite") == "smoke"]
    if args.suite == "smoke":
        items = items[:10]
    else:
        items = golden[:40]

    seed = json.loads(SEED.read_text(encoding="utf-8"))
    st, reg = _req(base, "POST", "/auth/register", body={"email": args.email, "password": args.password, "display_name": "Eval"})
    if st not in (201, 409):
        st, login = _req(base, "POST", "/auth/login", body={"email": args.email, "password": args.password})
    else:
        login = reg
        if st == 409:
            st, login = _req(base, "POST", "/auth/login", body={"email": args.email, "password": args.password})
    token = login.get("access_token")
    if not token:
        print("auth failed", st, login, file=sys.stderr)
        return 1

    jobs = []
    for d in seed:
        st, acc = _req(
            base,
            "POST",
            "/documents/ingest-text",
            token,
            {"title": d["title"], "text": d["text"], "tags": d.get("tags") or []},
            extra={"X-Idempotency-Key": f"eval-{d['local_id']}"},
        )
        if st in (202, 200) and acc.get("job_id"):
            jobs.append(acc["job_id"])
    t0 = time.time()
    while jobs and time.time() - t0 < 90:
        left = []
        for j in jobs:
            st, body = _req(base, "GET", f"/jobs/{j}", token)
            if body.get("status") not in ("done", "failed"):
                left.append(j)
        jobs = left
        if jobs:
            time.sleep(0.4)

    passed = 0
    failed = []
    for q in items:
        st, body = _req(base, "POST", "/ask", token, {"query": q["query"]})
        ans = (body.get("answer") or "") if st == 200 else ""
        needles = q.get("expect_contains") or []
        hit = all(n.lower() in ans.lower() for n in needles)
        if hit:
            passed += 1
            print(f"OK  {q['id']}  {q['query'][:60]}")
        else:
            failed.append(q["id"])
            print(f"FAIL {q['id']}  status={st}  got={ans[:160]!r}")
    total = len(items)
    print(f"\n{args.suite}: {passed}/{total} passed")
    return 0 if not failed else 1


if __name__ == "__main__":
    raise SystemExit(main())
