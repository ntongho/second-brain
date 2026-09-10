#!/usr/bin/env bash
# Phase 0 gate (05): paste this output for human sign-off before Phase 1.
set -euo pipefail
BASE="${BASE:-http://localhost:8000/v1}"
EMAIL="ada.gate@example.com"
PW="correct-horse-10"

echo "=== 1. register ==="
REG=$(curl -sS -w "\nHTTP %{http_code}\n" -X POST "$BASE/auth/register" \
  -H 'Content-Type: application/json' \
  -H "X-Request-Id: 00000000-0000-0000-0000-000000000001" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PW\",\"display_name\":\"Ada\"}")
echo "$REG"
AT=$(python3 -c "import json,sys; t=sys.stdin.read(); i=t.rfind('{');
import re; print(json.loads(t[t.find('{'):t.rfind('}')+1])['access_token'])" <<<"$REG")
RT=$(python3 -c "import json; import sys; t=sys.stdin.read();
print(json.loads(t[t.find('{'):t.rfind('}')+1])['refresh_token'])" <<<"$REG")

echo "=== 2. me ==="
curl -sS -w "\nHTTP %{http_code}\n" "$BASE/auth/me" -H "Authorization: Bearer $AT"

echo "=== 3. refresh ==="
REF=$(curl -sS -w "\nHTTP %{http_code}\n" -X POST "$BASE/auth/refresh" \
  -H 'Content-Type: application/json' \
  -d "{\"refresh_token\":\"$RT\"}")
echo "$REF"
RT2=$(python3 -c "import json,sys; t=sys.stdin.read(); print(json.loads(t[t.find('{'):t.rfind('}')+1])['refresh_token'])" <<<"$REF")
AT2=$(python3 -c "import json,sys; t=sys.stdin.read(); print(json.loads(t[t.find('{'):t.rfind('}')+1])['access_token'])" <<<"$REF")

echo "=== 4. logout ==="
curl -sS -w "\nHTTP %{http_code}\n" -X POST "$BASE/auth/logout" \
  -H "Authorization: Bearer $AT2" -H 'Content-Type: application/json' \
  -d "{\"refresh_token\":\"$RT2\"}"

echo "=== 5. unauthenticated /documents → 401 ==="
curl -sS -w "\nHTTP %{http_code}\n" "$BASE/documents"

echo "=== 6. AUTH-02 lockout (5x wrong, then correct) ==="
EMAIL2="lockout.gate@example.com"
curl -sS -o /dev/null -X POST "$BASE/auth/register" -H 'Content-Type: application/json' \
  -d "{\"email\":\"$EMAIL2\",\"password\":\"$PW\",\"display_name\":\"Lock\"}"
for i in 1 2 3 4 5; do
  echo -n "wrong $i: "
  curl -sS -w " HTTP %{http_code}\n" -X POST "$BASE/auth/login" -H 'Content-Type: application/json' \
    -d "{\"email\":\"$EMAIL2\",\"password\":\"wrong-password-xx\"}" | tail -n 1
done
echo -n "correct during lock: "
curl -sS -w "\nHTTP %{http_code}\n" -X POST "$BASE/auth/login" -H 'Content-Type: application/json' \
  -d "{\"email\":\"$EMAIL2\",\"password\":\"$PW\"}"

echo "=== 7. AUTH-03 refresh reuse ==="
EMAIL3="reuse.gate@example.com"
REG3=$(curl -sS -X POST "$BASE/auth/register" -H 'Content-Type: application/json' \
  -d "{\"email\":\"$EMAIL3\",\"password\":\"$PW\"}")
RT1=$(python3 -c "import json,sys; print(json.load(sys.stdin)['refresh_token'])" <<<"$REG3")
ROT=$(curl -sS -X POST "$BASE/auth/refresh" -H 'Content-Type: application/json' \
  -d "{\"refresh_token\":\"$RT1\"}")
RT2b=$(python3 -c "import json,sys; print(json.load(sys.stdin)['refresh_token'])" <<<"$ROT")
echo -n "replay RT1: "
curl -sS -w "\nHTTP %{http_code}\n" -X POST "$BASE/auth/refresh" -H 'Content-Type: application/json' \
  -d "{\"refresh_token\":\"$RT1\"}"
echo -n "RT2 after reuse: "
curl -sS -w "\nHTTP %{http_code}\n" -X POST "$BASE/auth/refresh" -H 'Content-Type: application/json' \
  -d "{\"refresh_token\":\"$RT2b\"}"

echo "=== GATE SCRIPT COMPLETE (also run pytest tests/test_auth.py for AUTH-04 timing) ==="
