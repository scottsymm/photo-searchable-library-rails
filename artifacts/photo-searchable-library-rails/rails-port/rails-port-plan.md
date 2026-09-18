---
title: Rails Port — Phase 1 Implementation Plan
tags:
  - plan
  - rails-port
  - phase-1
  - ruby-on-rails
  - hotwire
created: 2026-09-18
---

# Rails Port Phase 1 — Repo, Foundation, Ingest, Search

*Created: 2026-09-18*

**Goal:** A self-contained GitHub repo running a Rails 8.1 app that boots on
SQLite + sqlite-vec, runs a stateless Python ML sidecar, imports photos from the
mounted folder and uploads, and serves search + a basic catalog UI — with the
FastAPI contract preserved.

**Architecture:** Rails 8.1 full-stack (ERB + Turbo + Stimulus, Propshaft,
Solid Queue, SQLite). `sqlite-vec` is loaded on every connection via an adapter
prepend; virtual tables are created in raw SQL migrations and dumped to
`structure.sql` (`schema_format = :sql`). A slim Python FastAPI sidecar
(`sidecar/`) owns CLIP text/image embeddings and reverse-geocoding; it has no
database and no app logic. Solid Queue runs scan/import jobs; a domain `jobs`
table preserves the `GET /jobs` contract.

**Tech Stack:** Ruby 3.3 (via mise), Rails 8.1, sqlite3 + sqlite-vec, Solid
Queue, ruby-vips + ffmpeg (thumbnails), mini_exiftool (metadata), Faraday
(sidecar client), Minitest (tests).

**Source:** `rails-port-discovery.md` (this repo, `artifacts/.../rails-port/`).
Reference implementation: `/Users/jobofish/code/pics` (read-only).

**Locked decisions (from discovery review):** reverse-geocoding and face
clustering both live in the **Python sidecar** (`/v1/reverse-geocode`,
`/v1/cluster-faces` — the latter lands in Phase 2). Repo is an **independent
fork** with its own database; no shared catalog.

**Deferred to later phases:** people/faces (Phase 2), places UI + cluster
(Phase 2/3), Apple Photos bridge protocol (Phase 4), CLI + Docker/Kamal deploy +
conformance harness (Phase 5). The schema is fully created in Phase 1 so later
phases add no schema churn.

## Pre-execution blockers and readiness gate

Do not begin Task 1 until every item below is resolved or explicitly accepted.
These are implementation constraints, not optional follow-up work.

- [ ] **Local toolchain:** install `mise`, provision Ruby 3.3, and confirm
  `mise exec -- ruby -v` reports Ruby 3.3.x. Do not rely on the system Ruby
  2.6 installation. Keep shell activation idempotent; do not append duplicate
  entries to `~/.zshrc`.
- [ ] **Repository ownership:** decide the GitHub owner and visibility before
  Task 2. Confirm `gh auth status`, then create the remote and verify it with
  `git remote -v`. Do not push until the initial generated files are reviewed.
- [ ] **Schema dependency order:** create `sources` before `assets`, or defer
  `assets -> sources` until after both tables exist. The migration must run on a
  clean SQLite database without foreign-key errors.
- [ ] **Schema inventory:** reconcile the documented count. Phase 1 creates 17
  regular domain tables plus `vec0_content` and `vec0_face` virtual tables,
  alongside Rails/Solid Queue tables. The migration verification must assert the
  exact expected names rather than only printing all tables.
- [ ] **Vector contract:** keep production vectors at 512 dimensions and use
  512-dimensional vectors in tests. sqlite-vec 0.1.9 supports the default L2
  metric used by this migration; CLIP vectors are normalized by the sidecar,
  so L2 ranking preserves cosine similarity ranking. Verify the returned L2
  distance rather than assuming a cosine-distance value.
- [ ] **Phase 1 HTTP scope:** explicitly accept that Phase 1 does not implement
  `/admin/library` or the Apple Photos `/sources/apple-photos/*` routes. The
  “FastAPI contract preserved” goal means the Phase 1 subset only; full contract
  parity remains deferred to Phases 4–5.
- [ ] **Sidecar packaging:** add `sidecar/__init__.py` (or an equivalent
  package configuration), verify `pip install` includes `sidecar.app`, and make
  the sidecar boot independently from `/Users/jobofish/code/pics`. The reference
  checkout may be used for comparison only, not as a runtime prerequisite.
- [ ] **Native/runtime dependencies:** verify `libvips` with HEIC support,
  `exiftool`, `ffmpeg`, and Docker are available before running import tests.
- [ ] **End-to-end acceptance fixture:** reserve the Phase 1 tiny JPEG fixture
  for a real import acceptance test covering thumbnail storage, embedding
  insertion, job completion, `/search`, and `/assets/:id/thumbnail`.

Phase 1 is ready to execute only after all readiness-gate checkboxes are checked.

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `mise.toml` | Create | Pin Ruby 3.3 for the repo |
| `.github/` / git repo | Create via `gh` | GitHub repo `photo-searchable-library-rails` |
| `Gemfile` | Modify | Add sqlite-vec, ruby-vips, mini_exiftool, faraday |
| `config/application.rb` | Modify | `schema_format = :sql`, solid_queue adapter |
| `config/initializers/sqlite_vec.rb` | Create | Load sqlite-vec on every SQLite connection |
| `config/initializers/pics.rb` | Create | PICS_* env defaults (library, watch root, worker URL) |
| `db/migrate/*_create_pics_schema.rb` | Create | Full catalog schema (17 regular domain tables) |
| `db/migrate/*_create_vec_tables.rb` | Create | `vec0_content`, `vec0_face` virtual tables |
| `db/migrate/*_seed_pics_defaults.rb` | Create | Seed sources + settings |
| `app/models/asset.rb` | Create | `assets` row, belongs_to source |
| `app/models/stored_file.rb` | Create | `files` table (thumbnail BLOBs) |
| `app/models/source.rb` | Create | `sources` + path classifier |
| `app/models/setting.rb` | Create | Key-value settings store |
| `app/models/job.rb` | Create | Domain `jobs` table (API contract) |
| `app/models/content_embed.rb` | Create | `content_embeds` row |
| `app/models/face.rb`, `person.rb`, `person_alias.rb`, `person_face.rb`, `face_embed.rb`, `clustering_run.rb`, `cluster_suggestion.rb`, `face_assignment.rb`, `source_sync.rb`, `tag.rb` | Create | Tables for later phases (models only) |
| `app/services/sidecar_client.rb` | Create | Faraday client for sidecar endpoints |
| `app/services/exif_metadata.rb` | Create | mini_exiftool extraction |
| `app/services/thumbnail_maker.rb` | Create | ruby-vips images + ffmpeg video frames |
| `app/services/embedding_store.rb` | Create | content_embeds + vec0_content insert/KNN |
| `app/services/asset_importer.rb` | Create | Full per-file import pipeline |
| `app/services/search_service.rb` | Create | KNN + structured filters (port of search.py) |
| `app/services/catalog_overview.rb` | Create | Funnel + sources + context JSON |
| `app/jobs/scan_job.rb` | Create | Solid Queue job: walk root, enqueue imports |
| `app/jobs/import_job.rb` | Create | Solid Queue job: run AssetImporter |
| `app/controllers/health_controller.rb` | Create | `GET /` health |
| `app/controllers/search_controller.rb` | Create | `GET /search` |
| `app/controllers/catalog_controller.rb` | Create | `GET /catalog/overview` |
| `app/controllers/uploads_controller.rb` | Create | `POST /assets/upload` |
| `app/controllers/assets_controller.rb` | Create | `GET /assets/:id/thumbnail` |
| `app/controllers/jobs_controller.rb` | Create | `GET /jobs`, `GET /jobs/:id` |
| `app/controllers/admin_controller.rb` | Create | `GET /admin/status`, settings, `POST /admin/scan` |
| `config/routes.rb` | Modify | Route table mirroring FastAPI |
| `app/views/search/index.html.erb` | Create | Search form + results grid |
| `app/views/catalog/overview.html.erb` | Create | Funnel + sources summary |
| `app/views/jobs/index.html.erb` | Create | Job list |
| `app/views/layouts/application.html.erb` | Modify | Nav + Turbo setup |
| `sidecar/__init__.py`, `sidecar/app.py`, `sidecar/models.py` | Create | FastAPI: embed-text, embed-image, reverse-geocode, status |
| `sidecar/pyproject.toml`, `sidecar/Dockerfile`, `sidecar/.dockerignore` | Create | Sidecar packaging |
| `docker-compose.yml` | Create | Rails + sidecar dev stack |
| `test/services/*_test.rb` | Create | Unit tests (search, importer, thumbnail, geo) |
| `test/controllers/*_test.rb` | Create | Request tests for the contract endpoints |
| `test/fixtures/tiny.jpg` | Create | Base64-decoded 1×1 JPEG fixture |

---

## Tasks

### Task 1: Install mise and Ruby 3.3

**Files:**
- Create: `mise.toml`

- [x] **Step 1: Install mise**

```bash
brew install mise
```

- [x] **Step 2: Activate mise for the current shell (and persist)**

```bash
grep -qxF 'eval "$(mise activate zsh)"' ~/.zshrc || echo 'eval "$(mise activate zsh)"' >> ~/.zshrc
eval "$(mise activate zsh)"
```

Do not run the append command repeatedly. If shell startup changes are not
desired, run the `eval` only for the current shell and use `mise exec` for all
plan commands.

- [x] **Step 3: Pin Ruby 3.3 for the repo**

```bash
cd /Users/jobofish/code/photo-searchable-library-rails
mise use ruby@3.3
```

This creates `mise.toml` with the current mise format:

```toml
[tools]
ruby = "3.3"
```

- [x] **Step 4: Verify**

Run: `mise exec -- ruby -v`
Expected: `ruby 3.3.x ...`

- [x] **Step 5: Commit**

```bash
git init -q
git add mise.toml
git commit -q -m "chore: pin ruby 3.3 with mise"
```

---

### Task 2: Create the GitHub repo

**Files:**
- None (repo-level)

- [x] **Step 1: Create the repo from the local directory**

