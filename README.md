# Photo Searchable Library (Rails)

A private, self-hosted, searchable photo library. Import photos from Apple
Photos or a mounted folder, then find them by what happened, who was there,
where, or when, without uploading anything to a cloud service.

This is an independent Rails reimplementation of
[photo-searchable-library](https://github.com/scottsymm/photo-searchable-library).
It has its own SQLite database and library directory.

Rails 8.1 · Hotwire · SQLite/sqlite-vec · Solid Queue/Cable · Python ML sidecar ·
Swift Apple Photos bridge · Thruster + Kamal

## Table of Contents

- [What's implemented](#whats-implemented)
- [Architecture](#architecture)
- [Quick start](#quick-start)
- [Getting photos in](#getting-photos-in)
- [Apple Photos bridge](#apple-photos-bridge)
- [Configuration](#configuration)
- [Routes](#routes)
- [Other ways to run](#other-ways-to-run)
- [Production image and Kamal](#production-image-and-kamal)
- [Technical deep dives](#technical-deep-dives)
- [Quality gates](#quality-gates)
- [Roadmap and tradeoffs](#roadmap-and-tradeoffs)
- [Data and backups](#data-and-backups)
- [Project layout](#project-layout)
- [License](#license)

## Available now

- **Search and catalog:** CLIP semantic search, structured filters, catalog
  overview, thumbnails, uploads, mounted-folder scans, and embeddings.
- **Faces and people:** Face detection, face embeddings, clustering, and people
  review actions.
- **Application UI:** Search, Photos, People, Places, and Settings pages with
  live Turbo updates.
- **Apple Photos integration:** The bridge HTTP contract, sync state machine,
  lease recovery, deduplication, and catalog inventory.
- **Background processing:** Solid Queue jobs with live progress and catalog
  updates through Solid Cable and Turbo Streams.

Search supports free text plus `who:`, `place:`, `before:`, `after:`, and
`tag:` filters. Not yet built: the CLI, conformance harness, and local Kamal

## Architecture

```text
Browser / HTTP clients
          |
          v
Rails 8.1 application (:3000)
  ERB + Turbo/Stimulus
  Active Record + SQLite/sqlite-vec
  Solid Queue jobs + Solid Cable streams
          |
          v
Python ML sidecar (:9090)
  CLIP, InsightFace, reverse geocoding
          ^
          |
Swift Apple Photos bridge (macOS host process)
```

- Rails owns the catalog, database, library files, jobs, people, and UI.
- The sidecar owns model weights and inference only. It has no database.
- The Swift bridge owns macOS Photos access and speaks HTTP to Rails.

<details>
<summary><strong>Why a Python sidecar?</strong></summary>

CLIP and InsightFace remain in Python behind a small FastAPI service. Rails
calls the sidecar for embeddings, face vectors, and geocoding; the sidecar does
not initiate application work. This keeps the ML stack replaceable.

</details>

## Quick start

The default workflow is Docker Compose.

### Prerequisites

- Docker with Compose v2
- A photo directory, defaulting to `~/Pictures`

### Run it

```sh
bin/dev-docker
```

This builds the images, prepares the database, runs migrations, and starts the
Rails app on <http://localhost:3000>, the Solid Queue worker, and the stub ML
sidecar on `:9090`.

Useful commands:

```sh
bin/dev-docker
bin/dev-reset-docker
bin/dev-reset-docker --models
```

The development sidecar uses deterministic stub vectors. Set
`PICS_SIDECAR_MODE=real` in `docker-compose.yml` to download real model weights.

<details>
<summary><strong>Raw Docker Compose workflow</strong></summary>

`bin/dev-docker` wraps these operations:

```sh
docker compose -f docker-compose.yml -f docker-compose.dev.yml build
docker compose -f docker-compose.yml -f docker-compose.dev.yml run --rm --no-deps rails bin/rails db:create db:migrate db:seed
rm -f tmp/pids/server.pid
docker compose -f docker-compose.yml -f docker-compose.dev.yml up
```

Services are `rails` (web), `worker` (`bin/jobs start`), and `sidecar` (FastAPI).

</details>

## Getting photos in

- **Apple Photos bridge:** the primary macOS path; see below.
- **Mounted-folder scan:** mount a directory and scan it from Settings.
- **Direct upload:** upload an image from `/assets/upload`.

## Apple Photos bridge

On macOS, the bridge is the supported way to import photos from the Photos
library that macOS manages.

```sh
cd apps/photos-bridge
swift build
../../bin/dev-photos-bridge
```

The default target is `http://localhost:3000`; override it with:

```sh
PICS_BRIDGE_API_URL=http://localhost:3000 bin/dev-photos-bridge
```

The first run requests Photos permission. Keep the bridge running while using
the Apple Photos sync controls on the Photos page.

Rails owns `source_syncs` (`queued -> running -> done/partial/error`), recovers
stale runs with a lease, and stores originals under `library/apple-photos/`.
Apple Photos originals are never deleted on import failure.

<details>
<summary><strong>Apple Photos protocol</strong></summary>

The bridge uses `/sources/apple-photos/*`: sync, claim, complete, heartbeat,
known-assets, multipart asset ingest, and status. `source_asset_id` is a form
field because it can contain `/`. Completion maps an error with imports to
`partial`, an error without imports to `error`, and otherwise to `done`.
An `asset_count` of zero means `inventory_pending`, not empty.

</details>

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `PICS_LIBRARY` | `./library` | Originals, uploads, and crops |
| `PICS_WATCH_ROOT` | `/media/photos` | Mounted-folder scan root |
| `PICS_WORKER_URL` | `http://localhost:9090` | ML sidecar URL |
| `PICS_MODEL` | `openai/clip-vit-base-patch32` | CLIP model |
| `PICS_MODEL_VERSION` | `clip-vit-base-patch32-v1` | Embedding version |
| `PICS_MAX_UPLOAD_BYTES` | `104857600` | Upload limit |
| `PICS_SOURCE_SYNC_LEASE_SECONDS` | `60` | Sync lease |
| `PICS_BRIDGE_LEASE_SECONDS` | `60` | Bridge heartbeat lease |
| `PICS_INVENTORY_CACHE_TTL` | `60` | Inventory cache TTL |

Docker also uses `PICS_MOUNT_SOURCE` for the host photo directory and
`PICS_BRIDGE_API_URL` for the bridge target.

## Routes

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/`, `/health`, `/up` | Health and readiness |
| `GET` | `/search` | Semantic and structured search |
| `GET` | `/places` | Place aggregate |
| `GET` | `/catalog/overview` | Catalog funnel and sources |
| `GET`, `POST` | `/assets/upload` | Upload form and ingest |
| `GET` | `/assets/:id/thumbnail` | Thumbnail |
| `GET` | `/jobs`, `/jobs/:id` | Job status |
| `GET`, `PATCH`, `POST` | `/settings`, `/admin/*` | Operations and scanning |
| `GET`, `PATCH`, `POST` | `/persons/*` | People and clustering |
| `*` | `/sources/apple-photos/*` | Apple Photos bridge contract |

HTML is the default; request JSON with `Accept: application/json`.

## Other ways to run

<details>
<summary><strong>Host-native Rails with the sidecar in Docker</strong></summary>

```sh
mise install
bundle install
bin/rails db:prepare
bin/dev
bin/jobs start
```

`bin/dev` starts Rails only. The sidecar and Solid Queue run separately.

</details>

<details>
<summary><strong>Production image locally</strong></summary>

```sh
script/prod-smoke.sh
bin/kamal config
```

The smoke script boots the production image against the stub sidecar, uploads a
photo, waits for Solid Queue, and checks the thumbnail.

</details>

## Production image and Kamal

The production posture is configured but not deployed anywhere: the server and
registry in `config/deploy.yml` are placeholders. The production image uses Thruster in
front of Puma, a non-root user, jemalloc, asset precompilation, and an entrypoint
that runs `db:prepare db:seed`.

Kamal accessories reference prebuilt images and have a separate lifecycle:

```sh
  -t photo_searchable_library_rails_sidecar .
```

Persistent volumes hold `storage/` (primary, cache, queue, and cable SQLite
databases), `library/` (originals and crops), and `/models` (sidecar weights).

<details>
<summary><strong>Local Kamal deploy loop is future work</strong></summary>

A genuinely runnable `bin/kamal deploy -d local` requires SSH-to-localhost, a
throwaway registry, and the full proxy loop. It is tracked separately as
`kamal-local-deploy` and is not documented as working yet.

</details>

## Technical deep dives

<details>
<summary><strong>Rails multi-database setup</strong></summary>

Production has primary, cache, queue, and cable SQLite files. Development has
primary, queue, and cable. `schema_format = :sql` preserves sqlite-vec virtual
tables, while separate migration paths initialize Solid adapters.

</details>

<details>
<summary><strong>Solid Queue and Solid Cable</strong></summary>

Solid Queue is the database-backed Active Job adapter, so Redis is not required.
Development uses `bin/jobs start`; production can run the supervisor in Puma.
Turbo Streams broadcast job, catalog, and people updates through Solid Cable.

</details>

<details>
<summary><strong>sqlite-vec and vector search</strong></summary>

CLIP and face vectors are normalized 512-dimensional float32 blobs. Rails stores
metadata in `content_embeds`/`face_embeds` and indexes vectors in `vec0_content`
and `vec0_face`. The extension is loaded on every SQLite connection and KNN
queries use L2 distance.

</details>

<details>
<summary><strong>Import pipeline</strong></summary>

`AssetImporter` extracts EXIF metadata, makes a vips/ffmpeg thumbnail,
reverse-geocodes GPS, requests a sidecar embedding, stores the vector, and
classifies the source. `ScanJob` enqueues `ImportJob` per file.

</details>

<details>
<summary><strong>Faces and people</strong></summary>

Face detection, crops, face embeddings, clustering suggestions, and review
mutations are Rails-owned persistence around sidecar inference. Crop paths are
containment-checked before serving; repeated imports are idempotent.

</details>

<details>
<summary><strong>Kamal and Thruster</strong></summary>

Thruster is the production HTTP entrypoint (`bin/thrust`) on port 80. Kamal
orchestrates the Rails image over SSH, while the sidecar is a prebuilt accessory.
The amd64 target matches the sqlite-vec platform tags.

</details>

<details>
<summary><strong>Data ownership</strong></summary>

Rails owns the catalog and files. The sidecar owns model weights and inference.
The Swift bridge owns Photos access and only speaks HTTP. These boundaries make
the sidecar and bridge replaceable without changing catalog persistence.

</details>

## Quality gates

Run Rails commands in the container:

```sh
```

CI also runs importmap audit, system-test setup, and Docker builds for both the
production Rails image and the sidecar image.

## Roadmap and tradeoffs

Planned or deferred:

- CLI for scan, query, upload, strip-exif, cluster, and people.
- Behavioral conformance harness against the reference app.
- Local Kamal deploy loop (`kamal-local-deploy`).
- Video face extraction and fuller watch backfill behavior.

Tradeoffs: SQLite suits a single-user local library; sqlite-vec currently pins
the image build to amd64; real model startup downloads weights; production is
configured for one web container with Solid Queue in Puma.

## Data and backups

- `storage/` holds SQLite databases.
- `library/` holds imported originals, uploads, and crops.
- The Docker `models` volume holds model weights.

Back up the database and library directory together. They are the source of
truth. Avoid `docker compose down -v` unless destroying local data is intended.

## Project layout

```text
app/controllers/   HTTP endpoints
app/jobs/          Solid Queue jobs
app/models/        Catalog and job records
app/services/      Import, thumbnail, embedding, search, bridge logic
app/views/         Server-rendered Hotwire views
apps/photos-bridge/ Swift Apple Photos bridge
sidecar/           Stateless Python ML service
script/            Development and production helpers
test/              Minitest unit and request tests
config/            Rails, database, routes, deploy, and defaults
artifacts/         Discovery and implementation planning documents
```

## License

No license has been declared for this repository yet.
