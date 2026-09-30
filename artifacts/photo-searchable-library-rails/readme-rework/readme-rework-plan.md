---
title: Holistic README Rework — Implementation Plan
tags:
  - plan
  - readme-rework
  - documentation
created: 2026-09-30
---

# Holistic README Rework — Implementation Plan

*Created: 2026-09-30*

**Goal:** Replace `README.md` with a single, onboarding-first document that
accurately describes the app and stack, documents every local run path, treats
the Apple Photos bridge as first-class, and uses `<details>` blocks for
technical deep dives.

**Architecture:** One `README.md`, ordered as a reader journey, all existing
sections relocated (none dropped). Content is grounded in verified repo facts
(routes, env vars, `bin/` scripts, deploy posture), not invented.

**Tech Stack:** GitHub-flavored Markdown, `<details>/<summary>` collapsibles,
TOC anchors.

**Source:** `readme-rework-design.md` (this dir).

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `README.md` | Replace | The complete reworked document |
| `artifacts/.../readme-rework/readme-rework-plan.md` | Create | This plan |

---

## Tasks

### Task 1: Verify the source-of-truth facts the README will cite

Every route, env var, script, and command in the new README must exist. Verify
them before writing, so the document is grounded.

**Files:**
- None (verification)

- [ ] **Step 1: Verify routes**

Run:
```bash
mise exec -- bin/rails routes | wc -l
mise exec -- bin/rails routes | grep -E "apple-photos|persons|/up|/search|/places|/catalog/overview|/assets/upload|/jobs|/settings|/admin" | head -40
```
Expected: route lines print, including `apple-photos` routes, `/up`, `/search`,
`/places`, `/catalog/overview`, `/assets/upload`, `/jobs`, `/settings`, and
`/admin`. Note any that are missing and adjust the README table accordingly.

- [ ] **Step 2: Verify env vars**

Run:
```bash
grep -E "PICS_|MEDIA_SUFFIXES" config/initializers/pics.rb
grep -E "PICS_" config/deploy.yml docker-compose.yml bin/dev-photos-bridge
```
Expected: the env vars `PICS_LIBRARY`, `PICS_WATCH_ROOT`, `PICS_WORKER_URL`,
`PICS_MODEL`, `PICS_MODEL_VERSION`, `PICS_MAX_UPLOAD_BYTES`,
`PICS_SOURCE_SYNC_LEASE_SECONDS`, `PICS_BRIDGE_LEASE_SECONDS`,
`PICS_INVENTORY_CACHE_TTL`, `MEDIA_SUFFIXES` in the initializer, plus
`PICS_MOUNT_SOURCE` and `PICS_BRIDGE_API_URL` in compose/bridge scripts.

- [ ] **Step 3: Verify bin scripts**

Run:
```bash
ls bin/
```
Expected: `brakeman bundler-audit ci dev dev-docker dev-photos-bridge
dev-reset-docker docker-entrypoint importmap jobs kamal rails rake rubocop
setup thrust`.

- [ ] **Step 4: Verify the bridge and deploy commands**

Run:
```bash
bash -n bin/dev-photos-bridge
bash -n script/prod-smoke.sh
bin/kamal config > /dev/null 2>&1 && echo "kamal config ok"
```
Expected: no syntax errors, `kamal config ok` printed.

- [ ] **Step 5: Commit**

```bash
git add README.md 2>/dev/null || true
git add artifacts/photo-searchable-library-rails/readme-rework/readme-rework-design.md 2>/dev/null || true
git commit -m "chore: verify readme rework source facts" 2>/dev/null || true
```
If there is nothing to commit (clean tree), skip the commit and proceed.

---

### Task 2: Write the complete new README.md

This is the whole deliverable in one atomic write. Preserve the markdown
exactly as shown.

**Files:**
- Replace: `README.md`

- [ ] **Step 1: Write the file**

