---
title: Kamal and Thruster Production Deploy — Implementation Plan
tags:
  - plan
  - kamal-thruster-deploy
  - kamal
  - thruster
  - production
  - docker
created: 2026-09-29
---

# Kamal + Thruster Production Deploy — Implementation Plan

*Created: 2026-09-29*

**Goal:** Make the Rails app deployable with Kamal behind Thruster, verified
entirely against local Docker execution (build + run + smoke test). The
`docker compose` dev workflow is untouched; no server is provisioned and nothing
is deployed remotely.

**Architecture:** The stock production `Dockerfile` (Thruster → Puma, non-root,
jemalloc, `db:prepare` entrypoint) is kept with one native-dep alignment. One
Kamal app `photo_searchable_library_rails` runs a web role (Solid Queue in-Puma)
plus a `sidecar` accessory. Persistent volumes for `storage/` (4 SQLite DBs),
`library/`, and the sidecar `models/`. Local verification uses the compose
sidecar (stub mode) via `host.docker.internal`.

**Tech Stack:** Rails 8.1, Kamal 2.12, Thruster 0.1.26, Docker/BuildKit, GitHub
Actions, SQLite + sqlite-vec (amd64 platform tags).

**Source:** `kamal-thruster-deploy-design.md` (this dir).

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `Dockerfile` | Modify (build stage apt-get) | Add `libsqlite3-dev` to match the proven dev-image dependency set |
| `config/deploy.yml` | Modify | Real env (PICS_*), library volume, `/up` healthcheck, sidecar accessory |
| `.github/workflows/ci.yml` | Modify | Add `docker-build` job that builds the production image |
| `script/prod-smoke.sh` | Create | Repeatable local build'n'run smoke harness |
| `db/cache_migrate/001_create_solid_cache_tables.rb` | Create (contingency only) | Create cache table if the gate proves `db:prepare` skips cache |
| `artifacts/.../kamal-thruster-deploy/kamal-thruster-deploy-plan.md` | Create | This plan |

---

## Tasks

### Task 1: Align the production Dockerfile build stage with the dev image

The dev image (`Dockerfile.rails`) installs `build-essential git libsqlite3-dev
sqlite3` and compiles the full bundle. The production build stage installs
`build-essential git libvips libyaml-dev pkg-config` — no `libsqlite3-dev`.
`sqlite3`/`sqlite-vec` native extensions may compile from source, so add the
headers to the production build stage.

**Files:**
- Modify: `Dockerfile` (build stage apt-get line)

- [x] **Step 1: Add `libsqlite3-dev` to the build stage**

Find this block in `Dockerfile`:

```dockerfile
# Install packages needed to build gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libvips libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives
```

Replace it with:

```dockerfile
# Install packages needed to build gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libsqlite3-dev libvips libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives
```

- [x] **Step 2: Verify the image builds**

Run:
```bash
docker build --platform linux/amd64 -t photo_searchable_library_rails .
```
Expected: build succeeds through `bundle install` (gems compiled, including
`sqlite3` and `sqlite-vec`), `bootsnap precompile`, and
`assets:precompile`. If the build fails, capture the failing gem — do not
continue to Task 2 until the build is green.

- [x] **Step 3: Commit**

```bash
git add Dockerfile
git commit -m "build: add libsqlite3-dev to production build stage"
```

---

### Task 2: Wire production env, library volume, and proxy healthcheck

**Files:**
- Modify: `config/deploy.yml`

- [x] **Step 1: Add PICS_* env vars**

In `config/deploy.yml`, find:

```yaml
  clear:
    # Run the Solid Queue Supervisor inside the web server's Puma process to do jobs.
    # When you start using multiple servers, you should split out job processing to a dedicated machine.
    SOLID_QUEUE_IN_PUMA: true
```

Replace it with:

```yaml
  clear:
    # Run the Solid Queue Supervisor inside the web server's Puma process to do jobs.
    # When you start using multiple servers, you should split out job processing to a dedicated machine.
    SOLID_QUEUE_IN_PUMA: true

    # Pics application configuration.
    PICS_WORKER_URL: http://sidecar:9090
    PICS_LIBRARY: /rails/library
    PICS_SIDECAR_MODE: real
    PICS_MODEL: openai/clip-vit-base-patch32
    PICS_MODEL_VERSION: clip-vit-base-patch32-v1
    PICS_FACE_MODEL: buffalo_l
```

