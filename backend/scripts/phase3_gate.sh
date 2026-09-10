#!/usr/bin/env bash
# Phase 3 backend slice: idempotent /ask + SSE. Flutter gate is on the laptop.
set -euo pipefail
BASE="${BASE:-http://localhost:8000}"
BASE="${BASE%/}"
case "$BASE" in
  */v1) ;;
  *) BASE="$BASE/v1" ;;
esac
EMAIL="${EMAIL:-phase3.gate@example.com}"
PW="${PW:-correct-horse-10}"
ORIGIN="${BASE%/v1}"

echo "gate BASE=$BASE"
curl -sS "$ORIGIN/healthz"; echo

REG=$(curl -sS -w "\nHTTP:%{http_code}\n" -X POST "$BASE/auth/register" -H 'Content-Type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PW\"}" || true)
LOGIN=$(curl -sS -w "\nHTTP:%{http_code}\n" -X POST "$BASE/auth/login" -H 'Content-Type: application/json' \
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

auth() { curl -sS -H "Authorization: Bearer $AT" -H "Content-Type: application/json" "$@"; }

auth -X POST "$BASE/documents/ingest-text" -H "X-Idempotency-Key: p3-d1" \
  -d '{"title":"Compound Interest","text":"The Rule of 72 estimates doubling time: divide 72 by the annual rate. At 6%, money doubles in about 12 years.","tags":["gate"]}'
echo
sleep 2

K="p3-ask-$$"
echo "=== ask twice same key $K ==="
auth -X POST "$BASE/ask" -H "X-Idempotency-Key: $K" \
  -d '{"query":"What is the rule of 72?"}' > /tmp/p3_a1.json
auth -X POST "$BASE/ask" -H "X-Idempotency-Key: $K" \
  -d '{"query":"What is the rule of 72?"}' > /tmp/p3_a2.json
python3 - <<'PY'
import json
a1=json.load(open("/tmp/p3_a1.json"))
a2=json.load(open("/tmp/p3_a2.json"))
assert a1.get("message_id") and a1["message_id"]==a2["message_id"], (a1, a2)
print("replay ok", a1["message_id"], "degraded", a1.get("degraded"))
PY

echo "=== conflict different body ==="
auth -w "\nHTTP:%{http_code}\n" -X POST "$BASE/ask" -H "X-Idempotency-Key: $K" \
  -d '{"query":"something else entirely about invoices"}'
echo

echo "=== stream ==="
auth -N -X POST "$BASE/ask/stream" -H "X-Idempotency-Key: $K-stream" \
  -H "Accept: text/event-stream" \
  -d '{"query":"What is the rule of 72?"}' | head -c 1500
echo
echo "phase3 backend gate done"
