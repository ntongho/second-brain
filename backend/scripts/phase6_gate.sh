#!/usr/bin/env bash
# Phase 6: INV-9082 rank-1, invoice disambiguation, filters, pytest.
set -euo pipefail
BASE="${BASE:-http://localhost:8000}"
BASE="${BASE%/}"
case "$BASE" in
  */v1) ;;
  *) BASE="$BASE/v1" ;;
esac
ORIGIN="${BASE%/v1}"
EMAIL="${EMAIL:-phase6.gate@example.com}"
PW="${PW:-correct-horse-10}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

echo "gate BASE=$BASE"
curl -sS "$ORIGIN/healthz"; echo

REG=$(curl -sS -X POST "$BASE/auth/register" -H 'Content-Type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PW\",\"display_name\":\"P6\"}" || true)
LOGIN=$(curl -sS -X POST "$BASE/auth/login" -H 'Content-Type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PW\"}" || true)
AT=$(REG="$REG" LOGIN="$LOGIN" python3 -c "
import json, os, sys
def parse(raw):
    i = (raw or '').find('{')
    if i < 0: return {}
    try: return json.loads(raw[i:raw.rfind('}')+1])
    except Exception: return {}
b = parse(os.environ.get('REG',''))
if 'access_token' not in b: b = parse(os.environ.get('LOGIN',''))
if 'access_token' not in b:
    sys.stderr.write('auth failed\n'); sys.exit(1)
print(b['access_token'])
")

python3 - <<PY
import json, urllib.request
from pathlib import Path
seed = json.loads((Path("$ROOT")/"fixtures"/"docs-seed.json").read_text())
by = {d["local_id"]: d for d in seed}
base = "$BASE"
at = "$AT"
def post(path, body, extra=None):
    req = urllib.request.Request(base+path, data=json.dumps(body).encode(), method="POST")
    req.add_header("Authorization", "Bearer "+at)
    req.add_header("Content-Type", "application/json")
    if extra:
        for k,v in extra.items(): req.add_header(k,v)
    with urllib.request.urlopen(req) as r:
        return json.load(r)
def get(path):
    req = urllib.request.Request(base+path)
    req.add_header("Authorization", "Bearer "+at)
    with urllib.request.urlopen(req) as r:
        return json.load(r)
jobs=[]
for lid in ("D6","D11"):
    d=by[lid]
    acc=post("/documents/ingest-text", {"title": d["title"], "text": d["text"], "tags": d["tags"]},
             extra={"X-Idempotency-Key": f"p6-{lid}-$$"})
    jobs.append(acc["job_id"])
import time
t0=time.time()
while time.time()-t0<40:
    if all(get(f"/jobs/{j}")["status"]=="done" for j in jobs):
        break
    time.sleep(0.3)
else:
    raise SystemExit("ingest timeout")
hits=get("/search?q=INV-9082")
assert hits["data"], hits
assert "9082" in hits["data"][0]["title"], hits["data"][0]
print("INV-9082 rank-1 ok", hits["data"][0]["title"])
ask=post("/ask", {"query": "What is the total due on invoice INV-9082?"})
ans=ask["answer"]
assert "1,204" in ans or "1204" in ans, ans
print("Q16 ok")
ask=post("/ask", {"query": "What is the total due on the Beta invoice INV-9083?"})
assert "860" in ask["answer"], ask["answer"]
print("Q17 ok")
PY

cd "$ROOT/backend"
if [ -d .venv ]; then source .venv/bin/activate; fi
python -m pytest -q tests/test_search.py
echo "phase6 gate done"