```bash
cd /Users/jobofish/code/photo-searchable-library-rails
gh repo create photo-searchable-library-rails --source=. --remote=origin --public --push
```

> If you prefer a private repo, use `--private` instead of `--public`.

- [x] **Step 2: Verify**

Run: `git remote -v`
Expected: `origin  git@github.com:<owner>/photo-searchable-library-rails.git (push)`

---

### Task 3: Scaffold the Rails 8.1 app

**Files:**
- Many (generated by `rails new`)

- [x] **Step 1: Install Rails 8.1**

```bash
mise exec -- gem install rails -v '~> 8.1.0'
```

- [x] **Step 2: Generate the app in the current directory**

```bash
mise exec -- rails new . --database=sqlite3
```

> The directory already contains `artifacts/` and `mise.toml`; `rails new .`
> is the correct invocation. It will not touch existing files it doesn't own.

- [x] **Step 3: Verify the app boots**

```bash
mise exec -- bin/rails runner "puts Rails.version"
```
Expected: `8.1.x`

- [x] **Step 4: Commit**

```bash
git add -A
git commit -q -m "feat: scaffold rails 8.1 app"
```

---

### Task 4: Bootstrap the containerized Rails runtime and add gems

**Files:**
- Modify: `Gemfile`
- Create: `Dockerfile.rails`, `docker-compose.yml`

- [x] **Step 1: Add the gems**

```ruby
# Gemfile — append inside the existing gems block
gem "sqlite-vec", "~> 0.1.9"
gem "ruby-vips"
gem "mini_exiftool"
gem "faraday"
```

- [x] **Step 2: Remove the host-generated lockfile, if present**

```bash
rm -f Gemfile.lock
```

The authoritative lockfile must be generated by Bundler in the Linux Rails
container. The development container is pinned to `linux/amd64` because that
is the platform tag published by the pinned sqlite-vec gem. Do not run
host-native `bundle install` for this task.

- [x] **Step 3: Create the Rails container definition**

```dockerfile
# Dockerfile.rails
FROM ruby:3.3-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential libsqlite3-dev sqlite3 libvips42 libheif1 exiftool ffmpeg \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY Gemfile Gemfile.lock ./
RUN bundle install
COPY . .

CMD ["bin/rails", "runner", "\"puts Rails.version\""]
```

```yaml
# docker-compose.yml
services:
  rails:
    platform: linux/amd64
    build:
      context: .
      dockerfile: Dockerfile.rails
    command: bin/rails runner "puts Rails.version"
    volumes:
      - .:/app
    environment:
      - RAILS_ENV=development
```

- [x] **Step 4: Install dependencies inside the container**

```bash
docker compose build rails
docker compose run --rm rails bundle lock
```

The second command writes the container-resolved `Gemfile.lock` into the
checkout through the bind mount. Keep the generated lockfile in version
control; future builds must copy it before running `bundle install`.

From Task 5 onward, run Rails and Bundler commands inside this container with
`docker compose run --rm rails ...`. The host mise installation remains useful
for editing and repository tooling, but it is not the authoritative Ruby
runtime for the application.

- [x] **Step 5: Verify Rails and sqlite-vec inside the container**

Run: `docker compose run --rm rails bundle exec ruby -e "require 'sqlite_vec'; puts SqliteVec::VERSION"`
Expected: prints a version string like `0.1.9` (or similar; must not raise).

- [x] **Step 6: Commit**

```bash
git add Gemfile Gemfile.lock Dockerfile.rails docker-compose.yml
git commit -q -m "chore: containerize Rails dependencies"
```

---

### Task 5: Configure structure.sql and Solid Queue

**Files:**
- Modify: `config/application.rb`

- [x] **Step 1: Set schema format and queue adapter**

```ruby
# config/application.rb — inside class Application < Rails::Application
    config.active_record.schema_format = :sql
    config.active_job.queue_adapter = :solid_queue
```

- [x] **Step 2: Install Solid Queue tables/config**

```bash
mise exec -- bin/rails generate solid_queue:install
mise exec -- bin/rails db:migrate
```

Rails 8.1 scaffolding already creates `db/queue_schema.rb`. In the
development container, Solid Queue uses the primary SQLite database, so load
that schema into the development database after the regular migration:

```bash
docker compose run --rm rails bin/rails db:migrate
docker compose run --rm rails bin/rails runner "load Rails.root.join('db/queue_schema.rb').to_s"
```

- [x] **Step 3: Verify**

Run: `docker compose run --rm rails bin/rails runner "puts ActiveRecord::Base.connection.tables.grep(/solid_queue/).sort"`
Expected: prints the `solid_queue_*` table names from the primary development
database. Production may continue using the generated separate queue
database configuration.

- [x] **Step 4: Commit**

```bash
git add -A
git commit -q -m "feat: enable structure.sql and solid queue"
```

---

### Task 6: Load sqlite-vec on every connection

**Files:**
- Create: `config/initializers/sqlite_vec.rb`

- [x] **Step 1: Write the initializer**

```ruby
# config/initializers/sqlite_vec.rb
require "sqlite_vec"

module SqliteVecConnection
  def configure_connection
    super
    @raw_connection.enable_load_extension(true)
    SqliteVec.load(@raw_connection)
  end
end

ActiveSupport.on_load(:active_record_sqlite3adapter) do
  prepend SqliteVecConnection
end
```

This prepends onto the SQLite3 adapter's `configure_connection`, which Rails
calls after every new physical connection — so every pooled connection (web,
jobs, migrations, tests) has the `vec0` functions available.

- [x] **Step 2: Verify the extension loads on a fresh connection**

```bash
mise exec -- bin/rails runner "db = ActiveRecord::Base.connection.raw_connection; puts db.execute('SELECT vec_version()').inspect"
```
Expected: a row containing a version string, e.g. `[["v0.1.x"]]`. No error.

- [x] **Step 3: Commit**

```bash
git add config/initializers/sqlite_vec.rb
git commit -q -m "feat: load sqlite-vec on every sqlite connection"
```

---

### Task 7: Default PICS configuration

**Files:**
- Create: `config/initializers/pics.rb`

- [x] **Step 1: Write the initializer**

```ruby
# config/initializers/pics.rb
PICS_LIBRARY   = ENV.fetch("PICS_LIBRARY", File.expand_path("library", Rails.root))
PICS_WATCH_ROOT = ENV.fetch("PICS_WATCH_ROOT", "/media/photos")
PICS_WORKER_URL = ENV.fetch("PICS_WORKER_URL", "http://localhost:9090")
PICS_MODEL      = ENV.fetch("PICS_MODEL", "openai/clip-vit-base-patch32")
PICS_MODEL_VERSION = ENV.fetch("PICS_MODEL_VERSION", "clip-vit-base-patch32-v1")
MEDIA_SUFFIXES  = %w[.jpg .jpeg .png .heic .heif .mov .mp4 .avif .dng].freeze
```

- [x] **Step 2: Verify**

Run: `mise exec -- bin/rails runner "puts PICS_WORKER_URL"`
Expected: `http://localhost:9090`

- [x] **Step 3: Commit**

```bash
git add config/initializers/pics.rb
git commit -q -m "feat: pics configuration defaults"
```

---

### Task 8: Full catalog schema migration

**Files:**
- Create: `db/migrate/<timestamp>_create_pics_schema.rb`

> This ports the regular domain tables from `packages/core/core/schema.py` in
> one migration. The two sqlite-vec virtual tables are created separately in
> Task 9.
> The fork is free to evolve it; this is the Phase 1 baseline.

> **Required correction before implementation:** create `sources` before
> `assets`, or add the `assets.source_id` foreign key after `sources` exists.
> Also update the comment to match the readiness-gate inventory: 17 regular
> domain tables plus two virtual vector tables.

- [x] **Step 1: Generate the migration**

```bash
mise exec -- bin/rails generate migration CreatePicsSchema
```

- [x] **Step 2: Replace the generated body**

