---
title: Kamal and Thruster Production Deploy — Design
tags:
  - design
  - kamal-thruster-deploy
  - kamal
  - thruster
  - production
  - docker
created: 2026-09-29
---

# Kamal + Thruster Production Deploy — Design

*Created: 2026-09-29*

**Goal:** Make this Rails app deployable with Kamal behind Thruster, verified
entirely against **local Docker execution** — build the production image, run it
locally, smoke-test it. No server is provisioned and nothing is deployed
remotely. The existing `docker compose` development workflow
(`bin/dev-docker`) is untouched.

**Scope decisions (confirmed):**
- Sidecar runs as a **Kamal accessory** in the same `deploy.yml` — one
  `kamal deploy` brings up Rails + sidecar.
- Verification is **local Docker only** (build'n'run + compose sidecar).
- The mounted-folder watch root stays a **dev-only** feature (`docker-compose.yml`
  sets `PICS_MOUNT_SOURCE` / `PICS_WATCH_ROOT`). Production ingests via uploads
  and the Apple Photos bridge.

**Out of scope (follow-on):** README rework (separate task after this),
actual server provisioning/`kamal setup`, a dedicated job server role,
CLI, conformance harness.

---

## Architecture Overview

Production is one Kamal app, `photo_searchable_library_rails`, with a Rails web
container and a separately built/managed Kamal accessory:

```
        Browser / HTTPS (proxy)
                 │
                 ▼
  ┌────────────────────────────────────────────┐
  │ web  (Thruster :80 → Puma :3000)           │
  │  Rails 8.1, Solid Queue IN-PUMA            │
  │  SQLite: storage/production{,_queue,       │
  │          _cache,_cable}.sqlite3            │
  │  library/ (imports, apple-photos, .crops)  │
  └───────────────┬────────────────────────────┘
                  │ PICS_WORKER_URL=http://sidecar:9090 (Kamal net)
                  ▼
  ┌────────────────────────────────────────────┐
  │ sidecar (accessory)  FastAPI :9090         │
  │  CLIP + InsightFace models in /models      │
  └────────────────────────────────────────────┘
```

Persistent named volumes (survive deploys):
- `photo_searchable_library_rails_storage:/rails/storage` — all four SQLite DBs
- `photo_searchable_library_rails_library:/rails/library` — imported originals,
  uploads, apple-photos, `.crops`
- `photo_searchable_library_rails_models:/models` — HF weights (sidecar accessory)

## Components

### 1. `Dockerfile` (production image — keep stock)
Already correct for this app: Ruby 3.3-slim, `exiftool ffmpeg libheif1 libvips
sqlite3`, jemalloc + `LD_PRELOAD`, multi-stage build with bootsnap + asset
precompile, non-root `rails` user, `docker-entrypoint` (runs `db:prepare
db:seed` only when booting `rails server`), `CMD ./bin/thrust ./bin/rails
server`, `EXPOSE 80`.

Only changes if local verification surfaces a missing native dependency
(e.g. `libsqlite3-dev` in the build stage for the `sqlite-vec` native ext).

### 2. `config/deploy.yml`
Flesh out the stock scaffold:

- `service` / `image`: keep `photo_searchable_library_rails`.
- `builder.arch`: keep `amd64` — required by the `sqlite-vec` platform tag.
- `servers.web`: keep the placeholder host (unprovisioned). Leave the `job`
  role commented for the future multi-server split.
- `env.secret`: `RAILS_MASTER_KEY` (already in `.kamal/secrets`).
- `env.clear`:
  - `SOLID_QUEUE_IN_PUMA: true` (single-container worker for this phase)
  - `PICS_WORKER_URL: http://sidecar:9090`
  - `PICS_LIBRARY: /rails/library`
  - `PICS_SIDECAR_MODE: real`
  - `PICS_MODEL`, `PICS_MODEL_VERSION`, `PICS_FACE_MODEL` (passthrough)
- `volumes`: add
  `"photo_searchable_library_rails_library:/rails/library"` alongside the
  existing storage volume.
- `proxy.healthcheck.path`: `/up` — the stock Rails path is already wired and
  Kamal's proxy polls it during deploy.
- `asset_path: /rails/public/assets` (already set).
- `accessories.sidecar`:
  - `image`: `photo_searchable_library_rails_sidecar`, a prebuilt amd64 image
    created from `sidecar/Dockerfile` and published to the configured registry.
    Kamal 2.12 accessories reference images; they do not accept the app
    `builder` configuration and are managed separately from `kamal deploy`.
  - `host: <same placeholder>` with `port: "9090:9090"`.
  - `env`: `HF_HOME=/models/huggingface`, `PICS_SIDECAR_MODE=real`,
    `PICS_MODEL`, `PICS_MODEL_VERSION`, `PICS_FACE_MODEL`.
- `volumes`: `photo_searchable_library_rails_models:/models`.
  - No accessory `healthcheck` key: Kamal 2.12 does not support it in the
    accessory schema. Verify readiness through `/v1/status` during local checks
    and accessory operations.

