#!/usr/bin/env bash
# Phase 8: backup snapshot, restore-empty-only, stale heartbeat, pytest.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT/backend"
if [ -d .venv ]; then source .venv/bin/activate; fi
python -m pytest -q tests/test_backup.py tests/test_health.py
echo "phase8 unit ok"
echo
cat <<'EOF'
Live (optional):
  python ../fixtures/run_eval.py --base http://localhost:8000/v1 --suite smoke
  # restore drill: POST /v1/admin/backup/now  then empty users  then POST /v1/admin/restore
  # header: X-Restore-Token: $RESTORE_TOKEN
EOF
echo "phase8 gate done"