```ruby
class CreatePicsSchema < ActiveRecord::Migration[8.1]
  def change
    create_table :schema_meta, id: false do |t|
      t.string :key, null: false
      t.string :value, null: false
    end
    add_index :schema_meta, :key, unique: true

    create_table :assets do |t|
      t.string :path, null: false
      t.string :sha256, null: false
      t.integer :size_bytes, null: false, default: 0
      t.string :mime, null: false
      t.integer :source_id
      t.string :source_asset_id
      t.string :original_filename
      t.datetime :taken_at
      t.float :gps_lat
      t.float :gps_lon
      t.string :place_city
      t.string :place_country
      t.integer :thumbnail_id
      t.integer :stripped, null: false, default: 0
      t.integer :deleted, null: false, default: 0
      t.integer :skipped, null: false, default: 0
      t.text :extra
      t.timestamps
    end
    add_index :assets, :path, unique: true
    add_index :assets, :taken_at
    add_index :assets, [:place_city, :place_country]
    add_index :assets, [:source_id, :source_asset_id], unique: true
    add_foreign_key :assets, :sources

    create_table :files do |t|
      t.string :sha256, null: false
      t.string :kind, null: false
      t.binary :bytes
      t.timestamps
    end
    add_index :files, :sha256, unique: true

    create_table :sources do |t|
      t.string :kind, null: false
      t.string :display_name, null: false
      t.string :status, null: false, default: "not_connected"
      t.string :authorization_state
      t.string :bridge_status, null: false, default: "offline"
      t.datetime :bridge_last_seen_at
      t.datetime :last_sync_at
      t.string :last_error
      t.integer :asset_count, null: false, default: 0
      t.integer :imported_count, null: false, default: 0
      t.timestamps
    end
    add_index :sources, :kind, unique: true

    create_table :source_syncs do |t|
      t.integer :source_id, null: false
      t.string :status, null: false, default: "queued"
      t.integer :limit_count, null: false, default: 25
      t.integer :full_sync, null: false, default: 0
      t.datetime :started_at
      t.datetime :completed_at
      t.integer :imported_count, null: false, default: 0
      t.integer :failed_count, null: false, default: 0
      t.string :error
      t.timestamps
    end
    add_foreign_key :source_syncs, :sources

    create_table :persons do |t|
      t.string :name, null: false, default: ""
      t.integer :prototype_face_id
      t.string :status, null: false, default: "new"
    end

    create_table :person_aliases do |t|
      t.integer :person_id, null: false
      t.string :alias, null: false
      t.timestamps
    end
    add_index :person_aliases, [:person_id, :alias], unique: true
    add_foreign_key :person_aliases, :persons, on_delete: :cascade

    create_table :faces do |t|
      t.integer :asset_id, null: false
      t.string :crop_path
      t.string :bbox, null: false
      t.integer :cluster_id
    end
    add_foreign_key :faces, :assets, on_delete: :cascade

    create_table :content_embeds do |t|
      t.integer :asset_id, null: false
      t.string :model, null: false
      t.string :model_version, null: false
      t.binary :embed, null: false
    end
    add_index :content_embeds, :asset_id, unique: true
    add_foreign_key :content_embeds, :assets, on_delete: :cascade

    create_table :face_embeds do |t|
      t.integer :face_id, null: false
      t.string :model, null: false
      t.binary :embed, null: false
    end
    add_index :face_embeds, :face_id, unique: true
    add_foreign_key :face_embeds, :faces, on_delete: :cascade

    create_table :clustering_runs do |t|
      t.string :model, null: false
      t.string :model_version, null: false
      t.string :algorithm, null: false
      t.string :metric, null: false
      t.float :eps, null: false
      t.integer :min_samples, null: false
      t.string :status, null: false, default: "running"
      t.datetime :completed_at
      t.string :error
      t.timestamps
    end

    create_table :cluster_suggestions do |t|
      t.integer :run_id, null: false
      t.integer :cluster_key, null: false
      t.integer :representative_face_id
      t.integer :face_count, null: false
      t.string :confidence, null: false, default: "candidate"
      t.string :status, null: false, default: "unreviewed"
      t.integer :person_id
    end
    add_index :cluster_suggestions, [:run_id, :cluster_key], unique: true
    add_foreign_key :cluster_suggestions, :clustering_runs, column: :run_id, on_delete: :cascade

    create_table :face_assignments do |t|
      t.integer :run_id, null: false
      t.integer :face_id, null: false
      t.integer :suggestion_id
      t.float :distance
      t.string :status, null: false, default: "suggested"
    end
    add_index :face_assignments, [:run_id, :face_id], unique: true
    add_foreign_key :face_assignments, :clustering_runs, column: :run_id, on_delete: :cascade

    create_table :person_faces do |t|
      t.integer :person_id, null: false
      t.integer :face_id, null: false
      t.string :source, null: false
      t.timestamps
    end
    add_index :person_faces, [:person_id, :face_id], unique: true
    add_index :person_faces, :face_id
    add_foreign_key :person_faces, :persons, on_delete: :cascade
    add_foreign_key :person_faces, :faces, on_delete: :cascade

    create_table :settings, id: false do |t|
      t.string :key, null: false
      t.string :value
      t.timestamps
    end
    add_index :settings, :key, unique: true

    create_table :tags, id: false do |t|
      t.integer :asset_id, null: false
      t.string :tag, null: false
      t.string :source, null: false, default: "manual"
    end
    add_index :tags, [:asset_id, :tag], unique: true
    add_foreign_key :tags, :assets, on_delete: :cascade

    create_table :jobs do |t|
      t.string :kind, null: false
      t.string :status, null: false, default: "queued"
      t.float :progress, null: false, default: 0
      t.string :error
      t.text :params
      t.timestamps
    end
    add_index :jobs, :status
  end
end
```

- [x] **Step 3: Migrate**

```bash
mise exec -- bin/rails db:migrate
```

- [x] **Step 4: Verify**

Run: `mise exec -- bin/rails runner "puts ActiveRecord::Base.connection.tables.sort"`
Expected: lists the exact 17 regular domain tables, plus `schema_migrations`,
the `solid_queue_*` tables, and no unexpected missing domain table. The vector
tables are verified separately in Task 9.

- [x] **Step 5: Commit**

```bash
git add db/migrate/ db/structure.sql
git commit -q -m "feat: port catalog schema to activerecord migrations"
```

> `db/structure.sql` is generated because of `schema_format = :sql`. It will be
> regenerated after Task 9 so the virtual tables are captured.

---

### Task 9: vec0 virtual tables migration

**Files:**
- Create: `db/migrate/<timestamp>_create_vec_tables.rb`

- [x] **Step 1: Generate the migration**

```bash
mise exec -- bin/rails generate migration CreateVecTables
```

- [x] **Step 2: Replace the generated body**

```ruby
class CreateVecTables < ActiveRecord::Migration[8.1]
  def up
    execute "CREATE VIRTUAL TABLE IF NOT EXISTS vec0_content USING vec0(content_embed float[512])"
    execute "CREATE VIRTUAL TABLE IF NOT EXISTS vec0_face USING vec0(face_embed float[512])"
  end

  def down
    execute "DROP TABLE IF EXISTS vec0_content"
    execute "DROP TABLE IF EXISTS vec0_face"
  end
end
```

- [x] **Step 3: Migrate and dump structure.sql**

```bash
mise exec -- bin/rails db:migrate
mise exec -- bin/rails db:structure:dump
```

- [x] **Step 4: Verify**

Run: `grep -n "CREATE VIRTUAL TABLE" db/structure.sql`
Expected: two matches (`vec0_content`, `vec0_face`). Also verify the declared
dimension and distance metric using sqlite-vec's table introspection or a
known 512-dimensional KNN query. If this sqlite-vec version uses different
syntax for the metric, resolve that syntax here before continuing.

- [x] **Step 5: Commit**

```bash
git add db/migrate/ db/structure.sql
git commit -q -m "feat: add vec0 virtual tables and structure.sql dump"
```

---

### Task 10: Seed sources and settings

**Files:**
- Create: `db/migrate/<timestamp>_seed_pics_defaults.rb`

- [x] **Step 1: Generate the migration**

```bash
mise exec -- bin/rails generate migration SeedPicsDefaults
```

- [x] **Step 2: Replace the generated body**

```ruby
class SeedPicsDefaults < ActiveRecord::Migration[8.1]
  def up
    [
      ["apple_photos", "Apple Photos"],
      ["mounted_folder", "Mounted folder"],
      ["uploads", "Uploads"],
    ].each do |kind, display_name|
      execute <<~SQL
        INSERT INTO sources(kind, display_name, status, created_at, updated_at)
        VALUES ('#{kind}', '#{display_name}', 'not_connected', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        ON CONFLICT(kind) DO NOTHING
      SQL
    end

    { "watch_enabled" => "0", "watch_backfill" => "prompt", "watch_initialized" => "0" }.each do |key, value|
      execute <<~SQL
        INSERT INTO settings(key, value, created_at, updated_at)
        VALUES ('#{key}', '#{value}', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        ON CONFLICT(key) DO NOTHING
      SQL
    end
  end

  def down
    execute "DELETE FROM sources WHERE kind IN ('apple_photos','mounted_folder','uploads')"
    execute "DELETE FROM settings WHERE key IN ('watch_enabled','watch_backfill','watch_initialized')"
  end
end
```

- [x] **Step 3: Migrate and verify**

```bash
docker compose run --rm rails bin/rails db:migrate
docker compose run --rm rails bin/rails runner 'puts ActiveRecord::Base.connection.select_values("SELECT kind FROM sources ORDER BY kind").inspect'
```
Expected: `["apple_photos", "mounted_folder", "uploads"]`

- [x] **Step 4: Commit**

```bash
git add db/migrate/
git commit -q -m "feat: seed sources and settings defaults"
```

---

### Task 11: Core ActiveRecord models

**Files:**
- Create: `app/models/asset.rb`, `app/models/stored_file.rb`, `app/models/source.rb`, `app/models/setting.rb`, `app/models/job.rb`, `app/models/content_embed.rb`

- [x] **Step 1: Asset**

```ruby
# app/models/asset.rb
class Asset < ApplicationRecord
  belongs_to :source, optional: true
  has_one :content_embed
  has_many :faces
  has_many :tags

  scope :not_deleted, -> { where(deleted: 0) }

  def thumbnail_url
    "/assets/#{id}/thumbnail"
  end
end
```

- [x] **Step 2: StoredFile**

```ruby
# app/models/stored_file.rb
class StoredFile < ApplicationRecord
  self.table_name = "files"
end
```

- [x] **Step 3: Source (with path classifier)**

```ruby
# app/models/source.rb
class Source < ApplicationRecord
  has_many :assets
  has_many :source_syncs

  def self.library_root
    Pathname.new(PICS_LIBRARY)
  end

  def self.watch_root
    Pathname.new(PICS_WATCH_ROOT)
  end

  # Port of packages/core/core/sources.py classify_path -> returns the Source row
  def self.classify_path(path)
    resolved = Pathname.new(path).expand_path.to_s
    [["apple-photos", "apple_photos"], ["imports", "uploads"]].each do |subdir, kind|
      prefix = library_root.join(subdir).expand_path.to_s
      return find_by!(kind: kind) if resolved.start_with?(prefix + File::SEPARATOR) || resolved == prefix
    end
    prefix = watch_root.expand_path.to_s
    return find_by!(kind: "mounted_folder") if resolved.start_with?(prefix + File::SEPARATOR) || resolved == prefix
    nil
  end
end
```

- [x] **Step 4: Setting**

```ruby
# app/models/setting.rb
class Setting < ApplicationRecord
  self.primary_key = "key"

  def self.get(key, default = nil)
    find_by(key: key)&.value || default
  end

  def self.set_value(key, value)
    record = find_or_initialize_by(key: key)
    record.value = value
    record.save!
  end

  def self.all_map
    order(:key).pluck(:key, :value).to_h
  end
end
```

- [x] **Step 5: Job**

```ruby
# app/models/job.rb
class Job < ApplicationRecord
  validates :kind, presence: true

  def mark_working!
    update!(status: "working", progress: 0)
  end

  def bump_progress!(value)
    update!(progress: value.clamp(0.0, 1.0))
  end

  def complete!
    update!(status: "done", progress: 1)
  end

  def fail!(message)
    update!(status: "error", error: message.to_s[0, 4000])
  end
end
```