- [x] **Step 2: Add the library volume**

Find:

```yaml
volumes:
  - "photo_searchable_library_rails_storage:/rails/storage"
```

Replace with:

```yaml
volumes:
  - "photo_searchable_library_rails_storage:/rails/storage"
  - "photo_searchable_library_rails_library:/rails/library"
```

- [x] **Step 3: Add the proxy healthcheck**

Find:

```yaml
asset_path: /rails/public/assets
```

Replace with:

```yaml
asset_path: /rails/public/assets

# Kamal proxy healthcheck; Rails exposes this route in config/routes.rb.
proxy:
  healthcheck:
    path: /up
```

- [x] **Step 4: Verify config loads**

Run:
```bash
bin/kamal config 2>&1 | head -40
```
Expected: prints the resolved config including `PICS_WORKER_URL:
http://sidecar:9090`, both volumes, and `proxy.healthcheck.path: /up`. No YAML
or validation errors. Kamal's proxy performs the healthcheck against the
Thruster-served application.

- [x] **Step 5: Commit**

```bash
git add config/deploy.yml
git commit -m "feat: wire production env, library volume, and healthcheck"
```

---

### Task 3: Add the prebuilt sidecar accessory

**Files:**
- Modify: `config/deploy.yml`

- [x] **Step 1: Append the accessory block**

Find the commented accessory example at the bottom of `config/deploy.yml`:

```yaml
# Use accessory services (secrets come from .kamal/secrets).
# accessories:
#   db:
```

Replace it with an active block (keep the trailing sample comment lines
below it as-is, or remove them — the block below is the source of truth):

```yaml
# Use accessory services (secrets come from .kamal/secrets).
accessories:
  sidecar:
    image: photo_searchable_library_rails_sidecar
    registry:
      server: localhost:5555
    host: 192.168.0.1
    port: "9090:9090"
    env:
      clear:
        HF_HOME: /models/huggingface
        INSIGHTFACE_ROOT: /models/insightface
        PICS_SIDECAR_MODE: real
        PICS_MODEL: openai/clip-vit-base-patch32
        PICS_MODEL_VERSION: clip-vit-base-patch32-v1
        PICS_FACE_MODEL: buffalo_l
    volumes:
      - photo_searchable_library_rails_models:/models
```

Kamal 2.12 accessories reference prebuilt images and do not accept `builder` or
`healthcheck` keys. Build and publish the accessory image separately from the
Rails image, then manage it with `bin/kamal accessory boot sidecar`.

- [x] **Step 2: Build the accessory image**

Run:
```bash
docker build --platform linux/amd64 -f sidecar/Dockerfile -t photo_searchable_library_rails_sidecar .
```
Expected: the sidecar image builds successfully.

- [x] **Step 3: Verify config loads with the accessory**

Run:
```bash
bin/kamal config 2>&1 | head -60
```
Expected: prints the resolved config with an `accessories` entry whose name is
`sidecar`, image `photo_searchable_library_rails_sidecar`, host `192.168.0.1`,
port `9090:9090`, and the `models` volume. No unknown-key error.

- [x] **Step 4: Commit**

```bash
git add config/deploy.yml
git commit -m "feat: add ml sidecar as a kamal accessory"
```

---

### Task 4: Add the CI docker-build job

**Files:**
- Modify: `.github/workflows/ci.yml`

- [x] **Step 1: Append the job**

In `.github/workflows/ci.yml`, after the closing `name: test` job block (at the
end of the file), append a new job:

```yaml
  docker-build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v6

      - name: Build Rails production image
        run: docker build --platform linux/amd64 -t photo_searchable_library_rails:ci .

      - name: Build sidecar image
        run: docker build --platform linux/amd64 -f sidecar/Dockerfile -t photo_searchable_library_rails_sidecar:ci .
```

This runs natively on `linux/amd64` and only builds — it pushes nothing.

- [x] **Step 2: Verify the workflow parses**

Run:
```bash
ruby -ryaml -e "YAML.load_file('.github/workflows/ci.yml'); puts 'workflow yaml ok'"
```
Expected: prints `workflow yaml ok`.

