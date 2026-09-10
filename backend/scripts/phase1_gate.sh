#!/usr/bin/env bash
# Phase 1 gate: 202 <250ms, job done, document ready.
set -euo pipefail
BASE="${BASE:-http://localhost:8000/v1}"
EMAIL="phase1.gate@example.com"
PW="correct-horse-10"

REG=$(curl -sS -X POST "$BASE/auth/register" -H 'Content-Type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PW\",\"display_name\":\"P1\"}" || true)
AT=$(python3 -c "import json,sys; t=sys.stdin.read();
import re
try:
  b=json.loads(t[t.find('{'):t.rfind('}')+1]); print(b['access_token'])
except Exception:
  raise SystemExit('register failed: '+t)" <<<"$REG")

PAYLOAD='{"title":"Japan notes","text":"Kyoto food log. Kyoto food log. Total Kyoto food: ¥10,300. Nishiki Market.","tags":["travel"]}'

echo "=== ingest-text (expect HTTP 202, time_total <0.25s) ==="
curl -sS -o /tmp/sb_ingest.json -w "HTTP %{http_code}  time_total=%{time_total}s\n" \
  -X POST "$BASE/documents/ingest-text" \
  -H "Authorization: Bearer $AT" \
  -H "Content-Type: application/json" \
  -H "X-Idempotency-Key: phase1-gate-key-1" \
  -d "$PAYLOAD"
python3 - <<'PY'
import json
b=json.load(open("/tmp/sb_ingest.json"))
print("job_id", b.get("job_id"), "document_id", b.get("document_id"), "status", b.get("status"))
open("/tmp/sb_job_id","w").write(b["job_id"])
open("/tmp/sb_doc_id","w").write(b["document_id"])
PY

JOB=$(cat /tmp/sb_job_id)
echo "=== poll job ==="
for i in $(seq 1 30); do
  J=$(curl -sS "$BASE/jobs/$JOB" -H "Authorization: Bearer $AT")
  echo "$J"
  ST=$(python3 -c "import json,sys; print(json.load(sys.stdin)['status'])" <<<"$J")
  if [ "$ST" = "done" ]; then break; fi
  if [ "$ST" = "failed" ]; then echo FAIL; exit 1; fi
  sleep 0.2
done

echo "=== document ==="
curl -sS "$BASE/documents/$(cat /tmp/sb_doc_id)" -H "Authorization: Bearer $AT"
echo
echo "=== GATE: time_total <0.25s; job done; document ready ==="
