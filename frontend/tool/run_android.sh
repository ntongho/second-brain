#!/usr/bin/env bash
# Phone run: GOOGLE_CLIENT_ID from .env (no `source`). LAN API, not localhost.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT/frontend"

env_get() {
  local key="$1"
  local file="$ROOT/.env"
  [[ -f "$file" ]] || return 0
  local line
  line="$(grep -E "^${key}=" "$file" | tail -n 1 || true)"
  [[ -n "$line" ]] || return 0
  line="${line#${key}=}"
  line="${line%$'\r'}"
  line="${line#\"}"
  line="${line%\"}"
  line="${line#\'}"
  line="${line%\'}"
  printf '%s' "$line"
}

DEVICE="${1:-}"
if [[ -z "$DEVICE" ]]; then
  echo "Usage: bash tool/run_android.sh DEVICE_ID"
  echo "Get DEVICE_ID from: flutter devices"
  exit 1
fi

GID="$(env_get GOOGLE_CLIENT_ID)"
if [[ -z "${API_BASE_URL:-}" ]]; then
  LAN="$(hostname -I 2>/dev/null | awk '{print $1}')"
  if [[ -n "$LAN" && "$LAN" != "127.0.0.1" ]]; then
    API="http://${LAN}:8000/v1"
  else
    API="http://172.20.10.2:8000/v1"
  fi
else
  API="$API_BASE_URL"
fi

if [[ -z "$GID" ]]; then
  echo "GOOGLE_CLIENT_ID is empty in $ROOT/.env — Google on the phone will stay disabled."
fi

echo "Device $DEVICE"
echo "API $API"

exec flutter run -d "$DEVICE" \
  --dart-define="API_BASE_URL=$API" \
  --dart-define="GOOGLE_CLIENT_ID=$GID"
