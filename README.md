# AI Second Brain

Personal RAG knowledge assistant — dump notes, PDFs, voice memos; chat across them with citations.

**Pack:** v1.1.1 · **Stack:** Flutter + FastAPI + SQLite(WAL) + Chroma + Gemini + Groq Whisper  
**Rule:** phases in order. Phase 0 (this tree) is auth + scaffold only.

## Repo layout

```
second-brain/
├── AGENTS.md              # 01 — locked stack & rules (wins disagreements)
├── 02-openapi.yaml        # contract source of truth
├── backend/               # FastAPI
├── frontend/              # Flutter (Android / iOS / web)
├── fixtures/              # golden QA, seed docs, eval runner
└── docker-compose.yml     # api + 3 volumes
```

## Phase 0 — run locally (VSCode)

### Backend

```bash
cd backend
python3.12 -m venv .venv && source .venv/bin/activate   # 3.13 works if 3.12 isn't installed
pip install -e ".[dev]"
cp ../.env.example ../.env   # then set JWT_SECRET (≥32 chars). Dummy GEMINI/GROQ ok until Phase 1.
mkdir -p data/sqlite data/chroma data/backups
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Health: `GET http://localhost:8000/healthz` and `GET http://localhost:8000/v1/readyz`.

### Flutter (your machine — this pack workspace has no Flutter SDK)

```bash
cd frontend
flutter create . --project-name second_brain --org app.secondbrain --platforms=android,ios,web
# If create asks to overwrite pubspec/lib, say no — keep the files in this repo.
flutter pub get
flutter analyze
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000/v1
# Android emulator: --dart-define=API_BASE_URL=http://10.0.2.2:8000/v1
```

Application id / bundle: `app.secondbrain.frontend` (set in `android/` / `ios/` after `flutter create`, or via `--org app.secondbrain` + rename). Display name: **Second Brain**.

### Phase 0 gate

```bash
cd backend && pytest -q tests/test_auth.py tests/test_health.py
./scripts/phase0_gate.sh   # curl cycle — paste output before Phase 1
```

## Locked decisions (do not silently change)

- Contract: `02-openapi.yaml`. Additive only.
- Auth: self-issued JWT 15min + opaque rotating refresh (sha256, 30d, reuse revokes chain).
- Passwords: Argon2id (`time_cost=2`, `memory=19MiB`, `parallelism=1`), 10..72 chars.
- No token, no data. Cross-user = 404 never 403.
- Models pinned: `text-embedding-004@PINNED`, `gemini-2.5-flash@PINNED`.