```markdown
# Photo Searchable Library (Rails)

A private, self-hosted, searchable photo library. Import photos from Apple
Photos or a mounted folder, then find them by **what happened, who was there,
where, or when** — without uploading anything to a cloud service.

This is an independent Rails reimplementation of
[photo-searchable-library](https://github.com/scottsymm/photo-searchable-library)
(originally FastAPI + React). The Rails app has its own SQLite database and
library directory; it does not share a catalog with the reference project.

Rails 8.1 · Hotwire (Turbo + Stimulus) · SQLite + sqlite-vec · Solid Queue /
Cable · Python ML sidecar (CLIP + InsightFace) · Swift Apple Photos bridge ·
Thruster + Kamal

---

## Table of Contents

- [What's implemented](#whats-implemented)
- [Architecture](#architecture)
- [Quick start](#quick-start)
- [Getting photos in](#getting-photos-in)
- [Apple Photos bridge](#apple-photos-bridge)
- [Configuration](#configuration)
- [Routes](#routes)
- [Other ways to run](#other-ways-to-run)
- [Production image & Kamal](#production-image--kamal)
- [Technical deep dives](#technical-deep-dives)
- [Quality gates](#quality-gates)
- [Roadmap & tradeoffs](#roadmap--tradeoffs)
- [Data & backups](#data--backups)
- [Project layout](#project-layout)
- [License](#license)

---

## What's implemented

The project is complete through four phases:

| Phase | Delivered |
|---|---|
| 1 — Foundation, ingest, search | CLIP embeddings, semantic + structured search, catalog overview, uploads, mounted-folder scan, thumbnail pipeline |
| 2 — Faces & people | InsightFace face detection, face embeddings, DBSCAN clustering, people review (confirm/reject/restore/merge/split) |
| 3 — UI parity | Five-page Hotwire UI: Search, Photos, People, Places, Settings, with live Turbo Stream updates |
| 4 — Apple Photos bridge | `/sources/apple-photos/*` HTTP contract, sync state machine, lease recovery, catalog inventory |

**Search** supports free text (CLIP semantic) plus structured filters:
`who:` (people), `place:`, `before:`, `after:`, `tag:`.

**Not yet built:** CLI, conformance harness, and a local Kamal deploy loop.
See [Roadmap & tradeoffs](#roadmap--tradeoffs).

---

## Architecture

```text
Browser / HTTP clients
          │
          ▼
Rails 8.1 application (:3000)
  ERB + Turbo/Stimulus
  Active Record + SQLite/sqlite-vec
  Solid Queue jobs + Solid Cable streams
          │
          ▼
Python ML sidecar (:9090)
  CLIP text/image embeddings
  InsightFace face detection/embeddings
  Reverse geocoding
          ▲
          │
Swift Apple Photos bridge (macOS host process)
  Reads the macOS Photos library over HTTP
```

Three processes, three ownerships:

- **Rails** owns the catalog: database, thumbnails, library files, jobs,
  people, and the UI.
- **The sidecar is stateless**: it owns model weights and exposes inference
  endpoints only. It has no database and no application logic.
- **The Swift bridge owns macOS Photos access**: it reads the local Photos
  library and pushes assets into Rails over HTTP. Rails never touches Photos
  internals.

<details>
<summary><strong>Why a Python sidecar at all?</strong></summary>

CLIP and InsightFace are PyTorch models. The pragmatic move is to keep them in
Python behind a small FastAPI service rather than port them to Ruby. Rails
calls the sidecar for embeddings, face vectors, and geocoding; the sidecar
never initiates work. This keeps the ML stack replaceable without touching the
application.

</details>

---

## Quick start

The default path is the containerized dev stack.

### Prerequisites

- Docker with Compose v2
- A directory of photos to scan (defaults to `~/Pictures`, mounted read-only)

### Run it

```sh
bin/dev-docker
```

This builds the images, prepares the development database, runs migrations,
then starts the web app (`:3000`), the Solid Queue worker, and the sidecar
(`:9090`, stub mode) together. Open <http://localhost:3000>.

The dev stack runs the sidecar in **stub mode** (deterministic vectors, no
model download) so the app boots fast. To use real CLIP embeddings, set
`PICS_SIDECAR_MODE=real` in `docker-compose.yml` and restart the sidecar; the
first start downloads the models into the persistent `models` volume.

### Useful commands

```sh
bin/dev-docker            # build + migrate + run the whole stack
bin/dev-reset-docker      # wipe local dev SQLite DBs (keeps photos/models)
bin/dev-reset-docker --models   # also delete downloaded model weights
docker compose down       # stop the stack
```

<details>
<summary><strong>Raw docker compose workflow</strong></summary>

`bin/dev-docker` is a thin wrapper around:

```sh
docker compose build
docker compose run --rm --no-deps rails bin/rails db:create db:migrate db:seed
rm -f tmp/pids/server.pid
docker compose up
```

The stack is three services (see `docker-compose.yml`):

| Service | Command | Purpose |
|---|---|---|
| `rails` | `bin/rails server` | Web app on `:3000` |
| `worker` | `bin/jobs start` | Solid Queue worker |
| `sidecar` | uvicorn | ML inference on `:9090` (stub in dev) |

For live Python sidecar development, `docker-compose.dev.yml` bind-mounts
`./sidecar` and enables uvicorn `--reload`. Restart the `worker` service after
changing Ruby job code: `docker compose restart worker`.

</details>

---

## Getting photos in

There are three ways to add photos:

| Path | Who it's for | How |
|---|---|---|
| **Apple Photos bridge** | macOS users (recommended) | Sync from your existing Photos library; see below |
| **Mounted-folder scan** | Any OS | Mount a photo directory, then "Scan library now" on Settings |
| **Direct upload** | Any OS | Upload an image straight into the library |

The Settings page (`/settings`) drives watch enable/disable and one-off scans.

---

## Apple Photos bridge

The bridge is a **first-class citizen** — on macOS it is the primary way to get
photos into the library, since it reads the Photos library that macOS already
manages.

It is a small native Swift CLI in `apps/photos-bridge`. It talks only HTTP; it
has no database and no knowledge of Rails internals.

### Run it

```sh
cd apps/photos-bridge
swift build
../../bin/dev-photos-bridge
```

`bin/dev-photos-bridge` points at <http://localhost:3000> by default:

```sh
PICS_BRIDGE_API_URL=http://localhost:3000 bin/dev-photos-bridge
```

The first run asks macOS for Photos access. Keep the bridge running while you
use the Apple Photos sync controls on the Photos page (`/catalog/overview`):
**Import latest 25** or **Import entire library**.

### How the sync works

The bridge reports a heartbeat, requests a sync batch, uploads assets, and
marks the batch complete. Rails owns the `source_syncs` state machine
(`queued → running → done/partial/error`) and recovers stale runs via a lease.
Original files land in `library/apple-photos/` and are **never deleted** on
import failure — they are the only copy.

<details>
<summary><strong>Bridge protocol (for the curious)</strong></summary>

The Rails contract lives at `/sources/apple-photos/*`:

- `POST /sources/apple-photos/sync` — request a batch (`limit`, `full`)
- `POST /sources/apple-photos/sync/claim` — take ownership of the next queued sync
- `POST /sources/apple-photos/sync/:id/complete` — report `imported_count` / `failed_count` / `error`
- `POST /sources/apple-photos/bridge/heartbeat` — report authorization state + asset count
- `POST /sources/apple-photos/assets/known` — dedupe: which `source_asset_id`s already exist
- `POST /sources/apple-photos/assets` — multipart upload; returns `queued` / `duplicate` / retried
- `GET /sources/apple-photos/status` — source + bridge state

Key rules: `source_asset_id` contains `/` and is a **form field**, never a
route segment; `complete` maps `error && imported_count > 0 → partial`,
`error alone → error`, else `done`; `asset_count == 0` means
`inventory_pending`, not empty.

</details>

---

## Configuration

Environment variables read by the Rails app (`config/initializers/pics.rb`):

| Variable | Default | Purpose |
|---|---|---|
| `PICS_LIBRARY` | `./library` | Where imported originals, crops, and uploads live |
| `PICS_WATCH_ROOT` | `/media/photos` | Directory scanned by the admin scan action |
| `PICS_WORKER_URL` | `http://localhost:9090` | URL of the Python ML sidecar |
| `PICS_MODEL` | `openai/clip-vit-base-patch32` | Hugging Face CLIP model |
| `PICS_MODEL_VERSION` | `clip-vit-base-patch32-v1` | Version recorded with real-sidecar embeddings |
| `PICS_MAX_UPLOAD_BYTES` | `104857600` | Maximum upload size, in bytes |
| `PICS_SOURCE_SYNC_LEASE_SECONDS` | `60` | Stale Apple Photos sync recovery window |
| `PICS_BRIDGE_LEASE_SECONDS` | `60` | Bridge heartbeat lease before it goes `offline` |
| `PICS_INVENTORY_CACHE_TTL` | `60` | Watch-root inventory cache TTL (seconds) |

Docker-related:

| Variable | Where | Purpose |
|---|---|---|
| `PICS_MOUNT_SOURCE` | `docker-compose.yml` | Host directory mounted read-only at `/media/photos` (default `~/Pictures`) |
| `PICS_BRIDGE_API_URL` | `bin/dev-photos-bridge` | Bridge target URL (default `http://localhost:3000`) |

`PICS_MODEL` / `PICS_MODEL_VERSION` / `PICS_FACE_MODEL` are passed to the
sidecar process and take effect in `PICS_SIDECAR_MODE=real`; stub mode reports
`stub`/`stub-v1` and never downloads models.

---

## Routes

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/` · `/health` | JSON health for API clients; HTML dashboard otherwise |
| `GET` | `/up` | Rails healthcheck (used by Kamal/load balancers) |
| `GET` | `/search` | Semantic search with `q`, `who`, `place`, `before`, `after`, `tag` |
| `GET` | `/places` | Aggregated city/country index |
| `GET` | `/catalog/overview` | Catalog funnel, context, sources, and live sync state |
| `GET` | `/assets/upload` · `POST /assets/upload` | Upload form / upload an asset |
| `GET` | `/assets/:id/thumbnail` | JPEG thumbnail for an asset |
| `GET` | `/jobs` · `/jobs/:id` | List / show import and scan jobs |
| `GET` | `/admin/status` · `/settings` | Settings page (watch, scan, disk, jobs) |
| `GET` · `PATCH` | `/admin/settings` | Read / update settings |
| `POST` | `/admin/scan` | Queue a scan of the watch root |
| `GET` | `/admin/library` | Inventory walk + catalog counts |
| `GET` | `/persons` · `/persons/search` | People index / picker search |
| `POST` | `/persons/cluster` | Run face clustering |
| `PATCH` | `/persons/:id` | Rename a person |
| `POST` | `/persons/:id/aliases` · `DELETE .../:id` | Manage aliases |
| `POST` | `/persons/:id/merge/:remove_id` | Merge two people |
| `POST` | `/persons/:id/split` | Split faces into a new person |
| `POST` | `/persons/suggestions/:id/confirm` · `/reject` · `/restore` | Review cluster suggestions |
| `GET` | `/persons/faces/:face_id/crop` | Serve a face crop (containment-checked) |
| `*` | `/sources/apple-photos/*` | Apple Photos bridge contract (see above) |

HTML by default; JSON when requested with `Accept: application/json`.

---

## Other ways to run

<details>
<summary><strong>Host-native Rails + sidecar in Docker</strong></summary>

For editing Rails code with a fast local loop:

```sh
docker compose up sidecar        # terminal 1: sidecar on :9090 (stub)
mise install
bundle install
bin/rails db:prepare
bin/dev                           # terminal 2: Rails on :3000
bin/jobs start                    # terminal 3: Solid Queue worker
```

`bin/dev` starts Rails only. It does not start the sidecar or Solid Queue —
keep them running in their own terminals. The Compose sidecar publishes `:9090`
to the host, so host Rails reaches it at `http://localhost:9090` (the
`PICS_WORKER_URL` default).

</details>

<details>
<summary><strong>Raw docker compose</strong></summary>

See [Quick start](#quick-start) — `bin/dev-docker` is a thin wrapper around
`docker compose build && docker compose run ... db:create db:migrate db:seed &&
docker compose up`. Run those steps yourself if you prefer not to use the
wrapper.

</details>

---

## Production image & Kamal

The production posture is configured but **not deployed anywhere** — the
`config/deploy.yml` server (`192.168.0.1`) and registry (`localhost:5555`) are
placeholders you fill in when you have real infrastructure.

The stock Rails 8 production `Dockerfile` is kept: multi-stage build,
bootsnap, asset precompile, non-root `rails` user, jemalloc, Thruster serving
HTTP on `:80` in front of Puma, and an entrypoint that runs
`db:prepare db:seed` on boot.

### Verify the production image locally

```sh
docker build --platform linux/amd64 -t photo_searchable_library_rails .
script/prod-smoke.sh    # boots the image against the stub sidecar, uploads a photo,
                        # waits for the import job, checks the thumbnail
bin/kamal config        # prints the resolved Kamal configuration
```

### The ML sidecar image (separate lifecycle)

Kamal 2.12 accessories reference prebuilt images and are managed separately
from `kamal deploy`:

```sh
docker build --platform linux/amd64 -f sidecar/Dockerfile \
  -t photo_searchable_library_rails_sidecar .
bin/kamal accessory boot sidecar
```

Persistent volumes (`config/deploy.yml`):

| Volume | Container path | Holds |
|---|---|---|
| `photo_searchable_library_rails_storage` | `/rails/storage` | All four SQLite DBs (primary, queue, cache, cable) |
| `photo_searchable_library_rails_library` | `/rails/library` | Imported originals, uploads, `.crops` |
| `photo_searchable_library_rails_models` | `/models` | Sidecar model weights |

The Kamal proxy healthchecks `/up`, and `SOLID_QUEUE_IN_PUMA=true` runs the
Solid Queue supervisor inside Puma for single-container deploys.

<details>
<summary><strong>A local Kamal deploy loop is planned but not built</strong></summary>

A genuinely runnable `bin/kamal deploy -d local` (SSH-to-localhost, throwaway
registry, full proxy loop) is a separate tracked effort. This README will
document it only once it is verified working. Until then, the local production
path is: build the image, run `script/prod-smoke.sh`, and inspect
`bin/kamal config`.

</details>

---

## Technical deep dives

<details>
<summary><strong>Rails multi-database setup</strong></summary>

SQLite, but four logical databases in `config/database.yml`:

| Environment | Databases | Purpose |
|---|---|---|
| Development | `primary`, `cable`, `queue` | App data, Solid Cable, Solid Queue |
| Production | `primary`, `cache`, `queue`, `cable` | Adds Solid Cache |

`schema_format = :sql` (`config/application.rb`) dumps `db/structure.sql` so
the `vec0_*` virtual tables survive. Each connection has its own
`migrations_paths` (`db/queue_migrate`, `db/cable_migrate`, `db/cache_migrate`).

</details>

<details>
<summary><strong>Solid Queue & Solid Cable (no Redis)</strong></summary>

Background jobs use Solid Queue, the database-backed Active Job adapter, so
there is no Redis to run. The web container runs a supervisor in-Puma
(`SOLID_QUEUE_IN_PUMA`); dev uses a separate `worker` container (`bin/jobs
start`).

Live UI updates use **server-push Turbo Streams**, not polling: domain jobs
broadcast their card to the `"jobs"` stream, `ImportJob` broadcasts the catalog
overview to `"catalog"`, `ClusterFacesJob` broadcasts the people review queue
to `"people"`. Pages subscribe with `<%= turbo_stream_from "catalog" %>`.
Solid Cable (database-backed Action Cable adapter) delivers those broadcasts
across processes — in dev and production.

</details>

<details>
<summary><strong>sqlite-vec & vector search</strong></summary>

CLIP embeddings are 512-dimensional float32 vectors, stored as little-endian
BLOBs in `content_embeds` / `face_embeds` and indexed in two sqlite-vec virtual
tables created by migration:

```sql
CREATE VIRTUAL TABLE vec0_content USING vec0(content_embed float[512]);
CREATE VIRTUAL TABLE vec0_face    USING vec0(face_embed float[512]);
```

The extension is loaded on **every** SQLite connection via an adapter prepend
(`config/initializers/sqlite_vec.rb`). Vectors are normalized by the sidecar,
so L2 ranking preserves cosine ranking. `EmbeddingStore` inserts with
`rowid = asset_id` and runs `MATCH ... AND k = ?` KNN queries.

</details>

<details>
<summary><strong>The import pipeline</strong></summary>

`app/services/asset_importer.rb` per file:

1. `ExifMetadata.extract` — exiftool: `taken_at`, GPS, mime, size
2. `ThumbnailMaker.thumbnail` — ruby-vips (images) or ffmpeg (video frames)
   → 512px JPEG stored in `files` (`stored_file.bytes`)
3. `SidecarClient.reverse_geocode` — GPS → city/country (when GPS present)
4. `SidecarClient.embed_image` — CLIP embedding
5. `EmbeddingStore.add_content` — upsert `content_embeds` + `vec0_content`
6. `Source.classify_path` — `apple-photos` / `imports` (uploads) / mounted folder

Jobs: `ScanJob` walks the watch root and enqueues one `ImportJob` per file;
progress is written to the domain `jobs` table. Uploads originals are deleted
on import failure; **Apple Photos originals never are**.

</details>

<details>
<summary><strong>Faces, clustering & people</strong></summary>

On image import, `FaceDetection` calls the sidecar
(`POST /v1/detect-faces`), persists one face row per stable detection, writes
JPEG crops under `library/.crops/` (path-containment validated before serving),
and stores 512-float face vectors in `face_embeds` + `vec0_face`.

`ClusterFacesJob` runs cosine-DBSCAN in the sidecar (`/v1/cluster-faces`) over
unassigned faces, records `clustering_runs`, and creates one reviewable
`cluster_suggestion` per non-noise cluster. Confirming a suggestion creates a
`person` + `person_face` links; reject/restore/merge/split are transactional
mutations that survive later clustering runs.

</details>

<details>
<summary><strong>Kamal & Thruster deployment</strong></summary>

- **Thruster** is the production HTTP entrypoint (`CMD ["./bin/thrust",
  "./bin/rails", "server"]`): HTTP/1.1 + HTTP/2, asset caching/compression,
  X-Sendfile, serving on `:80`.
- **Kamal** (`bin/kamal`) orchestrates Docker deploys over SSH. The app is a
  single service with a sidecar accessory; `amd64` builds match the
  `sqlite-vec` platform tags.
- The image is the stock Rails 8 production `Dockerfile` — jemalloc, non-root,
  `db:prepare db:seed` entrypoint — with `libsqlite3-dev` added to the build
  stage for the `sqlite3`/`sqlite-vec` native gems.

</details>

<details>
<summary><strong>Data ownership boundaries</strong></summary>

| Process | Owns | Never touches |
|---|---|---|
| Rails | Catalog DB, library files, thumbnails, jobs, people, UI | Model weights, Photos internals |
| Sidecar | Model weights, inference | Database, app logic, filesystem beyond its volumes |
| Swift bridge | macOS Photos access | The Rails database; it only speaks HTTP |

The sidecar and bridge are both replaceable without touching the catalog —
the contracts are HTTP (`/v1/*` and `/sources/apple-photos/*` respectively).

</details>

---

## Quality gates

Run them in the container so native deps match the app image:

```sh
docker compose run --rm rails bin/rails test        # 84 tests
docker compose run --rm rails bin/rubocop           # style
docker compose run --rm rails bin/brakeman --no-pager
docker compose run --rm rails bin/bundler-audit
```

CI (`.github/workflows/ci.yml`) runs Brakeman, bundler-audit, importmap audit,
RuboCop, the test suite, system tests, and a `docker-build` job that builds
both the production image and the sidecar image on PRs.

---

## Roadmap & tradeoffs

Done: phases 1–4 (see [What's implemented](#whats-implemented)).

Planned / not built:

- **CLI** — the reference repo has a `pics` CLI (scan, query, upload,
  strip-exif, cluster, people); not ported.
- **Conformance harness** — behavioral parity checks against the reference app.
- **Local Kamal deploy loop** — tracked separately (`kamal-local-deploy`);
  the README will document it once verified.
- **Video face extraction** — face detection currently runs on images only.
- **Watch backfill radios** — the Settings UI keeps the backfill flow minimal
  until the watcher lands.

Tradeoffs worth knowing:

- SQLite is the database — great for a single-user local library; a
  multi-user server would want PostgreSQL.
- `sqlite-vec` pins the build to `linux/amd64` (platform tags).
- The sidecar downloads models on first real-mode boot (several minutes).
- Everything is designed for **one user on their own machine**; the deploy
  config assumes a single web container with the queue in-Puma.

---

## Data & backups

- `storage/` — SQLite databases (ignored by Git)
- `library/` — imported originals, uploads, `.crops`
- Docker `models` volume — downloaded model weights

Back up the database and library directory together; they are the source of
truth. The Docker volumes and the Compose `models` volume are named and
retained by default (`docker compose down -v` only when you want to destroy
them).

---

## Project layout

```text
app/controllers/   HTTP endpoints
app/jobs/          Solid Queue jobs
app/models/        Catalog and job records
app/services/      Import, thumbnail, embedding, search, bridge logic
app/views/         Server-rendered Hotwire views
apps/photos-bridge/ Swift Apple Photos bridge (macOS)
sidecar/           Stateless Python ML service
script/            Dev/production helpers (prod-smoke.sh)
test/              Minitest unit and request tests
config/            Rails, database, routes, deploy, and application defaults
artifacts/         Discovery and implementation planning documents
```

---

## License

No license has been declared for this repository yet.
```

- [ ] **Step 2: Verify structure**

Run:
```bash
wc -l README.md
grep -c "<details>" README.md
grep -c "</details>" README.md
grep -c "^\|.*\|" README.md
```
Expected: `wc -l` prints a number (roughly 400+); `<details>` and `</details>`
counts are **equal**; the routes/env tables present.

- [ ] **Step 3: Verify the hard boundary sentence**

Run:
```bash
grep -c "not built" README.md
grep -c "kamal-local-deploy" README.md
grep -c "not deployed anywhere" README.md
```
Expected: each greps ≥ 1 match.

- [ ] **Step 4: Verify no stale claims**

Run:
```bash
grep -inE "phase 1 foundation|planned follow-on|people and face review, places" README.md || echo "no stale claims"
```
Expected: prints `no stale claims`.

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs: rewrite readme for onboarding, bridge, and deploy posture"
```

---

### Task 3: Cross-check the README against the codebase

**Files:**
- None (verification)

- [ ] **Step 1: Every command in the README exists**

Run:
```bash
for c in "bin/dev-docker" "bin/dev-reset-docker" "bin/dev-photos-bridge" "bin/jobs" "bin/dev" "bin/kamal" "script/prod-smoke.sh" "bin/brakeman" "bin/rubocop" "bin/bundler-audit" "bin/importmap"; do
  test -f "$c" && echo "OK $c" || echo "MISSING $c"
done
```
Expected: all `OK`.

- [ ] **Step 2: Every route in the README table is routed**

Run:
```bash
mise exec -- bin/rails routes > /tmp/routes.txt
for r in "/up" "/search" "/places" "/catalog/overview" "/assets/upload" "/jobs" "/settings" "/admin/library" "/persons/search" "/persons/cluster" "/sources/apple-photos/status" "/sources/apple-photos/sync"; do
  grep -q "$r" /tmp/routes.txt && echo "OK $r" || echo "MISSING $r"
done
```
Expected: all `OK`.

- [ ] **Step 3: Every env var in the README table is defined**

Run:
```bash
for v in PICS_LIBRARY PICS_WATCH_ROOT PICS_WORKER_URL PICS_MODEL PICS_MODEL_VERSION PICS_MAX_UPLOAD_BYTES PICS_SOURCE_SYNC_LEASE_SECONDS PICS_BRIDGE_LEASE_SECONDS PICS_INVENTORY_CACHE_TTL; do
  grep -q "$v" config/initializers/pics.rb && echo "OK $v" || echo "MISSING $v"
done
```
Expected: all `OK`.

- [ ] **Step 4: `<details>` tags are balanced**

Run:
```bash
open=$(grep -c "<details>" README.md); close=$(grep -c "</details>" README.md)
echo "open=$open close=$close"
test "$open" = "$close" && echo "balanced" || echo "UNBALANCED"
```
Expected: `balanced`.

- [ ] **Step 5: Commit plan state**

```bash
git add artifacts/photo-searchable-library-rails/readme-rework/readme-rework-plan.md
git commit -m "chore: record readme rework plan"
```

---

## Verification Summary

- [ ] `README.md` rewritten; all old sections relocated, none dropped
- [ ] `bin/dev-docker` is the documented default; raw compose and host-native in `<details>`
- [ ] Apple Photos bridge is a first-class section with run + sync + protocol detail
- [ ] All four run paths documented (dev-docker, compose, host-native, production image)
- [ ] Seven technical deep dives present as `<details>` blocks
- [ ] Kamal boundary sentence present: not deployed, local loop is future work
- [ ] Routes/env/bin commands cross-checked against the repo (Task 3)
- [ ] `<details>`/`</details>` balanced; no stale "Phase 1 foundation" claims
- [ ] Repo gates still green after the change (`bin/rails test`)