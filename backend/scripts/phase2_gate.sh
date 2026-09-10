#!/usr/bin/env bash
# Phase 2: ingest D1/D2/D4/D5/D10 then Q1–Q3 + Q6 + degraded.
# Run from anywhere: bash backend/scripts/phase2_gate.sh
# BASE may be origin (http://127.0.0.1:8000) or already include /v1.
set -euo pipefail
BASE="${BASE:-http://localhost:8000}"
BASE="${BASE%/}"
case "$BASE" in
  */v1) ;;
  *) BASE="$BASE/v1" ;;
esac
EMAIL="${EMAIL:-phase2.gate@example.com}"
PW="${PW:-correct-horse-10}"

call() {
  curl -sS -H "Authorization: Bearer $AT" -H "Content-Type: application/json" "$@"
}

echo "gate BASE=$BASE email=$EMAIL"
REG=$(curl -sS -w "\nHTTP:%{http_code}\n" -X POST "$BASE/auth/register" -H 'Content-Type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PW\"}" || true)
LOGIN=$(curl -sS -w "\nHTTP:%{http_code}\n" -X POST "$BASE/auth/login" -H 'Content-Type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PW\"}" || true)
AT=$(REG="$REG" LOGIN="$LOGIN" python3 -c "
import json, os, sys
def parse(raw):
    raw = raw or ''
    i = raw.find('{')
    if i < 0:
        return {}
    try:
        return json.loads(raw[i:raw.rfind('}')+1])
    except Exception:
        return {}
b = parse(os.environ.get('REG',''))
if 'access_token' not in b:
    b = parse(os.environ.get('LOGIN',''))
if 'access_token' not in b:
    sys.stderr.write('auth failed. Is uvicorn up? Try: curl -sS \$BASE/healthz\\n')
    sys.stderr.write('register=' + os.environ.get('REG','')[:400] + '\\n')
    sys.stderr.write('login=' + os.environ.get('LOGIN','')[:400] + '\\n')
    sys.exit(1)
print(b['access_token'])
")

ingest() {
  local title="$1" text="$2"
  call -X POST "$BASE/documents/ingest-text" -d "$(python3 -c "import json,sys; print(json.dumps({'title':sys.argv[1],'text':sys.argv[2],'tags':['gate']}))" "$title" "$text")"
}

python3 - <<'PY'
import json, pathlib, urllib.request, os, time
# just print confirmation we'll ingest via curl below
print("seeding via curl...")
PY

# Minimal corpus for Q1, Q2, Q3, Q6
D1='Compound interest is interest earned on both principal and previously earned interest. The Rule of 72 estimates doubling time: divide 72 by the annual rate. At 6%, money doubles in about 12 years.'
D2='Kyoto food log: kaiseki dinner ¥8,000. Total Kyoto food: ¥10,300.'
D4='Total Osaka food: ¥7,900. Combined Japan food so far: Kyoto ¥10,300 + Osaka ¥7,900 = ¥18,200. Most expensive food city: Kyoto (kaiseki dinner).'
D5='Decisions: (1) Q3 budget: freeze hiring, cap travel at $4k/mo. Open: office lease renewal — no decision.'
D10='Bitcoin ETF inflows hit $2.1B. The piece discusses price action only. It contains no tax advice and no discussion of capital-gains rules.'

for pair in "Compound Interest|$D1" "Kyoto Food|$D2" "Osaka Budget|$D4" "Budget Meeting|$D5" "Crypto blog|$D10"; do
  title="${pair%%|*}"
  text="${pair#*|}"
  echo "ingest $title"
  call -X POST "$BASE/documents/ingest-text" \
    -d "$(TITLE="$title" TEXT="$text" python3 -c 'import json,os; print(json.dumps({"title":os.environ["TITLE"],"text":os.environ["TEXT"],"tags":["gate"]}))')"
  echo
done
sleep 2

ask() {
  echo "=== $1 ==="
  call -X POST "$BASE/ask" -d "$2"
  echo
}

ask Q1 '{"query":"According to the compound-interest article, what is the rule of 72?"}'
ask Q2 '{"query":"Summarize everything I saved about my Japan trip, with total food spend."}'
ask Q3 '{"query":"What did we decide about the Q3 budget in the Aug 20 meeting?"}'
ask Q6 '{"query":"What does my library say about crypto taxes?"}'
echo "=== degraded ==="
call -X POST "$BASE/ask" -H "X-Test-Force-Breaker: open" \
  -d '{"query":"What is the rule of 72?"}'
echo