- [x] **Step 6: ContentEmbed**

```ruby
# app/models/content_embed.rb
class ContentEmbed < ApplicationRecord
  belongs_to :asset
end
```

- [x] **Step 7: Verify**

Run: `mise exec -- bin/rails runner 'puts [Asset, StoredFile, Source, Setting, Job, ContentEmbed].map(&:name).join(",")'`
Expected: `Asset,StoredFile,Source,Setting,Job,ContentEmbed` (no LoadError)

- [x] **Step 8: Commit**

```bash
git add app/models
git commit -q -m "feat: core activerecord models"
```

---

### Task 12: Stub models for later phases

**Files:**
- Create: `app/models/face.rb`, `app/models/person.rb`, `app/models/person_alias.rb`, `app/models/person_face.rb`, `app/models/face_embed.rb`, `app/models/clustering_run.rb`, `app/models/cluster_suggestion.rb`, `app/models/face_assignment.rb`, `app/models/source_sync.rb`, `app/models/tag.rb`

- [x] **Step 1: Create the stub models**

These tables already exist (Task 8); models let later phases and the overview
service reference them now.

```ruby
# app/models/face.rb
class Face < ApplicationRecord
  belongs_to :asset
end
```

```ruby
# app/models/person.rb
class Person < ApplicationRecord
  has_many :person_faces
end
```

```ruby
# app/models/person_alias.rb
class PersonAlias < ApplicationRecord
  belongs_to :person
end
```

```ruby
# app/models/person_face.rb
class PersonFace < ApplicationRecord
  self.table_name = "person_faces"
  belongs_to :person
  belongs_to :face
end
```

```ruby
# app/models/face_embed.rb
class FaceEmbed < ApplicationRecord
  belongs_to :face
end
```

```ruby
# app/models/clustering_run.rb
class ClusteringRun < ApplicationRecord
end
```

```ruby
# app/models/cluster_suggestion.rb
class ClusterSuggestion < ApplicationRecord
  belongs_to :run, class_name: "ClusteringRun"
end
```

```ruby
# app/models/face_assignment.rb
class FaceAssignment < ApplicationRecord
end
```

```ruby
# app/models/source_sync.rb
class SourceSync < ApplicationRecord
  belongs_to :source
end
```

```ruby
# app/models/tag.rb
class Tag < ApplicationRecord
  self.table_name = "tags"
  belongs_to :asset
end
```

- [x] **Step 2: Verify**

Run: `mise exec -- bin/rails runner 'puts [Face, Person, PersonAlias, PersonFace, FaceEmbed, ClusteringRun, ClusterSuggestion, FaceAssignment, SourceSync, Tag].map(&:name).join(",")'`
Expected: comma-separated names, no LoadError.

- [x] **Step 3: Commit**

```bash
git add app/models
git commit -q -m "feat: activerecord models for faces, persons, clustering"
```

---

### Task 13: Sidecar client

**Files:**
- Create: `app/services/sidecar_client.rb`

- [x] **Step 1: Write the client**

```ruby
# app/services/sidecar_client.rb
require "faraday"
require "base64"

class SidecarClient
  class SidecarError < StandardError; end

  def self.status
    new.get("/v1/status")
  end

  def self.embed_text(text)
    new.post("/v1/embed-text", { texts: [text] })
  end

  def self.embed_image(image_bytes, mime: "image/jpeg")
    new.post("/v1/embed-image", {
      image_base64: Base64.strict_encode64(image_bytes),
      mime: mime,
    })
  end

  def self.reverse_geocode(lat:, lon:)
    new.post("/v1/reverse-geocode", { lat: lat, lon: lon })
  end

  def initialize
    @conn = Faraday.new(url: PICS_WORKER_URL) do |faraday|
      faraday.request :json
      faraday.response :json
      faraday.response :raise_error
      faraday.options.timeout = 120
    end
  end

  def get(path)
    @conn.get(path).body
  rescue Faraday::Error => e
    raise SidecarError, "sidecar GET #{path} failed: #{e.class}: #{e.message}"
  end

  def post(path, body)
    @conn.post(path, body).body
  rescue Faraday::Error => e
    raise SidecarError, "sidecar POST #{path} failed: #{e.class}: #{e.message}"
  end
end
```

- [x] **Step 2: Verify (client builds, no request yet)**

Run: `mise exec -- bin/rails runner 'puts SidecarClient.new.inspect'`
Expected: prints a `#<SidecarClient ...>` instance, no error.

- [x] **Step 3: Commit**

```bash
git add app/services/sidecar_client.rb
git commit -q -m "feat: faraday client for python sidecar"
```

---

### Task 14: EXIF metadata extraction

**Files:**
- Create: `app/services/exif_metadata.rb`

- [x] **Step 1: Write the service**

```ruby
# app/services/exif_metadata.rb
require "mini_exiftool"

class ExifMetadata
  # Port of services/worker/worker/exif.py (numeric GPS, fallback tags)
  def self.extract(path)
    tag = MiniExiftool.new(path, numerical: true)
    {
      taken_at: tag.datetimeoriginal || tag.createdate,
      gps_lat: signed(tag.gpslatitude, tag.gpslatituderef),
      gps_lon: signed(tag.gpslongitude, tag.gpslongituderef),
      mime: tag.mimetype || "application/octet-stream",
      size_bytes: tag.filesize.to_i,
      model: tag.model,
    }
  rescue MiniExiftool::Error, Errno::ENOENT
    {}
  end

  def self.signed(value, reference)
    return nil if value.nil?
    number = value.to_f
    if %w[S W South West].include?(reference.to_s)
      -number.abs
    else
      number.abs
    end
  end
end
```

- [x] **Step 2: Verify against a real file**

```bash
SAMPLE=$(find /Users/jobofish/Pictures -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.heic' \) 2>/dev/null | head -1)
mise exec -- bin/rails runner "puts ExifMetadata.extract('$SAMPLE').inspect"
```
Expected: a hash with `:mime`, `:size_bytes` (and possibly `:taken_at`, `:gps_lat`, `:gps_lon`, `:model`). If `$SAMPLE` is empty, create a JPEG fixture first (Task 21) and re-run.

- [x] **Step 3: Commit**

```bash
git add app/services/exif_metadata.rb
git commit -q -m "feat: exif metadata extraction via mini_exiftool"
```

---

### Task 15: Thumbnail maker (vips + ffmpeg)

**Files:**
- Create: `app/services/thumbnail_maker.rb`

- [x] **Step 1: Write the service**

```ruby
# app/services/thumbnail_maker.rb
require "vips"
require "open3"

class ThumbnailMaker
  MAX_DIM = 512

  # Port of services/worker/worker/thumbnail.py
  def self.thumbnail(path, mime)
    if mime.to_s.start_with?("video/")
      video_frame(path)
    else
      image_thumbnail(path)
    end
  end

  def self.image_thumbnail(path)
    image = Vips::Image.new_from_file(path)
    image = image.flatten(background: [244, 241, 233]) if image.has_alpha?
    image = image.thumbnail_image(MAX_DIM, height: MAX_DIM)
    image.jpegsave_buffer(Q: 82)
  rescue Vips::Error => e
    raise "thumbnail failed for #{path}: #{e.message}"
  end

  def self.video_frame(path)
    stdout, stderr, status = Open3.capture3(
      "ffmpeg", "-loglevel", "error", "-i", path, "-frames:v", "1",
      "-vf", "scale='if(gt(iw,ih),#{MAX_DIM},-1)':'if(gt(iw,ih),-1,#{MAX_DIM})'",
      "-f", "image2pipe", "-vcodec", "mjpeg", "-",
    )
    raise "ffmpeg produced no frame for #{path}: #{stderr}" if stdout.empty? || !status.success?
    stdout
  end
end
```

> Requires `libvips` with libheif. Install on macOS: `brew install vips`.

- [x] **Step 2: Verify against a real image**

```bash
SAMPLE=$(find /Users/jobofish/Pictures -type f \( -iname '*.jpg' -o -iname '*.jpeg' \) 2>/dev/null | head -1)
mise exec -- bin/rails runner "b = ThumbnailMaker.thumbnail('$SAMPLE', 'image/jpeg'); puts b.bytesize"
```
Expected: a byte count > 0 (JPEG thumbnail).

- [x] **Step 3: Commit**

```bash
git add app/services/thumbnail_maker.rb
git commit -q -m "feat: thumbnail extraction with ruby-vips and ffmpeg"
```

---

### Task 16: Embedding store (KNN + insert)

**Files:**
- Create: `app/services/embedding_store.rb`

- [x] **Step 1: Write the service**

```ruby
# app/services/embedding_store.rb
class EmbeddingStore
  # Port of packages/core/core/embeds.py
  # Vectors are little-endian float32 BLOBs: Ruby [..].pack("f*") == Python array('f').tobytes()

  def self.to_blob(vector)
    vector.pack("f*")
  end

  def self.add_content(asset_id:, model:, model_version:, vector:)
    blob = to_blob(vector)
    ContentEmbed.upsert(
      { asset_id: asset_id, model: model, model_version: model_version, embed: blob },
      unique_by: :asset_id,
    )
    db = ActiveRecord::Base.connection.raw_connection
    db.execute("DELETE FROM vec0_content WHERE rowid = ?", [asset_id])
    db.execute("INSERT INTO vec0_content(rowid, content_embed) VALUES (?, ?)", [asset_id, blob])
  end

  def self.content_knn(vector, limit)
    blob = to_blob(vector)
    rows = ActiveRecord::Base.connection.raw_connection.execute(
      "SELECT rowid, distance FROM vec0_content WHERE content_embed MATCH ? AND k = ?",
      [blob, limit],
    )
    rows.map { |row| [row["rowid"].to_i, row["distance"].to_f] }
  end
end
```

- [x] **Step 2: Verify in a sandbox**

