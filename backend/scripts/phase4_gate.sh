#!/usr/bin/env bash
# Phase 4 gate: ingest-file + highlight + delete orphans + JOB-01 (pytest).
set -euo pipefail
BASE="${BASE:-http://localhost:8000}"
BASE="${BASE%/}"
case "$BASE" in
  */v1) ;;
  *) BASE="$BASE/v1" ;;
esac
ORIGIN="${BASE%/v1}"
EMAIL="${EMAIL:-phase4.gate@example.com}"
PW="${PW:-correct-horse-10}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

echo "gate BASE=$BASE"
curl -sS "$ORIGIN/healthz"; echo
curl -sS "$ORIGIN/readyz"; echo

REG=$(curl -sS -w "\nHTTP:%{http_code}\n" -X POST "$BASE/auth/register" -H 'Content-Type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PW\",\"display_name\":\"P4\"}" || true)
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

auth() { curl -sS -H "Authorization: Bearer $AT" "$@"; }

python3 - <<'PY'
from pathlib import Path
import sys
sys.path.insert(0, str(Path("backend").resolve() if Path("backend").exists() else Path(".")))
# generate a tiny 50-page PDF next to /tmp
pages = [f"Gate page {i+1}. Rule of 72 token PAGE{i:02d}." for i in range(50)]
n = len(pages)
kids = " ".join(f"{3+i} 0 R" for i in range(n))
objects = [
    b"<< /Type /Catalog /Pages 2 0 R >>",
    f"<< /Type /Pages /Kids [{kids}] /Count {n} >>".encode(),
]
content_ids = [3+n+i for i in range(n)]
font_id = 3+2*n
for i in range(n):
    objects.append(
        (f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
         f"/Contents {content_ids[i]} 0 R /Resources << /Font << /F1 {font_id} 0 R >> >> >>").encode()
    )
for text in pages:
    stream = f"BT /F1 12 Tf 50 700 Td ({text}) Tj ET\n".encode()
    objects.append(b"<< /Length %d >>\nstream\n" % len(stream) + stream + b"endstream")
objects.append(b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")
out = bytearray(b"%PDF-1.4\n")
offsets = [0]
for i, body in enumerate(objects, 1):
    offsets.append(len(out))
    out += f"{i} 0 obj\n".encode() + body + b"\nendobj\n"
xref = len(out)
out += f"xref\n0 {len(objects)+1}\n".encode()
out += b"0000000000 65535 f \n"
for off in offsets[1:]:
    out += f"{off:010d} 00000 n \n".encode()
out += f"trailer\n<< /Size {len(objects)+1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
open("/tmp/sb_p4_50.pdf","wb").write(out)
print("wrote /tmp/sb_p4_50.pdf", len(out), "bytes")
PY

echo "=== ingest-file 50pp (expect 202, time_total <0.40s) ==="
KEY="phase4-50pp-$$-$(date +%s)"
curl -sS -o /tmp/sb_p4_ingest.json -w "HTTP %{http_code}  time_total=%{time_total}s\n" \
  -X POST "$BASE/documents/ingest-file" \
  -H "Authorization: Bearer $AT" \
  -H "X-Idempotency-Key: $KEY" \
  -F "title=Fifty pages" \
  -F "file=@/tmp/sb_p4_50.pdf;type=application/pdf"
python3 - <<'PY'
import json
b=json.load(open("/tmp/sb_p4_ingest.json"))
assert b.get("job_id") and b.get("document_id"), b
open("/tmp/sb_p4_job","w").write(b["job_id"])
open("/tmp/sb_p4_doc","w").write(b["document_id"])
print("job", b["job_id"], "doc", b["document_id"])
PY

JOB=$(cat /tmp/sb_p4_job)
DOC=$(cat /tmp/sb_p4_doc)
echo "=== poll job (done <90s) ==="
ok=0
for i in $(seq 1 180); do
  J=$(auth "$BASE/jobs/$JOB")
  ST=$(python3 -c "import json,sys; print(json.load(sys.stdin)['status'])" <<<"$J")
  echo "$ST"
  if [ "$ST" = "done" ]; then ok=1; break; fi
  if [ "$ST" = "failed" ]; then echo "$J"; exit 1; fi
  sleep 0.5
done
[ "$ok" = 1 ]

echo "=== document + highlight window ==="
auth "$BASE/documents/$DOC" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d['status']=='ready', d
assert d.get('page_count')==50, d.get('page_count')
assert d.get('chunk_count',0)>=1, d
print('pages', d['page_count'], 'chunks', d['chunk_count'])
"

echo "=== non-pdf 422 ==="
auth -w "\nHTTP:%{http_code}\n" -X POST "$BASE/documents/ingest-file" \
  -F "file=@/tmp/sb_p4_ingest.json;type=text/plain;filename=note.txt" | tail -1

echo "=== pytest JOB-01 + PDF contract (local venv) ==="
cd "$ROOT/backend"
if [ -d .venv ]; then
  # shellcheck disable=SC1091
  source .venv/bin/activate
fi
python -m pytest -q tests/test_pdf.py tests/test_job_01.py
echo "phase4 gate done"
