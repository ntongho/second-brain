# SecondBrain

Personal library you can ask. Paste notes, upload PDFs, record voice — answers cite **your** files, not the open web.

Local-first v1: FastAPI on your machine, Flutter on **Chrome** and **Android**. Not on the Play Store. iOS is the same codebase, not smoked yet.

```
Flutter (web / Android)
    │  HTTPS or LAN  /v1
    ▼
FastAPI  →  SQLite  +  Chroma  +  Gemini (embed + answer)  +  Groq Whisper
```

## What works

- **Auth** — email + password (Argon2id, lockout, refresh rotation). Google (GIS on web; Android needs a Web client ID as `serverClientId` plus an Android OAuth client + SHA-1). Forgot-password via Gmail Apps Script (see `SMTP-SETUP.md`).
- **Library** — notes, PDFs, voice memos. Panel slides in from the **right**.
- **Chat** — left history rail (New chat, search, Today / Older). SSE answers with **citation chips** that open the passage they came from.
- **Voice** — record on device, name the take, play it back, add to library or append **transcript only** to a note.
- **Offline** — queued asks drain when you reconnect; chat list and opened threads paint from cache; library list from cache.
- **Theme** — sun/moon in the AppBar (light / dark, same layout).
- **Admin** — hidden route for `ADMIN_EMAIL` only. Not in the app chrome.

## Stack

| Layer | Choice |
| --- | --- |
| App | Flutter 3.32+, Dart 3.8+, Riverpod, go_router, Dio |
| API | FastAPI, Pydantic v2, SQLAlchemy 2 async, Alembic |
| Store | SQLite WAL, Chroma (768-d), FTS5 hybrid retrieval |
| Models | Gemini embed + Flash (pinned in `.env`), Groq Whisper |
| Auth | JWT access + rotating refresh, `flutter_secure_storage` |

Contract: `02-openapi.yaml`. Rules dump: `AGENTS.md`. Visual language: `frontend/DESIGN.md`.

## Repository layout

```
backend/          FastAPI app, Alembic, tests
frontend/         Flutter (lib/, tool/, android_overlay/, assets/brand/)
fixtures/         eval / sample files
docker-compose.yml
02-openapi.yaml
SMTP-SETUP.md     Gmail reset codes
GO-LIVE-FREE.md   notes for a later $0 host (not done)
```

`frontend/android/` is created on your machine with `flutter create` (not always in git). Icons come from `python3 tool/render_brand.py` + `bash tool/install_android_brand.sh`.

## Quick start (laptop)

**Never commit `.env`.** Copy `.env.example` → `.env` and fill keys locally.

### API

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"
mkdir -p data/sqlite data/chroma data/backups
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Health: `http://localhost:8000/healthz`

Required in `.env`: `JWT_SECRET` (≥32 chars), `GEMINI_API_KEY`, `GROQ_API_KEY`. Optional: `ADMIN_EMAIL`, `GOOGLE_CLIENT_ID` (Web client), `GMAIL_WEBAPP_URL` + `GMAIL_WEBAPP_SECRET`.

Do **not** `source .env` in bash (values are not shell-safe).

### Chrome

```bash
cd frontend
flutter pub get
bash tool/run_chrome.sh
```

That reads `GOOGLE_CLIENT_ID` from `.env` (no `source`) and serves **http://localhost:8080**. Google Cloud Web client: Authorized JavaScript origins must include `http://localhost:8080`. Use the on-page Google button, not a popup.

### Android (USB, same Wi‑Fi as the PC)

```bash
cd frontend
flutter devices
bash tool/run_android.sh DEVICE_ID
```

`DEVICE_ID` is the id from `flutter devices` — type it as one word. The script points `API_BASE_URL` at your LAN IP (`http://x.x.x.x:8000/v1` on **one line**). The phone cannot use `localhost`.

Launcher name is **SecondBrain**. Package id is `app.secondbrain.second_brain` (leave it; Google Android OAuth is bound to that). Debug SHA-1: `bash tool/print_debug_sha.sh`.

Do not `flutter pub upgrade`. Do not delete `pubspec.lock`. Pins: `record` 5.2.1, `record_platform_interface` 1.2.0, `record_web` 1.1.5, `file_picker` 8.3.7, `flutter_secure_storage` 9.2.4.

## How to use it

1. Sign in.
2. Empty chat → **Add something** (note / PDF / voice) or **How it works**.
3. Ask. Tap a citation to see the passage.
4. Left rail: **+** new chat, search, history. Email → **Log out** (not Settings).
5. Library: folder, top-right.

## Design choices (worth reading)

- **Citations must match the answer** — highlight the span that was used, not a random chunk.
- **No QueuedInterceptor** on auth refresh — parallel refresh revoked the token chain.
- **Web Google = GIS `renderButton`**, created once (`StableGoogleButton`). `GoogleSignIn.signIn()` on web hits People API and has no idToken.
- **Offline history** is a snapshot of `listChats` plus per-thread messages you actually opened.
- **Icons** are geometric (twin-lobe mark), drawn in `tool/render_brand.py` / `BrandMark` — not model-generated art.

## Tests

```bash
cd backend && pytest
cd frontend && flutter test
```

## Not in v1

- Play Store / App Store
- Public hosting (see `GO-LIVE-FREE.md` if you want a later $0 VM + Pages)
- iOS device smoke (needs a Mac)
- Admin in the main UI

## License

Private / portfolio unless you add a license file.