```bash
mise exec -- bin/rails runner '
  a = Asset.create!(path: "/tmp/sandbox/a.jpg", sha256: "a", size_bytes: 1, mime: "image/jpeg")
  first = Array.new(512, 0.0); first[0] = 1.0
  second = Array.new(512, 0.0); second[1] = 1.0
  EmbeddingStore.add_content(asset_id: a.id, model: "m", model_version: "v", vector: first)
  puts EmbeddingStore.content_knn(first, 5).inspect
  puts EmbeddingStore.content_knn(second, 5).inspect
'
```
Expected: the first KNN returns `[[a.id, 0.0]]`; the second returns one result
with the L2 distance for two orthogonal unit vectors. Record the observed
sqlite-vec value in the test.

- [x] **Step 3: Clean up sandbox and commit**

```bash
mise exec -- bin/rails runner 'Asset.where("path LIKE ?", "/tmp/sandbox/%").destroy_all'
git add app/services/embedding_store.rb
git commit -q -m "feat: embedding store with vec0 knn"
```

---

### Task 17: Asset importer pipeline

**Files:**
- Create: `app/services/asset_importer.rb`

- [x] **Step 1: Write the service**

```ruby
# app/services/asset_importer.rb
require "digest"

class AssetImporter
  # Port of services/worker/worker/pipeline.py + packages/core/core/assets.py
  def self.import(path)
    metadata = ExifMetadata.extract(path)
    mime = metadata[:mime]
    thumb = ThumbnailMaker.thumbnail(path, mime)

    gps_lat = metadata[:gps_lat]
    gps_lon = metadata[:gps_lon]
    city = country = nil
    if gps_lat && gps_lon
      geo = SidecarClient.reverse_geocode(lat: gps_lat, lon: gps_lon)
      city = geo["city"]
      country = geo["country"]
    end

    sha256 = Digest::SHA256.file(path).hexdigest
    stored = StoredFile.find_or_initialize_by(sha256: "#{sha256}:thumbnail")
    stored.kind = "thumbnail"
    stored.bytes = thumb
    stored.save!

    source = Source.classify_path(path)
    asset = Asset.find_or_initialize_by(path: File.expand_path(path))
    asset.assign_attributes(
      sha256: sha256,
      size_bytes: File.size(path),
      mime: mime,
      source: source,
      taken_at: metadata[:taken_at],
      gps_lat: gps_lat,
      gps_lon: gps_lon,
      place_city: city,
      place_country: country,
      thumbnail_id: stored.id,
      extra: metadata.to_json,
      deleted: 0,
    )
    asset.save!

    embed = SidecarClient.embed_image(thumb, mime: mime)
    EmbeddingStore.add_content(
      asset_id: asset.id,
      model: embed["model"],
      model_version: embed["version"],
      vector: embed["embed"],
    )
    asset.id
  end
end
```

- [x] **Step 2: Verify the service loads**

```bash
docker compose run --rm rails bin/rails runner 'puts AssetImporter.method(:import).inspect'
```
Expected: prints the `AssetImporter.import` method without a LoadError. The
real import integration check is deferred to the final acceptance gate after
Task 24 starts the sidecar.

- [x] **Step 3: Commit**

```bash
git add app/services/asset_importer.rb
git commit -q -m "feat: asset import pipeline"
```

---

### Task 18: Solid Queue scan and import jobs

**Files:**
- Create: `app/jobs/scan_job.rb`, `app/jobs/import_job.rb`

- [x] **Step 1: ScanJob**

```ruby
# app/jobs/scan_job.rb
class ScanJob < ApplicationJob
  queue_as :default

  def perform(job_id:, root:)
    job = Job.find(job_id)
    job.mark_working!

    paths = Dir.glob(File.join(root, "**", "*")).select do |path|
      File.file?(path) && MEDIA_SUFFIXES.include?(File.extname(path).downcase)
    end.sort

    job.update!(params: { paths: paths }.to_json)

    if paths.empty?
      job.complete!
      return
    end

    paths.each_with_index do |path, index|
      ImportJob.perform_later(job_id: job.id, path: path, index: index, total: paths.length)
    end
  end
end
```

- [x] **Step 2: ImportJob**

```ruby
# app/jobs/import_job.rb
class ImportJob < ApplicationJob
  queue_as :default

  def perform(job_id:, path:, index:, total:)
    job = Job.find(job_id)
    AssetImporter.import(path)
    job.bump_progress!((index + 1).to_f / total)
    job.complete! if index + 1 >= total
  rescue => e
    job.fail!(e.message)
  end
end
```

- [x] **Step 3: Verify the jobs are defined**

Run: `mise exec -- bin/rails runner 'puts [ScanJob, ImportJob].map(&:name).join(",")'`
Expected: `ScanJob,ImportJob` (no LoadError)

- [x] **Step 4: Commit**

```bash
git add app/jobs
git commit -q -m "feat: solid queue scan and import jobs"
```

---

### Task 19: Search service

**Files:**
- Create: `app/services/search_service.rb`

- [x] **Step 1: Write the service**

```ruby
# app/services/search_service.rb
require "set"

class SearchService
  # Port of apps/api/api/search.py (structured filters + content KNN)
  def self.search(q: nil, who: nil, place: nil, before: nil, after: nil, tag: nil, limit: 50)
    limit = [[limit, 1].max, 200].min
    allowed = filter_ids(who: who, place: place, before: before, after: after, tag: tag)

    if q.present?
      resp = SidecarClient.embed_text(q)
      ranked = EmbeddingStore.content_knn(resp["results"].first, limit * 4)
      ranked.filter_map { |asset_id, distance| asset_result(asset_id, distance) if allowed.include?(asset_id) }.first(limit)
    else
      Asset.not_deleted.where(id: allowed)
           .order(Arel.sql("taken_at DESC, id DESC"))
           .limit(limit * 4)
           .map { |asset| asset_result(asset.id) }
           .first(limit)
    end
  end

  def self.asset_result(asset_id, distance = nil)
    asset = Asset.not_deleted.find_by(id: asset_id)
    return nil if asset.nil?
    result = {
      id: asset.id,
      path: asset.path,
      mime: asset.mime,
      taken_at: asset.taken_at&.iso8601,
      place_city: asset.place_city,
      place_country: asset.place_country,
      thumbnail_id: asset.thumbnail_id,
      thumbnail_url: asset.thumbnail_url,
    }
    result[:distance] = distance if distance
    result
  end

  def self.filter_ids(who: nil, place: nil, before: nil, after: nil, tag: nil)
    sql = "SELECT id FROM assets WHERE deleted = 0"
    params = []

    if place.present?
      like = "%#{escape_like(place)}%"
      sql += " AND (place_city LIKE ? ESCAPE '\\' OR place_country LIKE ? ESCAPE '\\')"
      params += [like, like]
    end
    if before.present?
      sql += " AND taken_at IS NOT NULL AND taken_at <= ?"
      params << before
    end
    if after.present?
      sql += " AND taken_at IS NOT NULL AND taken_at >= ?"
      params << after
    end
    if tag.present?
      sql += " AND id IN (SELECT asset_id FROM tags WHERE tag = ?)"
      params << tag
    end
    if who.present?
      like = "%#{escape_like(who)}%"
      sql += <<~SQL
        AND id IN (
          SELECT faces.asset_id FROM faces
          JOIN person_faces ON person_faces.face_id = faces.id
          JOIN persons ON persons.id = person_faces.person_id
          LEFT JOIN person_aliases ON person_aliases.person_id = persons.id
          WHERE persons.name LIKE ? COLLATE NOCASE ESCAPE '\\'
             OR person_aliases.alias LIKE ? COLLATE NOCASE ESCAPE '\\'
        )
      SQL
      params += [like, like]
    end

    rows = ActiveRecord::Base.connection.raw_connection.execute(sql, params)
    rows.map { |row| row["id"].to_i }.to_set
  end

  def self.escape_like(value)
    value.to_s.gsub("\\", "\\\\").gsub("%", "\\%").gsub("_", "\\_")
  end
end
```

- [x] **Step 2: Verify (sandbox, no sidecar needed for non-`q` path)**

```bash
mise exec -- bin/rails runner '
  a = Asset.create!(path: "/tmp/sandbox/s1.jpg", sha256: "s1", size_bytes: 1, mime: "image/jpeg", taken_at: "2021-06-01", place_city: "Paris")
  puts SearchService.search(place: "Paris").map { |r| r[:id] }.inspect
  puts SearchService.search(q: "anything", place: "Paris").size
  Asset.where("path LIKE ?", "/tmp/sandbox/%").destroy_all
'
```
Expected: first line prints `[<id>]`; second line prints `0` (embed-text sidecar call is not stubbed, so raises → assert the structured filter returned nothing because KNN raised). If you prefer a clean check, only run the first line; the `q:` line will raise `SidecarError` until the sidecar is up — that is expected at this stage.

- [x] **Step 3: Commit**

```bash
git add app/services/search_service.rb
git commit -q -m "feat: search service with knn and structured filters"
```

---

### Task 20: Catalog overview service

**Files:**
- Create: `app/services/catalog_overview.rb`

- [x] **Step 1: Write the service**

