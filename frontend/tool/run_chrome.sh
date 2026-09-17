#!/usr/bin/env bash
# Read GOOGLE_CLIENT_ID from .env without `source` (values are not shell-safe).
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

GID="$(env_get GOOGLE_CLIENT_ID)"
API="${API_BASE_URL:-http://localhost:8000/v1}"

if [[ -z "$GID" ]]; then
  echo "GOOGLE_CLIENT_ID is empty in $ROOT/.env — Google button will stay disabled."
fi

exec flutter run -d chrome --web-port=8080 \
  --dart-define="API_BASE_URL=$API" \
  --dart-define="GOOGLE_CLIENT_ID=$GID"
