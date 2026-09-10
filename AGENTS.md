# 01 — Unified Tech Stack & Rules File (v1.1.1)

Use as: `AGENTS.md` + `.cursorrules`. **This file wins every disagreement.**

v1.1: F0 auth (JWT + Argon2id) · embedding-cache compound key · job durability · model pinning · circuit breaker + degraded mode · daily backups · smoke-10/full-40 eval split.

## 1. Locked stack (do not substitute without RFC)

Monorepo: `backend/` (FastAPI, Alembic, tests) · `frontend/` (Flutter feature-first) · `fixtures/` · `02-openapi.yaml`.

**Backend:** Python 3.12 (3.13 acceptable if wheels work) · FastAPI ≥0.115 + Uvicorn ≥0.30 · Pydantic v2 ≥2.9 `extra=forbid` · self-issued JWT HS256 + Argon2id · SQLite WAL + SQLAlchemy 2.0 async + Alembic · Chroma persistent behind `VectorStore` · FTS5 BM25 · Gemini `text-embedding-004` 768-d PINNED · Gemini 2.5 Flash PINNED · pypdfium2 · Groq Whisper large-v3 · BackgroundTasks behind `JobQueue` + APScheduler sweeper/snapshot · tenacity · structlog JSON + `/metrics`.

**Frontend:** Flutter stable ≥3.32 / Dart ≥3.8 · flutter_riverpod ≥2.5 · go_router ≥14 · dio ≥5.6 · isar_community ≥3.2 (Phase 3+) · flutter_secure_storage for tokens · connectivity_plus (Phase 7; outbox drains on reconnect + app resume). workmanager is Android/iOS-only and is not used so Flutter web still compiles · record + just_audio (Phase 5).

**Infra v1:** Compose api + sqlite volume + chroma volume + backups volume. API is stateless. Anything on disk behind an interface + env path.

## 2. Performance budgets (CI fails if breached)

| Op | Budget |
| --- | --- |
| Auth register/login/refresh | <300ms p95 |
| Ingest-text | 202 <250ms p95 |
| Ingest-file | 202 <400ms p95 |
| Ask stream first token | <1.2s p95 WiFi; degraded <600ms |
| 50-page PDF pipeline | <90s background |
| Retrieval hybrid @100k | <400ms p95 |
| Boot sweep | <5s; `/readyz` false until done |
| App cold start | <1.8s; APK <45MB; RAM <180MB |

Argon2id tuned: `time_cost=2`, `memory=19MB`, `parallelism=1`.

## 3. Global rules

1. **Contract-first:** `02-openapi.yaml` is truth. Additive = minor. Renames/removals/status changes = `/v2`.
2. **Async or die:** `async def` I/O; CPU to executor; never block loop.
3. **Enqueue, don't execute:** ingest/transcribe/backup → 202 + `job_id`.
4. **Idempotency:** `X-Idempotency-Key` on POST ingest/ask (24h). Auth is NOT idempotent (rate-limited).
5. **Tracing:** `X-Request-Id` everywhere.
6. **Error envelope only:** `{error:{code,message,details,request_id,retryable}}`. Codes: `VALIDATION|AUTH|ACCOUNT_LOCKED|NOT_FOUND|RATE_LIMITED|UPSTREAM_429|UPSTREAM_DEGRADED|PROCESSING|CONFLICT|INTERNAL`. Never leak tracebacks/keys/hashes.
7. **Pagination:** cursor-based, `limit≤100`; `{data, next_cursor}`.
8. **No secrets in repo.** Boot fail-fast if `GEMINI_API_KEY` / `GROQ_API_KEY` / `JWT_SECRET` missing. `JWT_SECRET` ≥32 random bytes. Rotate via `JWT_SECRETS=[new,old]`.
9. **Tests per PR.** Auth/time tests use freezegun. Phase-gate claims require pasted command output.
10. **Structured logging:** JSON with `request_id,user_id,route,latency_ms`. Auth failures log `email_hash` never email.
11. **Agent discipline:** if a decision isn't in this pack, STOP and flag it. Do not silently deviate from OpenAPI or DDL.

## 4. RAG + platform (later phases — do not implement early)

Chunk 800/100 · cache key `(sha256(text), model)` + dim assert · hybrid RRF k=60 · prompt isolation · citations required · last-6 memory · model pinning · job heartbeat/sweep + wipe-before-reprocess · circuit breaker → keyword-only degraded · eval smoke-10 / full-40 · daily backups · restore-admin only when users table empty.

## 5. Auth rules (F0 — Phase 0)

- Email+password only (OAuth/passkeys = v2).
- `POST /auth/register|login|refresh|logout`, `GET /auth/me`.
- Passwords: Argon2id, min 10, max 72; never log/return hash.
- Access JWT 15min (HS256, `sub=user_id`, `jti`); refresh = opaque 32B, stored as sha256, 30d sliding, single-use rotation.
- Reuse of a rotated refresh token revokes the whole chain → 401 + `details.reused:true`.
- 5 bad logins → `ACCOUNT_LOCKED` 15min (`locked_until`); auth IP-limited 10/min → 429.
- Login: dummy Argon2 verify on unknown emails; identical 401 copy for bad-email vs bad-password.
- Every data query includes `user_id`; cross-user = **404 never 403**.
- Flutter: Dio single-flight refresh on 401 then one retry; failure → wipe secure storage → `/login`. `go_router.redirect` guards all routes.

## 6. Flutter rules

Feature-first (`auth,chat,library,ingestion,viewer,settings`) + `core/{network,storage,router,theme}` + `shared/widgets`. No cross-feature imports except via core/shared. AsyncNotifier per feature. Tokens ONLY in secure storage.

## 7. FastAPI rules

Thin routes → services. Routes never import vendors. WAL + `busy_timeout=10s`. Alembic per change (`002_auth`, `003_jobs_durability`, `004_cache_key`, `005_backups`).

## 8. Security (non-optional)

JWT rotation + reuse detection · lockout + IP limits · per-user isolation tested · secrets via env.

## 9. DO / DON'T

DO stream/cache/batch/paginate/trace/pin models/sweep jobs/snapshot daily/gate on full-40.  
DON'T embed on-device, put vectors in Isar, block routes on vendors, store tokens outside secure storage, return full docs in `/ask`, ship without restore drill, gate ship on n=10.