- [x] **Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: build the production image on prs and main"
```

---

### Task 5: Create the local smoke harness

**Files:**
- Create: `script/prod-smoke.sh`

- [x] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# Local production-image smoke test (no deploy). Builds the Rails image, runs
# it against the compose stub sidecar, and verifies boot, import, and search.
set -euo pipefail

IMAGE="photo_searchable_library_rails"
CONTAINER="pics-prod-smoke"
PORT="${PICS_SMOKE_PORT:-8080}"

echo "==> Building production image"
docker build --platform linux/amd64 -t "$IMAGE" .

echo "==> Ensuring the dev sidecar is up (stub mode)"
docker compose up -d sidecar

docker volume create psr_storage >/dev/null 2>&1 || true
docker volume create psr_library >/dev/null 2>&1 || true

echo "==> Starting production container on :$PORT"
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
docker run -d --name "$CONTAINER" \
  --platform linux/amd64 \
  -p "$PORT:80" \
  --add-host=host.docker.internal:host-gateway \
  -e RAILS_MASTER_KEY="$(cat config/master.key)" \
  -e PICS_WORKER_URL=http://host.docker.internal:9090 \
  -e SOLID_QUEUE_IN_PUMA=true \
  -v psr_storage:/rails/storage \
  -v psr_library:/rails/library \
  "$IMAGE"

echo "==> Waiting for /up"
for i in $(seq 1 60); do
  if curl -fsS "http://localhost:$PORT/up" >/dev/null 2>&1; then
    echo "    up after ${i}s"
    break
  fi
  sleep 1
  if [ "$i" = 60 ]; then
    echo "FAIL: /up never returned 200"
    docker logs "$CONTAINER" --tail 50
    exit 1
  fi
done

echo "==> /catalog/overview"
curl -fsS -H "Accept: application/json" "http://localhost:$PORT/catalog/overview" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print('    sources:', [s['kind'] for s in d['sources']])"

echo "==> Upload test/fixtures/tiny.jpg"
RESP=$(curl -fsS -F "file=@test/fixtures/tiny.jpg;type=image/jpeg" "http://localhost:$PORT/assets/upload")
echo "$RESP"
JOB_ID=$(echo "$RESP" | python3 -c "import json,sys; print(json.load(sys.stdin)['job_id'])")

echo "==> Waiting for import job $JOB_ID"
for i in $(seq 1 60); do
  STATUS=$(curl -fsS "http://localhost:$PORT/jobs/$JOB_ID" \
    | python3 -c "import json,sys; print(json.load(sys.stdin)['status'])")
  if [ "$STATUS" = "done" ]; then
    echo "    done after ${i}s"
    break
  fi
  if [ "$STATUS" = "error" ]; then
    echo "FAIL: import job errored"
    docker logs "$CONTAINER" --tail 50
    exit 1
  fi
  sleep 1
  if [ "$i" = 60 ]; then
    echo "FAIL: import job timed out"
    docker logs "$CONTAINER" --tail 50
    exit 1
  fi
done

echo "==> Verify thumbnail serves"
ASSET_ID=$(curl -fsS -H "Accept: application/json" "http://localhost:$PORT/catalog/overview" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['context']['recent_imports'][0]['id'])")
curl -fsS -o /tmp/pics-smoke-thumb.jpg -w "    thumbnail HTTP %{http_code}\n" \
  "http://localhost:$PORT/assets/$ASSET_ID/thumbnail"

echo "==> Cleanup"
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
docker volume rm psr_storage psr_library >/dev/null 2>&1 || true
echo "SMOKE OK"
```

- [x] **Step 2: Make it executable and syntax-check**

Run:
```bash
chmod +x script/prod-smoke.sh
bash -n script/prod-smoke.sh
```
Expected: `bash -n` exits 0 (no syntax errors) and prints nothing.

- [x] **Step 3: Commit**

```bash
git add script/prod-smoke.sh
git commit -m "chore: local production-image smoke harness"
```

---

### Task 6: Run the acceptance gate locally

**Files:**
- Modify: `script/prod-smoke.sh` if the gate exposes request-format issues
- Modify: `app/views/catalog/_overview.html.erb` if background catalog broadcasts
  expose an implicit partial lookup

