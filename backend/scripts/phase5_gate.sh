#!/usr/bin/env bash
# Phase 5: voice ingest + 12min 413 + pytest.
set -euo pipefail
BASE="${BASE:-http://localhost:8000}"
BASE="${BASE%/}"
case "$BASE" in
  */v1) ;;
  *) BASE="$BASE/v1" ;;
esac
ORIGIN="${BASE%/v1}"
EMAIL="${EMAIL:-phase5.gate@example.com}"
PW="${PW:-correct-horse-10}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

echo "gate BASE=$BASE"
curl -sS "$ORIGIN/healthz"; echo

REG=$(curl -sS -X POST "$BASE/auth/register" -H 'Content-Type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PW\",\"display_name\":\"P5\"}" || true)
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
    sys.stderr.write('auth failed\\n'); sys.exit(1)
print(b['access_token'])
")

python3 - <<'PY'
import struct
from pathlib import Path
sr=8000
n=sr*2
data=b"\x00\x00"*n
fmt=struct.pack("<HHIIHH",1,1,sr,sr*2,2,16)
riff=4+(8+16)+(8+len(data))
out=b"RIFF"+struct.pack("<I",riff)+b"WAVE"+b"fmt "+struct.pack("<I",16)+fmt+b"data"+struct.pack("<I",len(data))+data
Path("/tmp/sb_p5.wav").write_bytes(out)
print("wav", len(out))
PY

echo "=== ingest wav ==="
curl -sS -o /tmp/sb_p5_ingest.json -w "HTTP %{http_code} time=%{time_total}s\n" \
  -X POST "$BASE/documents/ingest-file" \
  -H "Authorization: Bearer $AT" \
  -H "X-Idempotency-Key: p5-wav-$$" \
  -F "title=Voice memo gym" \
  -F "file=@/tmp/sb_p5.wav;type=audio/wav"
python3 - <<'PY'
import json
b=json.load(open("/tmp/sb_p5_ingest.json"))
assert b.get("job_id"), b
open("/tmp/sb_p5_job","w").write(b["job_id"])
open("/tmp/sb_p5_doc","w").write(b["document_id"])
print(b)
PY
JOB=$(cat /tmp/sb_p5_job)
for i in $(seq 1 60); do
  J=$(curl -sS "$BASE/jobs/$JOB" -H "Authorization: Bearer $AT")
  ST=$(python3 -c "import json,sys; print(json.load(sys.stdin)['status'])" <<<"$J")
  echo "$ST"
  if [ "$ST" = "done" ]; then break; fi
  if [ "$ST" = "failed" ]; then echo "$J"; exit 1; fi
  sleep 0.4
done
curl -sS "$BASE/documents/$(cat /tmp/sb_p5_doc)" -H "Authorization: Bearer $AT" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['source_type']=='voice', d; assert 'Mon/Wed/Fri' in (d.get('text') or ''), d; print('transcript ok')"

echo "=== 12min 413 ==="
python3 - <<'PY'
import struct
from pathlib import Path
sr=8000
claimed=12*60*sr*2
data=b"\x00\x00"*64
fmt=struct.pack("<HHIIHH",1,1,sr,sr*2,2,16)
riff=4+(8+16)+(8+claimed)
out=b"RIFF"+struct.pack("<I",riff)+b"WAVE"+b"fmt "+struct.pack("<I",16)+fmt+b"data"+struct.pack("<I",claimed)+data
Path("/tmp/sb_p5_long.wav").write_bytes(out)
PY
curl -sS -o /tmp/sb_p5_long.json -w "HTTP %{http_code}\n" \
  -X POST "$BASE/documents/ingest-file" \
  -H "Authorization: Bearer $AT" \
  -F "file=@/tmp/sb_p5_long.wav;type=audio/wav"
python3 -c "import json; b=json.load(open('/tmp/sb_p5_long.json')); assert b.get('error',{}).get('code')=='VALIDATION', b; print('413/validation ok', b['error'].get('details'))"

cd "$ROOT/backend"
if [ -d .venv ]; then source .venv/bin/activate; fi
python -m pytest -q tests/test_voice.py
echo "phase5 gate done"