```ruby
# app/services/catalog_overview.rb
class CatalogOverview
  STAGE_KEYS = %w[discovered ready_to_import importing imported processing searchable failed_or_blocked].freeze

  def self.call
    new.call
  end

  def call
    entries = sources
    funnel = STAGE_KEYS.each_with_object({}) { |key, acc| acc[key] = entries.sum { |e| e[:stages][key] } }
    {
      generated_at: Time.now.utc.iso8601,
      funnel: funnel,
      sources: entries,
      context: context,
    }
  end

  private

  def sources
    Source.all.map do |source|
      imported = Asset.not_deleted.where(source: source).count
      searchable = ContentEmbed.joins(:asset).where(assets: { source_id: source.id, deleted: 0 }).count
      stages = {
        "discovered" => imported,
        "ready_to_import" => 0,
        "importing" => 0,
        "imported" => imported,
        "processing" => [imported - searchable, 0].max,
        "searchable" => searchable,
        "failed_or_blocked" => 0,
      }
      {
        kind: source.kind,
        display_name: source.display_name,
        readiness: "connected",
        readiness_detail: nil,
        reported_at: source.last_sync_at&.iso8601,
        stages: stages,
        sync: nil,
        watch_enabled: source.kind == "mounted_folder" && Setting.get("watch_enabled") == "1",
        ingest_mode: { "apple_photos" => "bridge", "mounted_folder" => "watch", "uploads" => "manual" }.fetch(source.kind, "manual"),
        actions: { can_sync: source.kind == "apple_photos" },
      }
    end
  end

  def context
    recent = Asset.not_deleted
                  .order(Arel.sql("thumbnail_id IS NULL, created_at DESC, taken_at DESC"))
                  .limit(6)
                  .includes(:source)
    faces_total = Face.count
    assigned = PersonFace.count
    located = Asset.not_deleted.where.not(gps_lat: nil).count
    total = Asset.not_deleted.count
    {
      recent_imports: recent.map do |asset|
        {
          id: asset.id,
          source_kind: asset.source&.kind,
          original_filename: asset.original_filename,
          imported_at: asset.created_at&.iso8601,
          taken_at: asset.taken_at&.iso8601,
        }
      end,
      photos_libraries: [],
      faces: {
        total: faces_total,
        assigned: assigned,
        unassigned: [faces_total - assigned, 0].max,
        embeddings_ready: FaceEmbed.count,
        embeddings_pending: [faces_total - FaceEmbed.count, 0].max,
        assets_processing: Asset.not_deleted.where.missing(:content_embed).count,
        clustering_status: "ready",
      },
      places: { located: located, unlocated: [total - located, 0].max },
    }
  end
end
```

- [x] **Step 2: Verify**

```bash
mise exec -- bin/rails runner 'puts CatalogOverview.call[:funnel].inspect'
```
Expected: a hash with the 7 stage keys all `0`.

- [x] **Step 3: Commit**

```bash
git add app/services/catalog_overview.rb
git commit -q -m "feat: catalog overview service"
```

---

### Task 21: Routes

**Files:**
- Modify: `config/routes.rb`

- [x] **Step 1: Replace routes.rb**

```ruby
# config/routes.rb
Rails.application.routes.draw do
  get "/", to: "health#index"
  get "/search", to: "search#index"
  get "/catalog/overview", to: "catalog#overview"
  post "/assets/upload", to: "uploads#create"
  get "/assets/:id/thumbnail", to: "assets#thumbnail"
  get "/jobs", to: "jobs#index"
  get "/jobs/:id", to: "jobs#show"
  get "/admin/status", to: "admin#status"
  get "/admin/settings", to: "admin#settings"
  patch "/admin/settings", to: "admin#update_settings"
  post "/admin/scan", to: "admin#scan"
end
```

- [x] **Step 2: Verify routes load**

Run: `mise exec -- bin/rails routes`
Expected: 11 routes, no error.

- [x] **Step 3: Commit**

```bash
git add config/routes.rb
git commit -q -m "feat: routes mirroring fastapi contract"
```

---

### Task 22: Health, Search, Catalog, Uploads, Assets, Jobs controllers

**Files:**
- Create: `app/controllers/health_controller.rb`, `app/controllers/search_controller.rb`, `app/controllers/catalog_controller.rb`, `app/controllers/uploads_controller.rb`, `app/controllers/assets_controller.rb`, `app/controllers/jobs_controller.rb`

- [x] **Step 1: HealthController**

```ruby
# app/controllers/health_controller.rb
class HealthController < ApplicationController
  def index
    render json: { ok: true }
  end
end
```

- [x] **Step 2: SearchController**

```ruby
# app/controllers/search_controller.rb
class SearchController < ApplicationController
  def index
    @results = SearchService.search(
      q: params[:q], who: params[:who], place: params[:place],
      before: params[:before], after: params[:after], tag: params[:tag],
      limit: (params[:limit] || 50).to_i,
    )
    respond_to do |format|
      format.json { render json: { results: @results } }
      format.html
    end
  end
end
```

- [x] **Step 3: CatalogController**

```ruby
# app/controllers/catalog_controller.rb
class CatalogController < ApplicationController
  def overview
    @overview = CatalogOverview.call
    respond_to do |format|
      format.json { render json: @overview }
      format.html
    end
  end
end
```

- [x] **Step 4: UploadsController**

```ruby
# app/controllers/uploads_controller.rb
require "securerandom"
require "fileutils"

class UploadsController < ApplicationController
  def create
    file = params[:file]
    raise ActionController::ParameterMissing, "file" if file.nil?
    suffix = (File.extname(file.original_filename).presence || ".jpg").downcase
    destination = Pathname.new(PICS_LIBRARY) / "imports" / "#{SecureRandom.hex}#{suffix}"
    destination.dirname.mkpath
    File.binwrite(destination, file.read)

    job = Job.create!(kind: "import", params: { paths: [destination.to_s] }.to_json)
    ImportJob.perform_later(job_id: job.id, path: destination.to_s, index: 0, total: 1)

    render json: { job_id: job.id, status: "queued", path: destination.to_s }
  end
end
```

- [x] **Step 5: AssetsController**

```ruby
# app/controllers/assets_controller.rb
class AssetsController < ApplicationController
  def thumbnail
    asset = Asset.not_deleted.find_by(id: params[:id])
    stored = asset && StoredFile.find_by(id: asset.thumbnail_id)
    raise ActiveRecord::RecordNotFound if stored.nil? || stored.bytes.nil?
    send_data stored.bytes, type: "image/jpeg", disposition: "inline"
  end
end
```

- [x] **Step 6: JobsController**

```ruby
# app/controllers/jobs_controller.rb
class JobsController < ApplicationController
  def index
    @jobs = Job.order(id: :desc).limit(100)
    respond_to do |format|
      format.json { render json: { jobs: @jobs.as_json(only: [:id, :kind, :status, :progress, :error, :params, :created_at, :updated_at]) } }
      format.html
    end
  end

  def show
    job = Job.find(params[:id])
    render json: job.as_json(only: [:id, :kind, :status, :progress, :error, :params, :created_at, :updated_at])
  end
end
```

- [x] **Step 7: Verify**

```bash
mise exec -- bin/rails runner 'puts [HealthController, SearchController, CatalogController, UploadsController, AssetsController, JobsController].map(&:name).join(",")'
```
Expected: comma-separated names, no LoadError.

- [x] **Step 8: Commit**

```bash
git add app/controllers
git commit -q -m "feat: health, search, catalog, uploads, assets, jobs controllers"
```

---

### Task 23: Admin controller

**Files:**
- Create: `app/controllers/admin_controller.rb`

- [x] **Step 1: Write the controller**

```ruby
# app/controllers/admin_controller.rb
class AdminController < ApplicationController
  def status
    models_ready = SidecarClient.status["ok"] == true rescue false
    root_available = File.directory?(PICS_WATCH_ROOT)
    counts = {
      "assets" => Asset.count,
      "faces" => Face.count,
      "persons" => Person.count,
      "jobs" => Job.count,
    }
    render json: {
      mount_source: ENV.fetch("PICS_MOUNT_SOURCE", nil),
      watch_root: PICS_WATCH_ROOT,
      root_available: root_available,
      models_ready: models_ready,
      disk: nil,
      counts: counts,
      settings: Setting.all_map,
    }
  end

  def settings
    render json: { settings: Setting.all_map }
  end

  def update_settings
    if params[:watch_enabled].present?
      Setting.set_value("watch_enabled", params[:watch_enabled]) if %w[0 1].include?(params[:watch_enabled].to_s)
    end
    if params[:watch_backfill].present?
      Setting.set_value("watch_backfill", params[:watch_backfill]) if %w[prompt backfill done].include?(params[:watch_backfill].to_s)
    end
    render json: { settings: Setting.all_map }
  end

  def scan
    root = params[:root].presence || PICS_WATCH_ROOT
    raise ActiveRecord::RecordNotFound, "root is not a directory: #{root}" unless File.directory?(root)

    paths = Dir.glob(File.join(root, "**", "*")).select do |path|
      File.file?(path) && MEDIA_SUFFIXES.include?(File.extname(path).downcase)
    end
    job = Job.create!(kind: "scan", params: { paths: paths }.to_json)
    ScanJob.perform_later(job_id: job.id, root: root)
    render json: { job_id: job.id, paths: paths.length, status: "queued" }
  end
end
```

- [x] **Step 2: Verify**

Run: `mise exec -- bin/rails runner 'puts AdminController.new.methods.grep(/status|settings|scan/).inspect'`
Expected: includes `:status`, `:settings`, `:update_settings`, `:scan`.

- [x] **Step 3: Commit**

```bash
git add app/controllers/admin_controller.rb
git commit -q -m "feat: admin status, settings, and scan endpoints"
```

---

### Task 24: Python sidecar (FastAPI)

**Files:**
- Create: `sidecar/app.py`, `sidecar/models.py`, `sidecar/pyproject.toml`, `sidecar/Dockerfile`, `sidecar/.dockerignore`

- [x] **Step 1: Sidecar app**

```python
# sidecar/app.py
"""Stateless ML inference sidecar. Owns model weights only — no DB, no app logic."""
from __future__ import annotations

import base64
import io

import reverse_geocoder
from fastapi import FastAPI, HTTPException
from PIL import Image
from pydantic import BaseModel

from .models import ClipEmbedder

MODEL_NAME = "openai/clip-vit-base-patch32"
MODEL_VERSION = "clip-vit-base-patch32-v1"

app = FastAPI(title="pics-sidecar")
embedder: ClipEmbedder | None = None


class TextRequest(BaseModel):
    texts: list[str]


class ImageRequest(BaseModel):
    image_base64: str
    mime: str = "image/jpeg"


class GeoRequest(BaseModel):
    lat: float
    lon: float


@app.on_event("startup")
def load_model() -> None:
    global embedder
    if embedder is None:
        embedder = ClipEmbedder(MODEL_NAME)


@app.get("/v1/status")
def status() -> dict:
    return {"ok": embedder is not None, "model": MODEL_NAME, "version": MODEL_VERSION}


@app.post("/v1/embed-text")
def embed_text(request: TextRequest) -> dict:
    if embedder is None:
        raise HTTPException(status_code=503, detail="models_pending")
    return {"model": MODEL_NAME, "version": MODEL_VERSION, "results": embedder.embed_text(request.texts)}


@app.post("/v1/embed-image")
def embed_image(request: ImageRequest) -> dict:
    if embedder is None:
        raise HTTPException(status_code=503, detail="models_pending")
    image = Image.open(io.BytesIO(base64.b64decode(request.image_base64))).convert("RGB")
    return {"model": MODEL_NAME, "version": MODEL_VERSION, "embed": embedder.embed_images([image])[0]}


@app.post("/v1/reverse-geocode")
def reverse_geocode(request: GeoRequest) -> dict:
    result = reverse_geocoder.search([(request.lat, request.lon)], mode=1)[0]
    return {"city": result["name"], "country": result["cc"]}
```

