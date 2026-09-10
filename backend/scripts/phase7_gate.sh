#!/usr/bin/env bash
# Phase 7: offline cache + outbox (Flutter unit tests). Manual: Chrome offline.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT/frontend"
flutter test test/local_cache_test.dart
echo "phase7 unit ok"
echo
cat <<'EOF'
Manual (web preview):
  1. Open library while online (caches titles + any opened docs).
  2. Chrome DevTools → Network → Offline. Red banner:
     "Offline — library readable, AI paused."
  3. Library still lists cached docs. Ask a question — composer stays enabled,
     bubble says queued. Same idempotency key if you send twice.
  4. Go online — indigo "Syncing N queued question(s)…" then the answer streams.
  5. Logout wipes threads, messages, documents, and outbox.
EOF
echo "phase7 gate done"