### 3. `.kamal/secrets`
Uses the externally supplied `RAILS_MASTER_KEY`. No other secrets are required
(`PICS_*` are clear env). Document that the key must come from a password
manager or deployment secret store and must never be committed.

### 4. `.github/workflows/ci.yml`
Add a `docker-build` job (parallel to `test`) that builds both the Rails
production image and the sidecar image for amd64. It pushes nothing and fails the
PR if either image stops building.

### 5. Local verification harness (`script/` + README section, no deploy)
A repeatable recipe (not part of the app runtime):

1. `docker build --platform linux/amd64 -t photo_searchable_library_rails .`
2. Start the dev sidecar: `docker compose up -d sidecar` (already publishes
   :9090 on the host).
3. Run the production image bound to the sidecar:
   ```sh
   docker run --rm -p 80:80 \
      -e RAILS_MASTER_KEY="$RAILS_MASTER_KEY" \
     -e PICS_WORKER_URL=http://host.docker.internal:9090 \
     -v <vol-storage>:/rails/storage \
     -v <vol-library>:/rails/library \
     photo_searchable_library_rails
   ```
4. Smoke test (acceptance gate, below).

`host.docker.internal` avoids running a second sidecar container during the
local check; the `sidecar` hostname only exists on the Kamal network.

## Key Decisions

| Decision | Choice | Why |
|---|---|---|
| Thruster | Stock Rails 8 `./bin/thrust` entrypoint | HTTP/1.1+HTTP/2, caching/compression, X-Sendfile, zero custom config |
| Sidecar | Kamal accessory, same app | One deploy; matches compose topology; accessory hostname `sidecar` on the Kamal network |
| Solid Queue | In-Puma for this phase | Single container keeps local verification simple; job role documented as the future split |
| Mounted folder | Dev-only | Production ingests via uploads + Apple Photos bridge; avoids a host-volume dependency in deploy |
| Architectures | `amd64` build | `sqlite-vec` publishes amd64 platform tags (already the dev-compose constraint) |
| DBs | All four SQLite files in `storage/` | `database.yml` production block already wires primary/cache/queue/cable with correct `migrations_paths` |
| Image | Keep stock `Dockerfile` | Already correct; minimal diff |

## Data Flow (release + runtime)

`docker build` → Rails image pushed to registry (placeholder `localhost:5555`) →
`kamal deploy` boots web → web `docker-entrypoint` runs `db:prepare db:seed`
(idempotent) → Thruster :80 → Puma → Rails. Separately, the sidecar image is
built/pushed and booted or updated with `bin/kamal accessory boot sidecar` or
`bin/kamal accessory reboot sidecar`. The accessory loads CLIP/InsightFace
weights from `models` volume → web calls
`http://sidecar:9090` for embeddings/faces/geocode → Solid Queue (in-Puma)
executes imports/clustering from the `queue` DB → Turbo Streams broadcast via
`solid_cable_messages` in the `cable` DB.

## Error Handling

- `db:prepare` failure on boot aborts startup loudly (entrypoint exit) — no
  silent half-migrated catalog.
- Sidecar model download/load failure → `/v1/status` 503 → admin
  `models_ready: false`; embed calls fail as existing `SidecarError` job errors
  (already handled by `ImportJob`). Deploy still boots.
- Missing `storage/` or `library/` volume = data loss; backups documented in the
  README rework.
- Thruster on :80 serves assets; 404/500 paths unchanged from Rails.

## Testing Approach

- No app-code changes are expected, so the existing suite (84 tests) stays the
  unit gate. `bin/rubocop`/`bin/brakeman` unchanged.
- **Add a CI job** that `docker build`s the production image on PRs and on
  pushes to `main`, to catch Dockerfile/native-dependency regressions (cheap,
  no push to any registry). Runs alongside the existing `test` job.
- **Acceptance gate (local Docker):**
  1. `docker build -t photo_searchable_library_rails .` succeeds.
  2. Container boots; `GET /up` → 200 `{"status":"ok"}` through Thruster.
  3. Boot runs `db:prepare`: `production.sqlite3`, `production_queue.sqlite3`,
     `production_cache.sqlite3`, `production_cable.sqlite3` all exist in
     `storage/`.
  4. With the compose sidecar reachable: `GET /catalog/overview` (JSON) returns
     sources; `POST /assets/upload` (tiny.jpg) enqueues; in-Puma worker drains
     it; asset appears searchable; `GET /assets/:id/thumbnail` returns JPEG.
  5. `bin/kamal config` parses the final `deploy.yml` (no server needed).

## Risks to Prove in the Gate

- **`db/cache_migrate` directory is absent** (only `db/cache_schema.rb` exists)
  while production `database.yml` points cache at `db/cache_migrate`. Confirm
  `db:prepare` still prepares the cache DB, or create
  `db/cache_migrate/001_create_solid_cache_tables.rb` (mirrors the existing
  `db/queue_migrate` / `db/cable_migrate` pattern).
- `sqlite-vec` native extension compiles in the build stage on `linux/amd64`.
- HEIC thumbnails decode in the prod image (`libheif1` present).
- Thruster serves JSON + Turbo Stream responses over HTTP/1.1 on :80.
