# Photo Searchable Library for Rails

A Rails implementation of a searchable personal photo library. It imports
photos into a local catalog, generates thumbnails and embeddings, and exposes
search and catalog views from one Rails application.

This repository is an independent Rails fork of
[photo-searchable-library](https://github.com/scottsymm/photo-searchable-library).
The Rails app has its own SQLite database and library directory. It does not
share a catalog with the reference implementation.

## Current Status

The repository currently contains the Phase 1 foundation:

- Rails 8.1 full-stack application with server-rendered views
- Hotwire through Turbo and Stimulus
- SQLite with `sqlite-vec` for vector search
- Solid Queue for scan and import jobs
- A stateless Python sidecar for CLIP embeddings and reverse geocoding
- Mounted-folder scanning and direct uploads
- Search, catalog overview, thumbnail, job, and admin endpoints

People and face review, Places, Apple Photos synchronization, the CLI, and
production deployment tooling are planned follow-on phases. See the
[Rails port discovery](artifacts/photo-searchable-library-rails/rails-port/rails-port-discovery.md)
and [Phase 1 plan](artifacts/photo-searchable-library-rails/rails-port/rails-port-plan.md)
for the broader design and roadmap.

## Architecture

```text
Browser / HTTP clients
          |
          v
Rails 8.1 application (:3000)
  ERB + Turbo/Stimulus
  Active Record + SQLite/sqlite-vec
  Solid Queue jobs
          |
          v
Python ML sidecar (:9090)
  CLIP text/image embeddings
  Reverse geocoding
```

The sidecar is stateless: it owns model weights, not application data or job
state. The Rails application owns the catalog, thumbnails, library files, and
background jobs.

## Requirements

The supported development path uses Docker Compose:

- Docker with Compose v2
- A host directory containing the photos to scan

For host-native Rails development, also install:

- Ruby 3.3, pinned in `mise.toml`
- SQLite and the native libraries used by `ruby-vips`
- `libvips` with HEIC support
- `exiftool`
- `ffmpeg`

The Compose images install the native runtime dependencies automatically.

## Quick Start

Build the Rails and sidecar images:

```sh
docker compose build
```

Prepare the development database:

```sh
docker compose run --rm rails bin/rails db:prepare
```

Start the application, Solid Queue worker, and sidecar:

```sh
docker compose up
```

The `rails` service serves the web application and the `worker` service runs
Solid Queue jobs. Both services use the same development database and library
directory.

Open [http://localhost:3000](http://localhost:3000). The Compose development
stack uses `PICS_SIDECAR_MODE=stub`, so it is suitable for booting the app and
running deterministic development flows without downloading CLIP weights.

To use real CLIP embeddings, change `PICS_SIDECAR_MODE` to `real` in
`docker-compose.yml` and restart the sidecar. The first startup downloads the
model into the persistent `models` volume and may take several minutes.

To stop the stack:

```sh
docker compose down
```

The named `models` volume is retained by default. Add `-v` only when you also
want to remove downloaded model data.

## Configuration

The Rails app reads these environment variables:

| Variable | Default | Purpose |
|---|---|---|
| `PICS_LIBRARY` | `./library` | Directory where imported library files and crops are stored |
| `PICS_WATCH_ROOT` | `/media/photos` | Directory scanned by the admin scan action |
| `PICS_MOUNT_SOURCE` | `$HOME/Pictures` | Host directory mounted read-only at `/media/photos` |
| `PICS_WORKER_URL` | `http://localhost:9090` | URL of the Python ML sidecar |
| `PICS_MODEL` | `openai/clip-vit-base-patch32` | Hugging Face model loaded by the real sidecar |
| `PICS_MODEL_VERSION` | `clip-vit-base-patch32-v1` | Version recorded with real-sidecar embeddings |
| `PICS_MAX_UPLOAD_BYTES` | `104857600` | Maximum upload size, in bytes |

The Compose stack mounts `$HOME/Pictures` read-only at `/media/photos` in both
the Rails and worker containers. The Settings page reports the host source and
the container path. To use a different host directory, recreate the stack with
`PICS_MOUNT_SOURCE` set:

```sh
docker compose down
PICS_MOUNT_SOURCE=/Volumes/Backup/Photos docker compose up --build
```

Do not point two implementations at the same catalog database.

`PICS_MODEL` and `PICS_MODEL_VERSION` must be supplied to the sidecar process.
The Compose service passes them through from the host environment. They take
effect when `PICS_SIDECAR_MODE=real`; stub mode intentionally reports
`stub`/`stub-v1` and does not download or load the configured model.

## Main Routes

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/` | Browser dashboard, or JSON health response for API clients |
| `GET` | `/health` | JSON application health response |
| `GET` | `/search` | Semantic search with optional person, place, date, and tag filters |
| `GET` | `/catalog/overview` | Catalog counts and source overview |
| `POST` | `/assets/upload` | Upload an asset for background import |
| `GET` | `/assets/:id/thumbnail` | Return an asset thumbnail |
| `GET` | `/jobs` | List import and scan jobs |
| `GET` | `/jobs/:id` | Show one job |
| `GET` | `/admin/status` | Show catalog and sidecar status |
| `GET` | `/admin/settings` | Read application settings |
| `PATCH` | `/admin/settings` | Update application settings |
| `POST` | `/admin/scan` | Queue a scan of the configured watch root |

The search endpoint serves HTML by default and JSON when requested with
`Accept: application/json`.

The modern-browser restriction applies only to HTML responses. HTTP clients
should request JSON with `Accept: application/json`; JSON responses do not
require a browser user agent.

## Development Commands

Run Rails commands in the container so the Ruby and native dependencies match
the application image:

```sh
docker compose run --rm rails bin/rails db:migrate
docker compose run --rm rails bin/rails test
docker compose run --rm rails bin/rubocop
docker compose run --rm rails bin/brakeman --no-pager
docker compose run --rm rails bin/bundler-audit
```

For host-native Rails development, start the sidecar in a separate terminal
first. The Compose sidecar publishes port `9090` to the host and uses the same
deterministic stub mode as the full Compose stack:

```sh
docker compose up sidecar
```

Then, in a second terminal, install Ruby dependencies and start Rails:

```sh
mise install
bundle install
bin/rails db:prepare
bin/dev
```

`bin/dev` starts Rails only; it does not start the Python sidecar. Keep the
sidecar terminal running while using embedding or reverse-geocoding features.
It also does not start Solid Queue; run `bin/jobs start` separately when using
host-native Rails.
For a fully containerized development environment, use `docker compose up`
from the [Quick Start](#quick-start) instead.

The test suite uses Minitest. CI runs security scans, importmap audit,
RuboCop, unit/request tests, and system-test setup.

## Data and Files

Development data is intended to remain local:

- `storage/` and the Rails SQLite databases hold catalog data
- `library/` holds imported originals and generated files
- The Compose `models` volume holds downloaded model files

The default `storage/` contents are ignored by Git. Keep any local
`library/` directory and model data out of commits as well.

Back up the database and library directory together. They are the source of
truth for a local Rails installation.

## Project Layout

```text
app/controllers/   HTTP endpoints
app/jobs/          Solid Queue jobs
app/models/        Catalog and job records
app/services/      Import, thumbnail, embedding, and search logic
app/views/         Server-rendered Rails and Hotwire views
sidecar/           Stateless Python embedding/geocoding service
test/              Minitest unit and request tests
config/            Rails, database, routes, and application defaults
artifacts/         Discovery and implementation planning documents
```

## License

No license has been declared for this repository yet.