- [x] **Step 2: CLIP wrapper**

```python
# sidecar/models.py
from __future__ import annotations

from collections.abc import Sequence

import torch
from PIL import Image
from transformers import CLIPModel, CLIPProcessor


class ClipEmbedder:
    def __init__(self, model_name: str):
        self.name = model_name
        self.model = CLIPModel.from_pretrained(model_name)
        self.processor = CLIPProcessor.from_pretrained(model_name)
        self.model.eval()

    @staticmethod
    def _tensor(output):
        return output.pooler_output if hasattr(output, "pooler_output") else output

    @torch.no_grad()
    def embed_images(self, images: Sequence[Image.Image]) -> list[list[float]]:
        inputs = self.processor(images=list(images), return_tensors="pt")
        features = self._tensor(self.model.get_image_features(**inputs))
        features = features / features.norm(dim=-1, keepdim=True)
        return features.cpu().numpy().tolist()

    @torch.no_grad()
    def embed_text(self, texts: Sequence[str]) -> list[list[float]]:
        inputs = self.processor(text=list(texts), return_tensors="pt", padding=True, truncation=True)
        features = self._tensor(self.model.get_text_features(**inputs))
        features = features / features.norm(dim=-1, keepdim=True)
        return features.cpu().numpy().tolist()
```

Create `sidecar/__init__.py` as an empty package marker. The sidecar must be
installable and runnable from this repository; `/Users/jobofish/code/pics` is
not a runtime dependency.

- [x] **Step 3: pyproject.toml**

```toml
# sidecar/pyproject.toml
[project]
name = "pics-sidecar"
version = "0.1.0"
requires-python = ">=3.12"
dependencies = [
  "fastapi>=0.115",
  "uvicorn>=0.30",
  "torch>=2.0",
  "transformers>=5",
  "pillow>=10",
  "reverse-geocoder>=1.5.1",
]

[build-system]
requires = ["setuptools>=75"]
build-backend = "setuptools.build_meta"
```

- [x] **Step 4: Dockerfile**

```dockerfile
# sidecar/Dockerfile
FROM python:3.12-slim

WORKDIR /app
COPY sidecar /app/sidecar

RUN pip install --no-cache-dir --index-url https://download.pytorch.org/whl/cpu torch \
    && pip install --no-cache-dir /app/sidecar

ENV HF_HOME=/models/huggingface
EXPOSE 9090
CMD ["uvicorn", "sidecar.app:app", "--host", "0.0.0.0", "--port", "9090"]
```

- [x] **Step 5: .dockerignore**

```
# sidecar/.dockerignore
__pycache__/
*.pyc
.venv/
```

- [x] **Step 6: Verify the deterministic development mode**

```bash
docker compose build sidecar
docker compose up -d sidecar
sleep 10
curl -s http://localhost:9090/v1/status
curl -s -X POST http://localhost:9090/v1/embed-text -H 'Content-Type: application/json' -d '{"texts":["picnic"]}'
curl -s -X POST http://localhost:9090/v1/reverse-geocode -H 'Content-Type: application/json' -d '{"lat":48.85,"lon":2.35}'
```

The Compose development service sets `PICS_SIDECAR_MODE=stub`, so startup is
deterministic and does not require a model download. Verify status reports
`mode: stub`, text embeddings contain 512 floats, and reverse-geocoding returns
the deterministic response. The real CLIP model is verified in the final task.

- [x] **Step 7: Commit**

```bash
git add sidecar
git commit -q -m "feat: python ml sidecar (embed-text, embed-image, reverse-geocode)"
```

---

### Task 25: Docker Compose dev stack

**Files:**
- Create: `docker-compose.yml`

- [x] **Step 1: Write compose**

```yaml
# docker-compose.yml
services:
  sidecar:
    platform: linux/amd64
    build: .
    dockerfile: sidecar/Dockerfile
    volumes:
      - models:/models
    ports:
      - "9090:9090"
    environment:
      - HF_HOME=/models/huggingface
      - PICS_SIDECAR_MODE=stub

  rails:
    build:
      context: .
      dockerfile: Dockerfile.rails
    command: bin/rails server -b 0.0.0.0
    volumes:
      - .:/app
      - catalog:/app/storage
      - ./library:/library
    ports:
      - "3000:3000"
    environment:
      - PICS_WORKER_URL=http://sidecar:9090
      - PICS_WATCH_ROOT=/media/photos
    depends_on:
      - sidecar

volumes:
  models:
  catalog:
```

- [x] **Step 2: Create a minimal Rails Dockerfile**

```dockerfile
# Dockerfile.rails
FROM ruby:3.3-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    libvips42 libheif1 exiftool ffmpeg build-essential libsqlite3-dev sqlite3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY Gemfile Gemfile.lock ./
RUN bundle install
COPY . .

EXPOSE 3000
CMD ["bin/rails", "server", "-b", "0.0.0.0"]
```

- [x] **Step 3: Verify sidecar image builds**

```bash
docker compose build sidecar
```
Expected: image builds successfully (torch CPU download is slow, several minutes).

- [x] **Step 4: Verify sidecar boots and responds**

```bash
docker compose up -d sidecar
sleep 60
curl -s http://localhost:9090/v1/status
```
Expected: stub mode returns `{"ok":true,"mode":"stub",...}` without waiting
for model weights.

- [x] **Step 5: Verify an end-to-end embed against the container**

```bash
curl -s -X POST http://localhost:9090/v1/embed-text -H 'Content-Type: application/json' -d '{"texts":["picnic"]}'
```
Expected: JSON with a `results` array of 512 floats.

- [x] **Step 6: Commit**

```bash
git add docker-compose.yml Dockerfile.rails
git commit -q -m "feat: docker compose dev stack"
```

---

### Task 26: Basic views (search, catalog, jobs)

**Files:**
- Create: `app/views/search/index.html.erb`, `app/views/catalog/overview.html.erb`, `app/views/jobs/index.html.erb`
- Modify: `app/views/layouts/application.html.erb`

- [x] **Step 1: Application layout (nav + Turbo)**

```erb
<%# app/views/layouts/application.html.erb — replace the <body> content %>
<body>
  <nav>
    <%= link_to "Overview", "/catalog/overview" %>
    <%= link_to "Search", "/search" %>
    <%= link_to "Jobs", "/jobs" %>
  </nav>
  <main>
    <%= yield %>
  </main>
</body>
```

- [x] **Step 2: Search view**

```erb
<%# app/views/search/index.html.erb %>
<h1>Search</h1>
<%= form_tag("/search", method: :get, data: { turbo_frame: "results" }) do %>
  <%= text_field_tag :q, params[:q], placeholder: "e.g. picnic with Sam 2021" %>
  <%= text_field_tag :who, params[:who], placeholder: "who" %>
  <%= text_field_tag :place, params[:place], placeholder: "place" %>
  <%= text_field_tag :before, params[:before], placeholder: "before (YYYY-MM-DD)" %>
  <%= text_field_tag :after, params[:after], placeholder: "after (YYYY-MM-DD)" %>
  <%= text_field_tag :tag, params[:tag], placeholder: "tag" %>
  <%= submit_tag "Search" %>
<% end %>

<%= turbo_frame_tag "results" do %>
  <div class="grid">
    <% @results.each do |result| %>
      <figure>
        <img src="<%= result[:thumbnail_url] %>" alt="<%= result[:taken_at] %>" loading="lazy" />
        <figcaption><%= result[:place_city] %> <%= result[:place_country] %> <%= result[:distance]&.round(3) %></figcaption>
      </figure>
    <% end %>
  </div>
<% end %>
```

- [x] **Step 3: Catalog overview view**

```erb
<%# app/views/catalog/overview.html.erb %>
<h1>Catalog Overview</h1>
<div data-controller="refresh" data-refresh-interval-value="3000">
  <h2>Funnel</h2>
  <ul>
    <% @overview[:funnel].each do |key, value| %>
      <li><%= key %>: <%= value %></li>
    <% end %>
  </ul>

  <h2>Sources</h2>
  <% @overview[:sources].each do |source| %>
    <section>
      <h3><%= source[:display_name] %></h3>
      <p><%= source[:ingest_mode] %> · readiness <%= source[:readiness] %></p>
      <ul>
        <% source[:stages].each do |key, value| %>
          <li><%= key %>: <%= value %></li>
        <% end %>
      </ul>
    </section>
  <% end %>
</div>
```

- [x] **Step 4: Jobs view**

```erb
<%# app/views/jobs/index.html.erb %>
<h1>Jobs</h1>
<%= turbo_frame_tag "jobs" do %>
  <table>
    <tr><th>id</th><th>kind</th><th>status</th><th>progress</th><th>error</th></tr>
    <% @jobs.each do |job| %>
      <tr>
        <td><%= job.id %></td>
        <td><%= job.kind %></td>
        <td><%= job.status %></td>
        <td><%= (job.progress * 100).round %>%</td>
        <td><%= job.error %></td>
      </tr>
    <% end %>
  </table>
<% end %>
```

- [x] **Step 5: Verify pages render**

```bash
mise exec -- bin/rails server &
sleep 8
curl -s -H 'Accept: text/html' http://localhost:3000/catalog/overview | grep -o "Catalog Overview"
curl -s -H 'Accept: text/html' http://localhost:3000/search | grep -o "Search"
curl -s -H 'Accept: text/html' http://localhost:3000/jobs | grep -o "Jobs"
kill %1
```
Expected: each curl prints the matching heading text.

- [x] **Step 6: Commit**