- [x] **Step 1: Run the smoke harness**

Before rerunning after a failed attempt, remove the prior smoke container and
volumes:

```bash
docker rm -f pics-prod-smoke >/dev/null 2>&1 || true
docker volume rm psr_storage psr_library >/dev/null 2>&1 || true
```

Run:
```bash
script/prod-smoke.sh
```
Expected, in order:
1. `docker build` succeeds.
2. Sidecar starts via compose.
3. Container boots; `/up` returns 200 within 60s.
4. `/catalog/overview` prints `sources: ['apple_photos', 'mounted_folder', 'uploads']`.
5. Upload returns a `job_id`.
6. The import job reaches `done`.
7. The thumbnail URL returns HTTP 200 and `/tmp/pics-smoke-thumb.jpg` is a JPEG.
8. Final line: `SMOKE OK`.

- [x] **Step 2: Confirm all four production databases were created**

Run:
```bash
docker run --rm -v psr_storage:/rails/storage -v psr_library:/rails/library --entrypoint ls photo_searchable_library_rails /rails/storage
```
Expected: lists `production.sqlite3`, `production_cache.sqlite3`,
`production_queue.sqlite3`, `production_cable.sqlite3` (plus sqlite WAL/journal
files). If `production_cache.sqlite3` is missing, `db:prepare` did not prepare
the cache database — proceed to Task 7.

- [x] **Step 3: Confirm the entrypoint ran migrations, not a bare boot**

Run:
```bash
docker logs pics-prod-smoke 2>&1 | head -20
```
Expected: migration/prepare output and a Puma/Thruster startup line. No
"Can't connect" or "ActiveRecord::NoDatabaseError" errors.

- [x] **Step 4: Confirm `bin/kamal config` is stable end to end**

Run:
```bash
bin/kamal config > /tmp/kamal-config.yml 2>/dev/null && wc -l /tmp/kamal-config.yml
```
Expected: prints a line count > 0 and exit 0.

---

### Task 7 (contingency): Create the cache migration if the gate skipped it

Not needed: Task 6 Step 2 confirmed that `production_cache.sqlite3` is created
by the existing production `db:prepare` flow.

**Files:**
- Create: `db/cache_migrate/001_create_solid_cache_tables.rb`

- [x] **Step 1: Create the migration** (not applicable; cache database created)

`db/cache_schema.rb` is a schema dump, not a migration — mirror the existing
`db/queue_migrate/001_create_solid_queue_tables.rb` pattern:

```ruby
# db/cache_migrate/001_create_solid_cache_tables.rb
class CreateSolidCacheTables < ActiveRecord::Migration[8.1]
  def change
    load Rails.root.join("db/cache_schema.rb")
    execute "DELETE FROM schema_migrations WHERE version = '1'"
  end
end
```

- [x] **Step 2: Verify the cache database is created on boot** (verified in Task 6)

Rerun `script/prod-smoke.sh`, then Task 6 Step 2 again.
Expected: `production_cache.sqlite3` now appears in `/rails/storage`.

- [x] **Step 3: Commit** (not applicable; no migration needed)

```bash
git add db/cache_migrate/001_create_solid_cache_tables.rb
git commit -m "fix: create solid cache tables for production prepare"
```

---

### Task 8: Commit plan state

- [x] **Step 1: Record the plan**

```bash
git add artifacts/photo-searchable-library-rails/kamal-thruster-deploy/kamal-thruster-deploy-plan.md
git commit -m "chore: record kamal thruster deploy plan"
```

---

## Verification Summary

- [x] `docker build --platform linux/amd64 -t photo_searchable_library_rails .` succeeds (Task 1/6)
- [x] `bin/kamal config` parses `deploy.yml` with PICS env, both volumes,
      `/up` healthcheck, and the `sidecar` accessory (Tasks 2/3/6)
- [x] `.github/workflows/ci.yml` parses as YAML and gains a `docker-build` job
      (Task 4)
- [x] `script/prod-smoke.sh` passes: boot, `/up`, catalog JSON, upload → import
      done → thumbnail JPEG (Task 6)
- [x] `storage/` contains all four production DBs after boot (Task 6; or
      Task 7 if cache was skipped)
- [x] Dev workflow untouched — `docker compose` files unchanged (Tasks 1–8)