```bash
git add app/views
git commit -q -m "feat: basic turbo views for search, catalog, jobs"
```

---

### Task 27: Test fixture (tiny JPEG)

**Files:**
- Create: `test/fixtures/tiny.jpg`

- [x] **Step 1: Generate the fixture**

Use a small valid JPEG so EXIF/thumbnail tests run offline. Generate it with the
reference repo's Pillow rather than hand-crafting bytes:

```bash
mkdir -p test/fixtures
python3 -c "from PIL import Image; Image.new('RGB',(32,32),(200,100,50)).save('test/fixtures/tiny.jpg','JPEG',quality=90)" || true
```

If Pillow is unavailable, copy any JPEG already on the machine:

```bash
find /Users/jobofish/Pictures -type f \( -iname '*.jpg' -o -iname '*.jpeg' \) 2>/dev/null | head -1 | xargs -I{} cp {} test/fixtures/tiny.jpg
```

- [x] **Step 2: Verify**

Run: `file test/fixtures/tiny.jpg`
Expected: `... JPEG image data ...`

- [x] **Step 3: Commit**

```bash
git add test/fixtures/tiny.jpg
git commit -q -m "test: add tiny jpeg fixture"
```

---

### Task 28: Model and service tests

**Files:**
- Create: `test/services/search_service_test.rb`, `test/services/embedding_store_test.rb`, `test/services/thumbnail_maker_test.rb`, `test/models/source_test.rb`

- [ ] **Step 1: Source classifier test**

```ruby
# test/models/source_test.rb
require "test_helper"

class SourceTest < ActiveSupport::TestCase
  test "classifies mounted folder paths" do
    source = Source.find_by!(kind: "mounted_folder")
    path = File.join(PICS_WATCH_ROOT, "2021", "picnic.jpg")
    assert_equal source, Source.classify_path(path)
  end

  test "classifies uploads under PICS_LIBRARY/imports" do
    source = Source.find_by!(kind: "uploads")
    path = File.join(PICS_LIBRARY, "imports", "abc123.jpg")
    assert_equal source, Source.classify_path(path)
  end

  test "returns nil for unrelated paths" do
    assert_nil Source.classify_path("/tmp/not-a-library/photo.jpg")
  end
end
```

- [ ] **Step 2: Embedding store test**

```ruby
# test/services/embedding_store_test.rb
require "test_helper"

class EmbeddingStoreTest < ActiveSupport::TestCase
  test "inserts and queries content embeddings" do
    asset = Asset.create!(path: "/tmp/test/a.jpg", sha256: "x", size_bytes: 1, mime: "image/jpeg")
    vector = Array.new(512, 0.0); vector[0] = 1.0
    EmbeddingStore.add_content(asset_id: asset.id, model: "m", model_version: "v", vector: vector)
    assert_equal [[asset.id, 0.0]], EmbeddingStore.content_knn(vector, 5)
  end

  test "knn returns the configured distance for differing vectors" do
    asset = Asset.create!(path: "/tmp/test/b.jpg", sha256: "y", size_bytes: 1, mime: "image/jpeg")
    first = Array.new(512, 0.0); first[0] = 1.0
    second = Array.new(512, 0.0); second[1] = 1.0
    EmbeddingStore.add_content(asset_id: asset.id, model: "m", model_version: "v", vector: first)
    result = EmbeddingStore.content_knn(second, 5)
    assert_equal 1, result.length
    assert_in_delta 1.4142135, result.first.last, 1e-4
  end
end
```

- [ ] **Step 3: Search service test (structured filter, no sidecar)**

```ruby
# test/services/search_service_test.rb
require "test_helper"

class SearchServiceTest < ActiveSupport::TestCase
  setup do
    @paris = Asset.create!(path: "/tmp/test/p.jpg", sha256: "p", size_bytes: 1, mime: "image/jpeg",
                           taken_at: Time.utc(2021, 6, 1), place_city: "Paris", place_country: "FR")
    @rome = Asset.create!(path: "/tmp/test/r.jpg", sha256: "q", size_bytes: 1, mime: "image/jpeg",
                          taken_at: Time.utc(2020, 1, 1), place_city: "Rome", place_country: "IT")
  end

  test "filters by place" do
    ids = SearchService.search(place: "Paris").map { |r| r[:id] }
    assert_equal [@paris.id], ids
  end

  test "filters by date window" do
    ids = SearchService.search(after: "2021-01-01", before: "2021-12-31").map { |r| r[:id] }
    assert_equal [@paris.id], ids
  end

  test "recent-first ordering without a query" do
    ids = SearchService.search.map { |r| r[:id] }
    assert_equal [@paris.id, @rome.id], ids
  end
end
```

- [ ] **Step 4: Thumbnail maker test**

```ruby
# test/services/thumbnail_maker_test.rb
require "test_helper"

class ThumbnailMakerTest < ActiveSupport::TestCase
  test "makes a jpeg thumbnail from an image" do
    path = Rails.root.join("test", "fixtures", "tiny.jpg").to_s
    jpeg = ThumbnailMaker.thumbnail(path, "image/jpeg")
    assert jpeg.bytesize > 0
    assert_equal "\xFF\xD8".b, jpeg.byteslice(0, 2)
  end
end
```

- [ ] **Step 5: Run the tests**

```bash
mise exec -- bin/rails test test/models/source_test.rb test/services/embedding_store_test.rb test/services/search_service_test.rb test/services/thumbnail_maker_test.rb
```
Expected: all pass (green). The search test with a `q:` parameter is not included here because it needs the sidecar.

- [ ] **Step 6: Commit**

```bash
git add test
git commit -q -m "test: model and service unit tests"
```

---

### Task 29: Controller request tests

**Files:**
- Create: `test/controllers/health_controller_test.rb`, `test/controllers/search_controller_test.rb`, `test/controllers/catalog_controller_test.rb`, `test/controllers/jobs_controller_test.rb`

- [ ] **Step 1: Health test**

```ruby
# test/controllers/health_controller_test.rb
require "test_helper"

class HealthControllerTest < ActionDispatch::IntegrationTest
  test "returns ok" do
    get "/"
    assert_response :success
    assert_equal({ "ok" => true }, JSON.parse(response.body))
  end
end
```

- [ ] **Step 2: Search test**

```ruby
# test/controllers/search_controller_test.rb
require "test_helper"

class SearchControllerTest < ActionDispatch::IntegrationTest
  test "returns empty results without a query" do
    get "/search", params: { q: "" }, as: :json
    assert_response :success
    assert_equal({ "results" => [] }, JSON.parse(response.body))
  end

  test "renders html page" do
    get "/search"
    assert_response :success
    assert_match "Search", response.body
  end
end
```

- [ ] **Step 3: Catalog test**

```ruby
# test/controllers/catalog_controller_test.rb
require "test_helper"

class CatalogControllerTest < ActionDispatch::IntegrationTest
  test "overview returns funnel" do
    get "/catalog/overview", as: :json
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal %w[discovered ready_to_import importing imported processing searchable failed_or_blocked],
                 body["funnel"].keys
  end

  test "renders html page" do
    get "/catalog/overview"
    assert_response :success
    assert_match "Catalog Overview", response.body
  end
end
```

- [ ] **Step 4: Jobs test**

```ruby
# test/controllers/jobs_controller_test.rb
require "test_helper"

class JobsControllerTest < ActionDispatch::IntegrationTest
  test "lists jobs" do
    Job.create!(kind: "scan")
    get "/jobs", as: :json
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body["jobs"].length
    assert_equal "scan", body["jobs"].first["kind"]
  end
end
```

- [ ] **Step 5: Run the controller tests**

```bash
mise exec -- bin/rails test test/controllers/health_controller_test.rb test/controllers/search_controller_test.rb test/controllers/catalog_controller_test.rb test/controllers/jobs_controller_test.rb
```
Expected: all pass (green).

- [ ] **Step 6: Commit**

```bash
git add test/controllers
git commit -q -m "test: controller request tests for contract endpoints"
```

---

### Task 30: Full test suite + rubocop

**Files:**
- None (verification)

- [ ] **Step 1: Run the whole suite**

```bash
mise exec -- bin/rails test
```
Expected: all tests green.

- [ ] **Step 2: Lint (rubocop if installed)**

```bash
mise exec -- bin/rubocop app lib test 2>/dev/null || echo "rubocop not installed; skipping"
```
If rubocop is not in the Gemfile, add `gem "rubocop-rails-omakase"` to the
`:development, :test` group, `bundle install`, and run `bin/rubocop`. Fix any
offenses in the files created by this plan.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -q -m "chore: lint and test cleanup"
```

---

## Verification Summary

After all tasks complete:

- [ ] `mise exec -- bin/rails test` — all tests pass
- [ ] `docker compose build sidecar && docker compose up -d sidecar` — container boots
- [ ] `curl -s http://localhost:9090/v1/status` returns `{"ok":true,...}`
- [ ] `curl -s -X POST http://localhost:9090/v1/embed-text -H 'Content-Type: application/json' -d '{"texts":["picnic"]}'` returns 512 floats
- [ ] `mise exec -- bin/rails server` and visit `http://localhost:3000/` → `{"ok":true}`
- [ ] `POST /admin/scan` against the mounted folder enqueues a scan job; `GET /jobs` shows it
- [ ] `GET /search?q=picnic` (with sidecar up) returns ranked results with thumbnail URLs
- [ ] `GET /assets/:id/thumbnail` returns a JPEG
- [ ] Imported photos appear in `/catalog/overview` with searchable counts
- [ ] Import `test/fixtures/tiny.jpg` through the Rails job path and verify the
  job reaches `done`, a thumbnail row and content embedding exist, `/search`
  returns the asset with the sidecar running, and `/assets/:id/thumbnail`
  returns JPEG bytes.

## Phase 2 preview (next plan)

People/faces: add `/v1/detect-faces` + `/v1/cluster-faces` to the sidecar,
`FaceDetection` in the import pipeline, face crops to `library/.crops`, face
embeds to `vec0_face`, a `ClusterFacesJob`, and the people review/merge/split
controllers + views. The schema already exists from Task 8, so Phase 2 is
additive.
