---
title: Phase 4 — Apple Photos Bridge Protocol Implementation Plan
tags:
  - plan
  - apple-photos-bridge
  - phase-4
  - rails
  - hotwire
created: 2026-09-24
---

# Phase 4 — Apple Photos Bridge Protocol Implementation Plan

*Created: 2026-09-24*

**Goal:** Implement the `/sources/apple-photos/*` HTTP contract on the Rails
app so the existing Swift PhotoKit bridge can drive Apple Photos ingestion into
the Rails catalog — plus the catalog-overview apple entry, the `/admin/library`
inventory walk, and the Photos-page Apple source card.

**Architecture:** The Swift bridge (`apps/photos-bridge` in the reference repo)
is unchanged — it only speaks HTTP. Rails recreates the FastAPI
`apps/api/api/sources.py` contract: a `source_syncs` state machine
(queued → running → done/partial/error) with lease-based stale recovery, a
bridge heartbeat that expires to `offline` after a short lease, a full-sync
dedupe endpoint, a multipart asset upload that lands files in
`library/apple-photos/{uuid}.{suffix}` and reuses the existing `ImportJob`, and
the catalog-overview apple entry fed by a TTL-cached watch-root inventory walk.
The schema already exists (Phase 1) — no migrations.

**Tech Stack:** Rails 8.1, Active Record + SQLite, Solid Queue, Turbo Streams,
Minitest.

**Source:** `apple-photos-bridge-discovery.md` (this dir); reference
`/Users/jobofish/code/pics` — `apps/api/api/sources.py`, `apps/api/api/catalog.py`,
`apps/api/api/admin.py`, `apps/photos-bridge/Sources/PicsPhotosBridge/main.swift`,
tests `apps/api/tests/test_sync.py`, `test_sources.py`, `test_full_sync.py`.

**Key contract facts the executor must not drift from:** `source_asset_id`
contains `/` and is a **form field**, never a route segment; `claim`/`complete`
are form-encoded, `sync`/`known`/`heartbeat` are JSON; `complete` maps
`error && imported_count>0 → partial`, `error alone → error`, else `done`;
`asset_count == 0` means `inventory_pending`, not empty.

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `config/initializers/pics.rb` | Modify | Add `PICS_SOURCE_SYNC_LEASE_SECONDS`, `PICS_BRIDGE_LEASE_SECONDS`, `PICS_INVENTORY_CACHE_TTL` |
| `app/models/source_sync.rb` | Modify | Broadcast the catalog overview region on create/update |
| `app/services/apple_photos_bridge.rb` | Create | Bridge protocol: sync/claim/complete/heartbeat/known/ingest + serializers |
| `app/controllers/apple_photos_controller.rb` | Create | The 8 bridge endpoints |
| `config/routes.rb` | Modify | `/sources/apple-photos/*` + `/admin/library` |
| `app/jobs/import_job.rb` | Modify | Only delete `uploads` originals on import failure; never apple-photos |
| `app/services/library_inventory.rb` | Create | TTL-cached watch-root walk: media files, extensions, photos libraries |
| `app/controllers/admin_controller.rb` | Modify | `library` action |
| `app/services/catalog_overview.rb` | Replace | Per-kind entries with real funnel/readiness/sync + `photos_libraries` context |
| `app/helpers/application_helper.rb` | Modify | `bridge_label`, `readiness_label`, `freshness_label`, `sync_active?`, badge updates |
| `app/views/catalog/_source_card.html.erb` | Replace | Apple Photos card: bridge states, sync controls, how-to-connect |
| `app/views/catalog/_overview.html.erb` | Modify | Pass `photos_libraries` + `sync` locals to the source card |
| `test/controllers/apple_photos_controller_test.rb` | Create | Tests for all 8 endpoints |
| `test/models/source_sync_test.rb` | Create | Broadcast-enqueue test |
| `test/jobs/import_job_test.rb` | Create | Delete-guard test |
| `test/services/library_inventory_test.rb` | Create | Walk + prune test |
| `test/controllers/admin_controller_test.rb` | Modify | `/admin/library` test |
| `test/controllers/catalog_controller_test.rb` | Modify | Apple funnel/readiness tests |
| `test/test_helper.rb` | Modify | Clear the inventory cache in `setup` |

---

## Tasks

### Task 1: Phase 4 environment constants

**Files:**
- Modify: `config/initializers/pics.rb`

- [x] **Step 1: Append the three new constants**

```ruby
# config/initializers/pics.rb — append after MEDIA_SUFFIXES
PICS_SOURCE_SYNC_LEASE_SECONDS = Integer(ENV.fetch("PICS_SOURCE_SYNC_LEASE_SECONDS", 3600))
PICS_BRIDGE_LEASE_SECONDS = Integer(ENV.fetch("PICS_BRIDGE_LEASE_SECONDS", 15))
PICS_INVENTORY_CACHE_TTL = Float(ENV.fetch("PICS_INVENTORY_CACHE_TTL", 60))
```

- [x] **Step 2: Verify**

Run:
```bash
mise exec -- bin/rails runner 'puts [PICS_SOURCE_SYNC_LEASE_SECONDS, PICS_BRIDGE_LEASE_SECONDS, PICS_INVENTORY_CACHE_TTL].inspect'
```
Expected: `[3600, 15, 60.0]`.

- [x] **Step 3: Commit**

```bash
git add config/initializers/pics.rb
git commit -q -m "feat: apple photos bridge lease and inventory constants"
```

---

### Task 2: SourceSync broadcasts the catalog overview

The bridge (not a job) advances sync state, so the Photos page must update
live. Broadcasting from the model — exactly like `ImportJob` does — re-renders
the `#catalog_overview` region on the `"catalog"` stream whenever a sync is
created or changes state.

**Files:**
- Modify: `app/models/source_sync.rb`
- Create: `test/models/source_sync_test.rb`

- [x] **Step 1: Replace the model**

```ruby
# app/models/source_sync.rb
class SourceSync < ApplicationRecord
  belongs_to :source

  after_create_commit :broadcast_catalog
  after_update_commit :broadcast_catalog

  private

  def broadcast_catalog
    Turbo::StreamsChannel.broadcast_replace_later_to "catalog",
      target: "catalog_overview",
      partial: "catalog/overview",
      locals: { overview: CatalogOverview.call }
  end
end
```

- [x] **Step 2: Write the broadcast test**

```ruby
# test/models/source_sync_test.rb
require "test_helper"

class SourceSyncTest < ActiveSupport::TestCase
  test "sync create enqueues a catalog overview broadcast" do
    apple = Source.find_by!(kind: "apple_photos")
    assert_enqueued_with(job: Turbo::Streams::ActionBroadcastJob) do
      SourceSync.create!(source: apple, limit_count: 25, full_sync: 0)
    end
  end
end
```

- [x] **Step 3: Verify**

Run: `mise exec -- bin/rails test test/models/source_sync_test.rb`
Expected: 1 run, 0 failures, 0 errors.

- [x] **Step 4: Commit**

```bash
git add app/models/source_sync.rb test/models/source_sync_test.rb
git commit -q -m "feat: broadcast catalog overview on source sync changes"
```

---

### Task 3: ApplePhotosBridge service

This service is a port of `apps/api/api/sources.py` plus the serializers used
by the controller and `CatalogOverview`. It is written in full here.

**Files:**
- Create: `app/services/apple_photos_bridge.rb`

- [x] **Step 1: Write the service**

```ruby
# app/services/apple_photos_bridge.rb
require "digest"
require "json"
require "securerandom"

class ApplePhotosBridge
  def self.source
    Source.find_by!(kind: "apple_photos")
  end

  def self.library_root
    Pathname.new(PICS_LIBRARY)
  end

  def self.sync_request(limit: 25, full: false)
    src = source
    recover_stale!(src)
    active = src.source_syncs.where(status: %w[queued running]).order(id: :desc).first
    return { sync: active, already_active: true } if active

    sync = src.source_syncs.create!(limit_count: limit.clamp(1, 500), full_sync: full ? 1 : 0)
    { sync: sync, already_active: false }
  end

  def self.sync_status
    src = source
    recover_stale!(src)
    { sync: src.source_syncs.order(id: :desc).first }
  end

  def self.claim
    src = source
    recover_stale!(src)
    sync = src.source_syncs.where(status: "queued").order(:id).first
    return { sync: nil } if sync.nil?

    sync.update!(status: "running", started_at: Time.current)
    { sync: sync.reload }
  end

  def self.complete(sync_id, imported_count: 0, failed_count: 0, error: nil)
    sync = SourceSync.find(sync_id)
    imported_count = imported_count.to_i
    failed_count = failed_count.to_i
    status = if error.present?
               imported_count.positive? ? "partial" : "error"
             else
               "done"
             end
    sync.update!(
      status: status,
      completed_at: Time.current,
      imported_count: imported_count,
      failed_count: failed_count,
      error: error
    )
    { sync: sync }
  end

  def self.recover_stale!(src)
    cutoff = Time.current - PICS_SOURCE_SYNC_LEASE_SECONDS
    src.source_syncs.where(status: "running").where("started_at < ?", cutoff).update_all(
      status: "error", error: "bridge lease expired", completed_at: Time.current
    )
  end

  def self.heartbeat(authorization_state:, asset_count:)
    src = source
    bridge_status = if %w[denied restricted notDetermined].include?(authorization_state.to_s)
                      "authorization_required"
                    elsif asset_count.to_i.zero?
                      "inventory_pending"
                    else
                      "connected"
                    end
    src.update!(
      bridge_status: bridge_status,
      bridge_last_seen_at: Time.current,
      authorization_state: authorization_state,
      asset_count: asset_count.to_i
    )
    { source: source_with_bridge_status }
  end

  def self.source_with_bridge_status
    src = source
    if src.bridge_last_seen_at.nil? || (Time.current - src.bridge_last_seen_at) > PICS_BRIDGE_LEASE_SECONDS
      src.bridge_status = "offline"
    end
    src
  end

  def self.known(source_asset_ids)
    ids = Array(source_asset_ids).first(500)
    found = source.assets.not_deleted.where(source_asset_id: ids).pluck(:source_asset_id)
    { source_asset_ids: found }
  end

  def self.ingest(file:, source_asset_id:, original_filename: nil, media_type: nil, taken_at: nil, authorization_state: nil, asset_count: nil)
    src = source
    existing = src.assets.not_deleted.find_by(source_asset_id: source_asset_id)
    if existing && File.file?(existing.path)
      mark_connected!(src, authorization_state, asset_count)
      if existing.content_embed.present? || active_import_for?(existing.path)
        return { status: "duplicate", duplicate: true, asset_id: existing.id, source_asset_id: source_asset_id }
      end
      job = queue_import(existing.path)
      return { status: "queued", duplicate: true, retried: true, asset_id: existing.id, job_id: job.id, source_asset_id: source_asset_id, path: existing.path }
    end

    suffix = File.extname(original_filename.presence || file.original_filename.to_s).downcase
    suffix = ".jpg" if suffix.blank?
    destination = library_root.join("apple-photos", "#{SecureRandom.hex}#{suffix}")
    destination.dirname.mkpath
    file.tempfile.rewind
    File.open(destination, "wb") { |output| IO.copy_stream(file.tempfile, output) }

    asset = src.assets.find_or_initialize_by(source_asset_id: source_asset_id)
    asset.assign_attributes(
      original_filename: original_filename.presence || file.original_filename,
      path: destination.to_s,
      sha256: Digest::SHA256.file(destination).hexdigest,
      size_bytes: File.size(destination),
      mime: file.content_type.presence || "application/octet-stream",
      taken_at: taken_at,
      deleted: 0
    )
    asset.save!
    job = queue_import(destination.to_s)
    mark_connected!(src, authorization_state, asset_count)
    { status: "queued", duplicate: false, asset_id: asset.id, job_id: job.id, source_asset_id: source_asset_id, path: destination.to_s }
  end

  def self.mark_connected!(src, authorization_state, asset_count)
    src.update!(
      status: "connected",
      authorization_state: authorization_state,
      asset_count: asset_count.nil? ? src.asset_count : asset_count.to_i,
      last_error: nil,
      last_sync_at: Time.current
    )
  end

  def self.queue_import(path)
    job = Job.create!(kind: "import", params: { paths: [ path ] }.to_json)
    ImportJob.perform_later(job_id: job.id, path: path, index: 0, total: 1)
    job
  end

  def self.active_import_for?(path)
    Job.where(kind: "import", status: %w[queued working]).find_each do |job|
      return true if JSON.parse(job.params || "{}").dig("paths").to_a.include?(path)
    end
    false
  end

  def self.sync_json(sync)
    return nil if sync.nil?

    {
      id: sync.id,
      source_id: sync.source_id,
      status: sync.status,
      limit_count: sync.limit_count,
      full_sync: sync.full_sync,
      requested_at: sync.created_at&.iso8601,
      started_at: sync.started_at&.iso8601,
      completed_at: sync.completed_at&.iso8601,
      imported_count: sync.imported_count,
      failed_count: sync.failed_count,
      error: sync.error
    }
  end

  def self.source_json(source)
    {
      id: source.id,
      kind: source.kind,
      display_name: source.display_name,
      status: source.status,
      authorization_state: source.authorization_state,
      bridge_status: source.bridge_status,
      bridge_last_seen_at: source.bridge_last_seen_at&.iso8601,
      last_sync_at: source.last_sync_at&.iso8601,
      last_error: source.last_error,
      asset_count: source.asset_count,
      imported_count: source.imported_count,
      watch_enabled: false,
      ingest_mode: "bridge"
    }
  end
end
```

- [x] **Step 2: Verify the service loads and a sync round-trips**

Run:
```bash
mise exec -- bin/rails runner 'result = ApplePhotosBridge.sync_request(limit: 5); puts result[:sync].status; puts ApplePhotosBridge.claim[:sync].status; ApplePhotosBridge.complete(result[:sync].id, imported_count: 5); puts SourceSync.last.status'
```
Expected output:
```
queued
running
done
```

- [x] **Step 3: Commit**

```bash
git add app/services/apple_photos_bridge.rb
git commit -q -m "feat: apple photos bridge sync and ingest service"
```

---

### Task 4: ApplePhotosController + routes

**Files:**
- Create: `app/controllers/apple_photos_controller.rb`
- Modify: `config/routes.rb`

- [x] **Step 1: Write the controller**

```ruby
# app/controllers/apple_photos_controller.rb
class ApplePhotosController < ApplicationController
  def status
    source = ApplePhotosBridge.source_with_bridge_status
    imported = source.assets.not_deleted.joins(:content_embed).count
    render json: { source: ApplePhotosBridge.source_json(source).merge(imported_count: imported) }
  end

  def sync
    result = ApplePhotosBridge.sync_request(
      limit: (params[:limit] || 25).to_i,
      full: params[:full] == true || params[:full].to_s == "true" || params[:full].to_s == "1"
    )
    if request.format.html?
      notice = result[:already_active] ? "An Apple Photos import is already in progress." : "Apple Photos import queued."
      redirect_to "/catalog/overview", notice: notice
    else
      render json: { sync: ApplePhotosBridge.sync_json(result[:sync]), already_active: result[:already_active] }
    end
  end

  def sync_status
    render json: { sync: ApplePhotosBridge.sync_json(ApplePhotosBridge.sync_status[:sync]) }
  end

  def claim
    render json: { sync: ApplePhotosBridge.sync_json(ApplePhotosBridge.claim[:sync]) }
  end

  def complete
    result = ApplePhotosBridge.complete(
      params[:id],
      imported_count: params[:imported_count],
      failed_count: params[:failed_count],
      error: params[:error]
    )
    render json: { sync: ApplePhotosBridge.sync_json(result[:sync]) }
  end

  def known
    render json: ApplePhotosBridge.known(params[:source_asset_ids])
  end

  def heartbeat
    result = ApplePhotosBridge.heartbeat(
      authorization_state: params[:authorization_state],
      asset_count: params[:asset_count]
    )
    render json: { source: ApplePhotosBridge.source_json(result[:source]) }
  end

  def ingest
    file = params.require(:file)
    source_asset_id = params.require(:source_asset_id)
    result = ApplePhotosBridge.ingest(
      file: file,
      source_asset_id: source_asset_id,
      original_filename: params[:original_filename],
      media_type: params[:media_type],
      taken_at: params[:taken_at],
      authorization_state: params[:authorization_state],
      asset_count: params[:asset_count]
    )
    render json: result
  end
end
```

- [x] **Step 2: Add the routes**

```ruby
# config/routes.rb — add inside the routes.draw block, before the railties health route
  get "/sources/apple-photos/status", to: "apple_photos#status"
  post "/sources/apple-photos/sync", to: "apple_photos#sync"
  get "/sources/apple-photos/sync/status", to: "apple_photos#sync_status"
  post "/sources/apple-photos/sync/claim", to: "apple_photos#claim"
  post "/sources/apple-photos/sync/:id/complete", to: "apple_photos#complete"
  post "/sources/apple-photos/assets/known", to: "apple_photos#known"
  post "/sources/apple-photos/bridge/heartbeat", to: "apple_photos#heartbeat"
  post "/sources/apple-photos/assets", to: "apple_photos#ingest"
  get "/admin/library", to: "admin#library"
```

- [x] **Step 3: Verify routes load**

Run: `mise exec -- bin/rails routes | grep "apple-photos"`
Expected: the 8 `apple-photos` routes above (plus `/admin/library`).

- [x] **Step 4: Commit**

```bash
git add app/controllers/apple_photos_controller.rb config/routes.rb
git commit -q -m "feat: apple photos bridge controller and routes"
```

---

### Task 5: Sync protocol tests

**Files:**
- Create: `test/controllers/apple_photos_controller_test.rb` (sync half)

- [x] **Step 1: Write the sync protocol tests**

```ruby
# test/controllers/apple_photos_controller_test.rb
require "test_helper"

class ApplePhotosControllerTest < ActionDispatch::IntegrationTest
  test "sync request returns a queued sync" do
    post "/sources/apple-photos/sync", params: { limit: 3 }, as: :json
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "queued", body["sync"]["status"]
    assert_equal false, body["already_active"]
    assert_equal 3, body["sync"]["limit_count"]
  end

  test "sync request with full flag records full_sync" do
    post "/sources/apple-photos/sync", params: { full: true }, as: :json
    assert_equal 1, JSON.parse(response.body)["sync"]["full_sync"]
  end

  test "does not queue a second active sync" do
    post "/sources/apple-photos/sync", params: { limit: 2 }, as: :json
    first = JSON.parse(response.body)["sync"]
    post "/sources/apple-photos/sync", params: { limit: 4 }, as: :json
    body = JSON.parse(response.body)
    assert_equal true, body["already_active"]
    assert_equal first["id"], body["sync"]["id"]
  end

  test "claim marks the sync running and is not reusable" do
    post "/sources/apple-photos/sync", params: { limit: 2 }, as: :json
    first = JSON.parse(response.body)["sync"]
    post "/sources/apple-photos/sync/claim"
    body = JSON.parse(response.body)
    assert_equal "running", body["sync"]["status"]
    assert_equal first["id"], body["sync"]["id"]

    post "/sources/apple-photos/sync/claim"
    assert_nil JSON.parse(response.body)["sync"]
  end

  test "complete finishes a sync" do
    post "/sources/apple-photos/sync", params: { limit: 3 }, as: :json
    sync_id = JSON.parse(response.body)["sync"]["id"]
    post "/sources/apple-photos/sync/#{sync_id}/complete", params: { imported_count: "3" }
    body = JSON.parse(response.body)
    assert_equal "done", body["sync"]["status"]
    assert_equal 3, body["sync"]["imported_count"]
  end

  test "complete reports partial when some failed" do
    post "/sources/apple-photos/sync", params: { limit: 3 }, as: :json
    sync_id = JSON.parse(response.body)["sync"]["id"]
    post "/sources/apple-photos/sync/#{sync_id}/complete",
      params: { imported_count: "2", failed_count: "1", error: "one asset failed" }
    assert_equal "partial", JSON.parse(response.body)["sync"]["status"]
  end

  test "complete reports error when nothing imported" do
    post "/sources/apple-photos/sync", params: { limit: 3 }, as: :json
    sync_id = JSON.parse(response.body)["sync"]["id"]
    post "/sources/apple-photos/sync/#{sync_id}/complete",
      params: { failed_count: "1", error: "bridge error" }
    assert_equal "error", JSON.parse(response.body)["sync"]["status"]
  end

  test "stale running sync is recovered on the next request" do
    post "/sources/apple-photos/sync", params: { limit: 2 }, as: :json
    old_id = JSON.parse(response.body)["sync"]["id"]
    post "/sources/apple-photos/sync/claim"
    SourceSync.find(old_id).update_column(:started_at, 3.hours.ago)

    post "/sources/apple-photos/sync", params: { limit: 2 }, as: :json
    body = JSON.parse(response.body)
    assert_equal false, body["already_active"]
    assert_not_equal old_id, body["sync"]["id"]
    assert_equal "error", SourceSync.find(old_id).status
    assert_equal "bridge lease expired", SourceSync.find(old_id).error
  end

  test "sync status returns the latest sync" do
    post "/sources/apple-photos/sync", params: { limit: 5 }, as: :json
    sync_id = JSON.parse(response.body)["sync"]["id"]
    get "/sources/apple-photos/sync/status", headers: { "ACCEPT" => "application/json" }
    assert_equal sync_id, JSON.parse(response.body)["sync"]["id"]
  end

  test "html sync request redirects to the overview" do
    post "/sources/apple-photos/sync", params: { limit: 25 }, headers: { "ACCEPT" => "text/html" }
    assert_response :redirect
    assert_redirected_to "/catalog/overview"
  end
end
```

- [x] **Step 2: Verify**

Run: `mise exec -- bin/rails test test/controllers/apple_photos_controller_test.rb`
Expected: 10 runs, 0 failures, 0 errors.

- [x] **Step 3: Commit**

```bash
git add test/controllers/apple_photos_controller_test.rb
git commit -q -m "feat: apple photos sync protocol tests"
```

---

### Task 6: Heartbeat, status, known, and ingest tests

**Files:**
- Modify: `test/controllers/apple_photos_controller_test.rb` (append)

- [x] **Step 1: Append the endpoint tests**

```ruby
# test/controllers/apple_photos_controller_test.rb — append inside the class, after the last test
  test "status returns defaults for an unconfigured source" do
    get "/sources/apple-photos/status", headers: { "ACCEPT" => "application/json" }
    body = JSON.parse(response.body)
    assert_equal "apple_photos", body["source"]["kind"]
    assert_equal "offline", body["source"]["bridge_status"]
  end

  test "heartbeat reports authorization required" do
    post "/sources/apple-photos/bridge/heartbeat",
      params: { authorization_state: "notDetermined", asset_count: 0 }, as: :json
    assert_equal "authorization_required", JSON.parse(response.body)["source"]["bridge_status"]
  end

  test "heartbeat reports connected and records totals" do
    post "/sources/apple-photos/bridge/heartbeat",
      params: { authorization_state: "authorized", asset_count: 8105 }, as: :json
    body = JSON.parse(response.body)
    assert_equal "connected", body["source"]["bridge_status"]
    assert_equal 8105, body["source"]["asset_count"]
    assert_not_nil body["source"]["bridge_last_seen_at"]
  end

  test "bridge status becomes offline after the lease" do
    Source.find_by!(kind: "apple_photos").update!(bridge_status: "connected", bridge_last_seen_at: 1.day.ago)
    get "/sources/apple-photos/status", headers: { "ACCEPT" => "application/json" }
    assert_equal "offline", JSON.parse(response.body)["source"]["bridge_status"]
  end

  test "known returns only existing source asset ids" do
    apple = Source.find_by!(kind: "apple_photos")
    Asset.create!(path: "/tmp/apple/1.jpg", sha256: "k1", size_bytes: 1, mime: "image/jpeg",
      source: apple, source_asset_id: "ABC/L0/001")
    post "/sources/apple-photos/assets/known",
      params: { source_asset_ids: [ "ABC/L0/001", "missing" ] }, as: :json
    assert_equal [ "ABC/L0/001" ], JSON.parse(response.body)["source_asset_ids"]
  end

  test "ingest writes the file, upserts the asset, and queues an import" do
    tmpdir = Dir.mktmpdir
    original = ApplePhotosBridge.method(:library_root)
    ApplePhotosBridge.define_singleton_method(:library_root) { Pathname.new(tmpdir) }
    upload = Rack::Test::UploadedFile.new(Rails.root.join("test/fixtures/tiny.jpg"), "image/jpeg")

    assert_difference "Job.count" do
      post "/sources/apple-photos/assets", params: {
        file: upload,
        source_asset_id: "ABC/L0/001",
        original_filename: "IMG_0001.JPG",
        media_type: "image",
        authorization_state: "authorized",
        asset_count: "1"
      }
    end
    body = JSON.parse(response.body)
    assert_equal "queued", body["status"]
    assert_equal false, body["duplicate"]
    assert_equal "ABC/L0/001", body["source_asset_id"]
    asset = Asset.find_by!(source_asset_id: "ABC/L0/001")
    assert File.file?(asset.path)
    assert_equal "connected", Source.find_by!(kind: "apple_photos").status

    post "/sources/apple-photos/assets", params: {
      file: Rack::Test::UploadedFile.new(Rails.root.join("test/fixtures/tiny.jpg"), "image/jpeg"),
      source_asset_id: "ABC/L0/001",
      original_filename: "IMG_0001.JPG"
    }
    assert_equal "duplicate", JSON.parse(response.body)["status"]
  ensure
    ApplePhotosBridge.define_singleton_method(:library_root, original) if original
    FileUtils.rm_rf(tmpdir) if tmpdir
  end

  test "ingest retries a previously failed import without re-writing the file" do
    tmpdir = Dir.mktmpdir
    original = ApplePhotosBridge.method(:library_root)
    ApplePhotosBridge.define_singleton_method(:library_root) { Pathname.new(tmpdir) }
    post "/sources/apple-photos/assets", params: {
      file: Rack::Test::UploadedFile.new(Rails.root.join("test/fixtures/tiny.jpg"), "image/jpeg"),
      source_asset_id: "ABC/L0/002",
      original_filename: "IMG_0002.JPG"
    }
    asset = Asset.find_by!(source_asset_id: "ABC/L0/002")
    Job.where(kind: "import").update_all(status: "error")

    assert_difference "Job.count" do
      post "/sources/apple-photos/assets", params: {
        file: Rack::Test::UploadedFile.new(Rails.root.join("test/fixtures/tiny.jpg"), "image/jpeg"),
        source_asset_id: "ABC/L0/002",
        original_filename: "IMG_0002.JPG"
      }
    end
    body = JSON.parse(response.body)
    assert_equal "queued", body["status"]
    assert_equal true, body["duplicate"]
    assert_equal true, body["retried"]
    assert_equal asset.path, body["path"]
  ensure
    ApplePhotosBridge.define_singleton_method(:library_root, original) if original
    FileUtils.rm_rf(tmpdir) if tmpdir
  end
```

- [x] **Step 2: Verify**

Run: `mise exec -- bin/rails test test/controllers/apple_photos_controller_test.rb`
Expected: 17 runs, 0 failures, 0 errors.

- [x] **Step 3: Commit**

```bash
git add test/controllers/apple_photos_controller_test.rb
git commit -q -m "feat: heartbeat status known and ingest tests"
```

---

### Task 7: Do not delete Apple Photos originals on import failure

The current `ImportJob` removes the source file whenever an `import` job fails.
For uploads that is cheap recovery; for Apple Photos the file in
`library/apple-photos/` is the **only** copy of the original. Scope deletion to
`uploads` only.

**Files:**
- Modify: `app/jobs/import_job.rb`
- Create: `test/jobs/import_job_test.rb`

- [x] **Step 1: Guard the deletion**

```ruby
# app/jobs/import_job.rb — replace the rescue block
  rescue StandardError => e
    if job&.kind == "import"
      FileUtils.rm_f(path) if Source.classify_path(path)&.kind == "uploads"
    end
    job&.record_attempt!(total, error: "#{path}: #{e.message}")
    broadcast_catalog if job&.reload&.status == "error"
  end
```

- [x] **Step 2: Write the guard test**

```ruby
# test/jobs/import_job_test.rb
require "test_helper"

class ImportJobTest < ActiveSupport::TestCase
  test "import failure does not delete apple photos originals" do
    path = File.join(PICS_LIBRARY, "apple-photos", "original.jpg")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "original bytes")
    job = Job.create!(kind: "import", params: { paths: [ path ] }.to_json)
    original = AssetImporter.method(:import)
    AssetImporter.define_singleton_method(:import) { |*| raise "worker failed" }

    ImportJob.perform_now(job_id: job.id, path: path, index: 0, total: 1)

    assert File.file?(path)
    assert_equal "error", job.reload.status
  ensure
    AssetImporter.define_singleton_method(:import, original) if original
    FileUtils.rm_f(path)
  end

  test "import failure deletes uploads originals" do
    path = File.join(PICS_LIBRARY, "imports", "upload.jpg")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "upload bytes")
    job = Job.create!(kind: "import", params: { paths: [ path ] }.to_json)
    original = AssetImporter.method(:import)
    AssetImporter.define_singleton_method(:import) { |*| raise "worker failed" }

    ImportJob.perform_now(job_id: job.id, path: path, index: 0, total: 1)

    assert_not File.exist?(path)
    assert_equal "error", job.reload.status
  ensure
    AssetImporter.define_singleton_method(:import, original) if original
    FileUtils.rm_f(path)
  end
end
```

- [x] **Step 3: Verify**

Run: `mise exec -- bin/rails test test/jobs/import_job_test.rb`
Expected: 2 runs, 0 failures, 0 errors.

- [x] **Step 4: Commit**

```bash
git add app/jobs/import_job.rb test/jobs/import_job_test.rb
git commit -q -m "fix: only delete uploads originals on import failure"
```

---

### Task 8: LibraryInventory service

Port of `_library_inventory` + the TTL cache in `admin.py`. Detects
`*.photoslibrary` bundles (pruned from the walk — PhotoKit owns their
contents), counts media files by extension, and caches per watch-root for
`PICS_INVENTORY_CACHE_TTL` seconds.

**Files:**
- Create: `app/services/library_inventory.rb`
- Create: `test/services/library_inventory_test.rb`
- Modify: `test/test_helper.rb`

- [x] **Step 1: Write the service**

```ruby
# app/services/library_inventory.rb
class LibraryInventory
  TTL = PICS_INVENTORY_CACHE_TTL

  @mutex = Mutex.new
  @cache = nil
  @cached_at = nil
  @cache_root = nil
  @cache_wall_at = nil

  class << self
    def call(root = PICS_WATCH_ROOT)
      now = Time.now.to_f
      return @cache if fresh?(now, root)

      @mutex.synchronize do
        return @cache if fresh?(now, root)

        @cache = new.scan(root)
        @cached_at = now
        @cache_root = root
        @cache_wall_at = Time.current
        @cache
      end
    end

    def scanned_at
      @cache_wall_at
    end

    def clear!
      @cache = nil
      @cached_at = nil
      @cache_root = nil
      @cache_wall_at = nil
    end

    private

    def fresh?(now, root)
      @cache && @cached_at && @cache_root == root && (now - @cached_at) <= TTL
    end
  end

  def scan(root)
    @photos_libraries = []
    @extensions = Hash.new(0)
    @media_files = 0
    @directory_errors = []

    unless File.directory?(root)
      return {
        root: root,
        available: false,
        media_files: 0,
        extensions: {},
        photos_libraries: [],
        directory_errors: []
      }
    end

    walk(root)
    {
      root: root,
      available: true,
      media_files: @media_files,
      extensions: @extensions.sort.to_h,
      photos_libraries: @photos_libraries,
      directory_errors: @directory_errors.first(20)
    }
  end

  private

  def walk(dir)
    Dir.children(dir).sort.each do |entry|
      path = File.join(dir, entry)
      if File.directory?(path)
        if entry.end_with?(".photoslibrary")
          @photos_libraries << { name: entry, path: path }
        else
          walk(path)
        end
      elsif File.file?(path)
        suffix = File.extname(path).downcase
        if MEDIA_SUFFIXES.include?(suffix)
          @media_files += 1
          @extensions[suffix] += 1
        end
      end
    rescue Errno::EACCES, Errno::ENOENT => e
      @directory_errors << e.message
    end
  end
end
```

- [x] **Step 2: Write the test**

```ruby
# test/services/library_inventory_test.rb
require "test_helper"

class LibraryInventoryTest < ActiveSupport::TestCase
  test "scans a root and finds photos libraries and media" do
    LibraryInventory.clear!
    dir = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(dir, "Photos Library.photoslibrary", "sub"))
    File.write(File.join(dir, "Photos Library.photoslibrary", "sub", "inside.jpg"), "x")
    FileUtils.mkdir_p(File.join(dir, "vacation"))
    File.write(File.join(dir, "vacation", "picnic.jpg"), "x")
    File.write(File.join(dir, "notes.txt"), "x")

    inventory = LibraryInventory.call(dir)

    assert_equal 1, inventory[:media_files]
    assert_equal ".jpg", inventory[:extensions].keys.first
    assert_equal 1, inventory[:photos_libraries].length
    assert_equal "Photos Library.photoslibrary", inventory[:photos_libraries].first[:name]
    assert_equal true, inventory[:available]
    assert_equal 0, inventory[:directory_errors].length
  ensure
    LibraryInventory.clear!
    FileUtils.rm_rf(dir) if dir
  end

  test "reports an unavailable root" do
    LibraryInventory.clear!
    inventory = LibraryInventory.call(File.join(Dir.tmpdir, "missing-root-#{SecureRandom.hex}"))
    assert_equal false, inventory[:available]
    assert_empty inventory[:photos_libraries]
  ensure
    LibraryInventory.clear!
  end
end
```

- [x] **Step 3: Clear the cache between tests**

```ruby
# test/test_helper.rb — add inside the `setup do` block, before the source seeding
    LibraryInventory.clear!
```

- [x] **Step 4: Verify**

Run: `mise exec -- bin/rails test test/services/library_inventory_test.rb`
Expected: 2 runs, 0 failures, 0 errors.

- [x] **Step 5: Commit**

```bash
git add app/services/library_inventory.rb test/services/library_inventory_test.rb test/test_helper.rb
git commit -q -m "feat: ttl-cached watch root inventory walk"
```

---

### Task 9: Admin library endpoint

**Files:**
- Modify: `app/controllers/admin_controller.rb`
- Modify: `test/controllers/admin_controller_test.rb`

- [x] **Step 1: Add the library action and helpers**

```ruby
# app/controllers/admin_controller.rb — add inside the class, before `private`
  def library
    render json: LibraryInventory.call.merge(catalog: catalog_counts)
  end

# and add inside the existing `private` section
  def catalog_counts
    root = Source.watch_root.expand_path.to_s
    mounted = Asset.not_deleted.where("path LIKE ?", "#{escape_like(root)}#{File::SEPARATOR}%").count
    {
      assets: Asset.not_deleted.count,
      mounted_assets: mounted,
      faces: Face.count
    }
  end

  def escape_like(value)
    value.to_s.gsub("\\", "\\\\").gsub("%", "\\%").gsub("_", "\\_")
  end
```

- [x] **Step 2: Add the test**

```ruby
# test/controllers/admin_controller_test.rb — append inside the class
  test "library returns inventory and catalog counts" do
    get "/admin/library", headers: { "ACCEPT" => "application/json" }
    assert_response :success
    body = JSON.parse(response.body)
    assert_includes body.keys, "available"
    assert_includes body.keys, "photos_libraries"
    assert body["catalog"].key?("assets")
    assert body["catalog"].key?("mounted_assets")
    assert body["catalog"].key?("faces")
  end
```

- [x] **Step 3: Verify**

Run: `mise exec -- bin/rails test test/controllers/admin_controller_test.rb`
Expected: 2 runs, 0 failures, 0 errors.

- [x] **Step 4: Commit**

```bash
git add app/controllers/admin_controller.rb test/controllers/admin_controller_test.rb
git commit -q -m "feat: admin library inventory endpoint"
```

---

### Task 10: CatalogOverview rewrite

Replaces the placeholder per-source math with real entries for
apple_photos / mounted_folder / uploads, the apple funnel and readiness logic,
the `sync` object, and the `photos_libraries` context.

**Files:**
- Replace: `app/services/catalog_overview.rb`
- Modify: `test/controllers/catalog_controller_test.rb`

- [x] **Step 1: Replace the service**

```ruby
# app/services/catalog_overview.rb
require "json"
require "set"

class CatalogOverview
  STAGE_KEYS = %w[discovered ready_to_import importing imported processing searchable failed_or_blocked].freeze

  def self.call
    new.call
  end

  def call
    inventory = LibraryInventory.call
    active = job_paths
    failed = failed_job_counts
    entries = [
      apple_entry(active, failed),
      mounted_entry(inventory, active, failed),
      uploads_entry(active, failed)
    ]
    funnel = STAGE_KEYS.each_with_object({}) { |key, acc| acc[key] = entries.sum { |e| e[:stages][key] } }
    {
      generated_at: Time.now.utc.iso8601,
      funnel: funnel,
      sources: entries,
      context: context(inventory)
    }
  end

  private

  def apple_entry(active, failed)
    src = Source.find_by!(kind: "apple_photos")
    latest_sync = src.source_syncs.order(id: :desc).first
    counts = processing_counts(src.id, active.fetch("apple_photos", Set.new))
    stages = empty_stages
    stages["discovered"] = src.asset_count
    stages["imported"] = counts[:imported]
    stages["ready_to_import"] = [ src.asset_count - counts[:imported], 0 ].max
    if latest_sync && %w[queued running].include?(latest_sync.status)
      stages["importing"] = latest_sync.full_sync == 1 ? stages["ready_to_import"] : [ latest_sync.limit_count, stages["ready_to_import"] ].min
    end
    stages["processing"] = counts[:processing]
    stages["searchable"] = counts[:searchable]
    stages["failed_or_blocked"] = counts[:stuck] +
      (latest_sync && %w[partial error].include?(latest_sync.status) ? latest_sync.failed_count : 0) +
      failed.fetch("apple_photos", 0)
    readiness, detail = readiness_for(src, latest_sync)
    {
      kind: "apple_photos",
      display_name: src.display_name,
      readiness: readiness,
      readiness_detail: detail,
      reported_at: src.last_sync_at&.iso8601,
      stages: stages,
      bridge_status: ApplePhotosBridge.source_with_bridge_status.bridge_status,
      bridge_last_seen_at: src.bridge_last_seen_at&.iso8601,
      authorization_state: src.authorization_state,
      watch_enabled: false,
      ingest_mode: "bridge",
      sync: ApplePhotosBridge.sync_json(latest_sync),
      actions: { can_sync: true }
    }
  end

  def mounted_entry(inventory, active, failed)
    src = Source.find_by!(kind: "mounted_folder")
    available = inventory[:available]
    counts = processing_counts(src.id, active.fetch("mounted_folder", Set.new))
    stages = empty_stages
    stages["discovered"] = available ? inventory[:media_files] : 0
    stages["imported"] = counts[:imported]
    stages["ready_to_import"] = [ stages["discovered"] - counts[:imported], 0 ].max
    stages["importing"] = active.fetch("mounted_folder", Set.new).size
    stages["processing"] = counts[:processing]
    stages["searchable"] = counts[:searchable]
    stages["failed_or_blocked"] = counts[:stuck] + failed.fetch("mounted_folder", 0)
    readiness, detail = available ? [ "connected", nil ] : [ "failed", "watch root is not available: #{inventory[:root]}" ]
    {
      kind: "mounted_folder",
      display_name: src.display_name,
      readiness: readiness,
      readiness_detail: detail,
      reported_at: LibraryInventory.scanned_at&.iso8601,
      stages: stages,
      sync: nil,
      watch_enabled: Setting.get("watch_enabled") == "1",
      ingest_mode: "watch",
      actions: { can_sync: false }
    }
  end

  def uploads_entry(active, failed)
    src = Source.find_by!(kind: "uploads")
    counts = processing_counts(src.id, active.fetch("uploads", Set.new))
    stages = empty_stages
    stages["discovered"] = counts[:imported]
    stages["imported"] = counts[:imported]
    stages["importing"] = active.fetch("uploads", Set.new).size
    stages["processing"] = counts[:processing]
    stages["searchable"] = counts[:searchable]
    stages["failed_or_blocked"] = counts[:stuck] + failed.fetch("uploads", 0)
    {
      kind: "uploads",
      display_name: src.display_name,
      readiness: "connected",
      readiness_detail: nil,
      reported_at: nil,
      stages: stages,
      sync: nil,
      watch_enabled: false,
      ingest_mode: "manual",
      actions: { can_sync: false }
    }
  end

  def readiness_for(src, latest_sync)
    auth = src.authorization_state
    if %w[denied restricted notDetermined].include?(auth)
      return [ "authorization_required", "Photos authorization is #{auth}" ]
    end
    if latest_sync && latest_sync.status == "error"
      return [ "failed", latest_sync.error || "last sync failed" ]
    end
    return [ "failed", src.last_error ] if src.last_error.present?

    if src.status == "not_connected" && src.last_sync_at.nil? && latest_sync.nil?
      return [ "not_configured", nil ]
    end
    if src.asset_count.zero? && !(latest_sync && %w[done partial].include?(latest_sync.status))
      return [ "inventory_pending", "waiting for the bridge to report library totals" ]
    end
    [ "connected", nil ]
  end

  def processing_counts(source_id, active_paths)
    counts = { imported: 0, searchable: 0, processing: 0, stuck: 0 }
    Asset.not_deleted.where(source_id: source_id).find_each do |asset|
      counts[:imported] += 1
      if asset.content_embed.present?
        counts[:searchable] += 1
      elsif active_paths.include?(asset.path)
        counts[:processing] += 1
      else
        counts[:stuck] += 1
      end
    end
    counts
  end

  def job_paths
    job_paths_for(%w[queued working])
  end

  def job_paths_for(statuses)
    result = Hash.new { |h, k| h[k] = Set.new }
    Job.where(kind: %w[import scan], status: statuses).find_each do |job|
      JSON.parse(job.params || "{}").dig("paths").to_a.each do |path|
        kind = Source.classify_path(path)&.kind
        result[kind] << path if kind
      end
    end
    result
  end

  def failed_job_counts
    resolved = job_paths_for(%w[queued working done])
    counts = Hash.new(0)
    counted = Hash.new { |h, k| h[k] = Set.new }
    Job.where(kind: %w[import scan], status: "error").find_each do |job|
      JSON.parse(job.params || "{}").dig("paths").to_a.each do |path|
        kind = Source.classify_path(path)&.kind
        next if kind.nil?
        next if resolved[kind].include?(path)
        next if counted[kind].include?(path)

        counted[kind] << path
        counts[kind] += 1
      end
    end
    counts
  end

  def empty_stages
    STAGE_KEYS.each_with_object({}) { |key, acc| acc[key] = 0 }
  end

  def context(inventory)
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
          taken_at: asset.taken_at&.iso8601
        }
      end,
      photos_libraries: inventory[:photos_libraries],
      faces: {
        total: faces_total,
        assigned: assigned,
        unassigned: [ faces_total - assigned, 0 ].max,
        embeddings_ready: FaceEmbed.count,
        embeddings_pending: [ faces_total - FaceEmbed.count, 0 ].max,
        assets_processing: Asset.not_deleted.where.missing(:content_embed).count,
        clustering_status: "ready"
      },
      places: { located: located, unlocated: [ total - located, 0 ].max }
    }
  end
end
```

- [x] **Step 2: Add overview tests**

```ruby
# test/controllers/catalog_controller_test.rb — append inside the class
  test "apple entry reports bridge inventory and funnel" do
    apple = Source.find_by!(kind: "apple_photos")
    apple.update!(asset_count: 10, bridge_status: "connected",
      bridge_last_seen_at: Time.current, authorization_state: "authorized", status: "connected")
    asset = Asset.create!(
      path: File.join(PICS_LIBRARY, "apple-photos", "a.jpg"),
      sha256: "ap1", size_bytes: 1, mime: "image/jpeg",
      source: apple, source_asset_id: "ABC/L0/1", deleted: 0
    )
    ContentEmbed.create!(asset: asset, model: "m", model_version: "v", embed: Array.new(512, 0.0).pack("f*"))

    get "/catalog/overview", headers: { "ACCEPT" => "application/json" }
    body = JSON.parse(response.body)
    apple_entry = body["sources"].find { |s| s["kind"] == "apple_photos" }
    assert_equal "connected", apple_entry["readiness"]
    assert_equal 10, apple_entry["stages"]["discovered"]
    assert_equal 1, apple_entry["stages"]["imported"]
    assert_equal 9, apple_entry["stages"]["ready_to_import"]
    assert_equal 1, apple_entry["stages"]["searchable"]
    assert_equal true, apple_entry["actions"]["can_sync"]
  end

  test "mounted folder reports failed when the watch root is unavailable" do
    get "/catalog/overview", headers: { "ACCEPT" => "application/json" }
    body = JSON.parse(response.body)
    mounted = body["sources"].find { |s| s["kind"] == "mounted_folder" }
    assert_equal "failed", mounted["readiness"]
    assert_includes mounted["readiness_detail"], "watch root is not available"
  end
```

- [x] **Step 3: Verify**

Run: `mise exec -- bin/rails test test/controllers/catalog_controller_test.rb`
Expected: 4 runs, 0 failures, 0 errors.

- [x] **Step 4: Commit**

```bash
git add app/services/catalog_overview.rb test/controllers/catalog_controller_test.rb
git commit -q -m "feat: real apple photos funnel and readiness in catalog overview"
```

---

### Task 11: View helpers for bridge labels and freshness

**Files:**
- Modify: `app/helpers/application_helper.rb`

- [x] **Step 1: Update the badge helpers and add label helpers**

Replace `source_badge_class` and `source_badge_label`, and add the new methods:

```ruby
# app/helpers/application_helper.rb — replace the two existing methods and add these
  def source_badge_class(source)
    if source[:kind] == "apple_photos"
      case source[:bridge_status]
      when "connected" then "badge badgeOk"
      when "authorization_required" then "badge badgeWarn"
      else "badge badgeMuted"
      end
    elsif source[:ingest_mode] == "manual"
      "badge badgeMuted"
    elsif source[:ingest_mode] == "watch"
      source[:watch_enabled] ? "badge badgeOk" : "badge badgeMuted"
    elsif source[:readiness] == "connected"
      "badge badgeOk"
    elsif %w[failed authorization_required].include?(source[:readiness])
      "badge badgeWarn"
    else
      "badge badgeMuted"
    end
  end

  def source_badge_label(source)
    if source[:kind] == "apple_photos"
      bridge_label(source[:bridge_status])
    elsif source[:ingest_mode] == "manual"
      "Manual upload"
    elsif source[:ingest_mode] == "watch"
      source[:watch_enabled] ? "Watching" : "Watch paused"
    else
      readiness_label(source[:readiness])
    end
  end

  def bridge_label(status)
    {
      "offline" => "Bridge offline",
      "authorization_required" => "Photos access required",
      "inventory_pending" => "Reading Photos library",
      "connected" => "Connected",
      "syncing" => "Syncing"
    }.fetch(status.to_s, "Bridge offline")
  end

  def readiness_label(status)
    {
      "not_configured" => "Not configured",
      "authorization_required" => "Authorization required",
      "inventory_pending" => "Inventory pending",
      "connected" => "Connected",
      "failed" => "Failed"
    }.fetch(status.to_s, "Unknown")
  end

  def freshness_label(source)
    return "live" if source[:kind] == "uploads"
    return "never synced" if source[:reported_at].blank?

    reported = Time.zone.parse(source[:reported_at])
    return "as of last sync #{reported.to_fs(:short)}" unless source[:kind] == "mounted_folder"

    minutes = ((Time.current - reported) / 60).round
    return "scanned just now" if minutes < 1
    return "scanned #{minutes} min ago" if minutes < 60

    hours = minutes / 60
    return "scanned #{hours} h ago" if hours < 24

    "scanned #{hours / 24} d ago"
  end

  def sync_active?(sync)
    sync.present? && %w[queued running].include?(sync[:status])
  end
```

- [x] **Step 2: Verify**

Run: `mise exec -- bin/rails runner 'puts ApplicationHelper.new.bridge_label("connected")'`
Expected: `Connected`.

- [x] **Step 3: Commit**

```bash
git add app/helpers/application_helper.rb
git commit -q -m "feat: bridge and freshness view helpers"
```

---

### Task 12: Apple Photos source card + overview wiring

**Files:**
- Replace: `app/views/catalog/_source_card.html.erb`
- Modify: `app/views/catalog/_overview.html.erb`

- [x] **Step 1: Replace the source card**

```erb
<%# app/views/catalog/_source_card.html.erb %>
<div class="card actionCard">
  <strong><%= source[:display_name] %><span class="<%= source_badge_class(source) %>"><%= source_badge_label(source) %></span></strong>

  <% if source[:kind] == "apple_photos" %>
    <% if source[:bridge_status] == "offline" %>
      <span class="muted">Library detected, but the macOS bridge is not connected.</span>
    <% elsif source[:bridge_status] == "authorization_required" %>
      <span class="muted">Allow Pics access to Photos in macOS, then keep the bridge running.</span>
    <% elsif source[:bridge_status] == "inventory_pending" %>
      <span class="muted">Connected. Reading your Photos library inventory…</span>
    <% end %>

    <% if source[:bridge_status] != "offline" && photos_libraries.any? %>
      <span class="muted">Detected library: <%= photos_libraries.first[:path] %></span>
    <% end %>

    <div class="sourceFacts">
      <span><%= number_with_delimiter(source[:stages]["discovered"]) %> discovered · <%= number_with_delimiter(source[:stages]["searchable"]) %> searchable</span>
      <span class="muted"><%= freshness_label(source) %></span>
      <% if source[:readiness_detail] %><span class="status"><%= source[:readiness_detail] %></span><% end %>
      <% if sync && sync[:status] == "error" && sync[:error].present? && sync[:error] != source[:readiness_detail] %>
        <span class="status"><%= sync[:error] %></span>
      <% end %>
    </div>

    <% if source[:bridge_status] == "offline" %>
      <details class="setupDetails">
        <summary>How to connect</summary>
        <ol>
          <li>From the Pics project folder, run the bridge command below.</li>
          <li>Allow Photos access when macOS prompts.</li>
          <li>Keep the bridge running, then return here.</li>
        </ol>
        <div class="commandRow"><code>swift run PicsPhotosBridge --watch --api-url http://localhost:3000</code></div>
        <% if photos_libraries.any? %><span class="muted">Detected library: <%= photos_libraries.first[:path] %></span><% end %>
      </details>
    <% end %>

    <% if source[:actions][:can_sync] && source[:bridge_status] == "connected" %>
      <div class="syncControls">
        <% sync_status = sync && sync[:status] %>
        <% import_label = case sync_status when "queued" then "Waiting for bridge…" when "running" then "Import in progress…" else "Import latest 25" end %>
        <%= button_to import_label, "/sources/apple-photos/sync", method: :post, params: { limit: 25 }, class: "button", disabled: sync_active?(sync) %>
        <%= button_to "Import entire library", "/sources/apple-photos/sync", method: :post, params: { limit: 500, full: "1" }, class: "button secondary", disabled: sync_active?(sync), data: { turbo_confirm: "Run a full Apple Photos sync? Pics will scan the entire Photos library and import only assets it does not already know about. The local bridge must be running." } %>
        <% if sync_status == "done" %>
          <span class="muted">Last <%= sync[:full_sync] == 1 ? "full" : "bounded" %> import added <%= number_with_delimiter(sync[:imported_count]) %> assets.</span>
        <% elsif sync_status == "partial" %>
          <span class="status">Partial import: <%= number_with_delimiter(sync[:imported_count]) %> imported, <%= number_with_delimiter(sync[:failed_count]) %> failed.</span>
        <% end %>
      </div>
    <% end %>
  <% else %>
    <div class="sourceFacts">
      <span><%= number_with_delimiter(source[:stages]["discovered"]) %> discovered · <%= number_with_delimiter(source[:stages]["searchable"]) %> searchable</span>
      <% if source[:ingest_mode] == "watch" %>
        <span class="muted"><%= source[:watch_enabled] ? "Watching for new files" : "Continuous watch is paused" %></span>
        <%= link_to "Manage watch settings", "/settings", class: "cardLink" %>
      <% else %>
        <span class="muted">Files uploaded directly to Pics</span>
      <% end %>
      <% if source[:readiness] == "failed" && source[:readiness_detail] %>
        <span class="status"><%= source[:readiness_detail] %></span>
      <% end %>
    </div>
  <% end %>
</div>
```

- [x] **Step 2: Pass the new locals from the overview**

```erb
<%# app/views/catalog/_overview.html.erb — replace the source connections render block %>
<h2>Source connections</h2>
<div class="cards">
  <% overview[:sources].each do |source| %>
    <%= render partial: "source_card", locals: { source: source, photos_libraries: overview[:context][:photos_libraries], sync: source[:sync] } %>
  <% end %>
</div>
```

- [x] **Step 3: Verify**

Run: `mise exec -- bin/rails test test/controllers/catalog_controller_test.rb`
Expected: all green (the HTML page still renders the partials). Then a smoke
render:

```bash
mise exec -- bin/rails server &
sleep 8
curl -s -H 'Accept: text/html' http://localhost:3000/catalog/overview | grep -o "Import latest 25"
kill %1 2>/dev/null
```

Expected: `Import latest 25` does **not** appear (bridge is offline by default),
but `Bridge offline` does appear. Run:

```bash
curl -s -H 'Accept: text/html' http://localhost:3000/catalog/overview | grep -o "Bridge offline"
```

Expected: `Bridge offline` prints a match.

- [x] **Step 4: Commit**

```bash
git add app/views/catalog/_source_card.html.erb app/views/catalog/_overview.html.erb
git commit -q -m "feat: apple photos source card with sync controls"
```

---

### Task 13: Full suite, quality gates, and curl bridge simulation

**Files:**
- None (verification)

- [ ] **Step 1: Run the full suite**

```bash
mise exec -- bin/rails test
```

Expected: all green.

- [ ] **Step 2: Rubocop**

```bash
mise exec -- bin/rubocop app lib test
```

Expected: no offenses.

- [ ] **Step 3: Brakeman**

```bash
mise exec -- bin/brakeman --no-pager
```

Expected: no warnings.

- [ ] **Step 4: Simulate the bridge over HTTP against a running server**

Start the server, then drive the protocol the way `main.swift` does (heartbeat →
sync → claim → known → upload → complete). Use a real tiny JPEG:

```bash
mise exec -- bin/rails server &
sleep 8
curl -s -X POST http://localhost:3000/sources/apple-photos/bridge/heartbeat \
  -H 'Content-Type: application/json' \
  -d '{"authorization_state":"authorized","asset_count":5}'
curl -s -X POST http://localhost:3000/sources/apple-photos/sync \
  -H 'Content-Type: application/json' -d '{"limit":2,"full":false}'
curl -s -X POST http://localhost:3000/sources/apple-photos/sync/claim
curl -s -X POST http://localhost:3000/sources/apple-photos/assets/known \
  -H 'Content-Type: application/json' -d '{"source_asset_ids":["A/B/C"]}'
curl -s -X POST http://localhost:3000/sources/apple-photos/assets \
  -F "file=@test/fixtures/tiny.jpg;type=image/jpeg" \
  -F "source_asset_id=A/B/C" -F "original_filename=IMG_0001.JPG" \
  -F "authorization_state=authorized" -F "asset_count=5"
curl -s -X POST http://localhost:3000/sources/apple-photos/sync/1/complete \
  -d 'imported_count=1&failed_count=0'
curl -s http://localhost:3000/sources/apple-photos/status
curl -s http://localhost:3000/catalog/overview | grep -o '"kind":"apple_photos"'
kill %1 2>/dev/null
```

Expected: heartbeat returns `"bridge_status":"connected"`; sync returns
`"status":"queued"`; claim returns `"status":"running"`; known returns
`{"source_asset_ids":[]}`; the upload returns `"status":"queued"`; complete
returns `"status":"done"`; status returns the source with the uploaded asset
count; the overview contains the apple_photos source entry.

- [ ] **Step 5: Commit plan state**

```bash
git add artifacts/photo-searchable-library-rails/apple-photos-bridge/apple-photos-bridge-plan.md
git commit -q -m "chore: record apple photos bridge phase 4 plan"
```

---

## Verification Summary

After all tasks complete:

- [ ] `mise exec -- bin/rails test` — all tests pass
- [ ] `mise exec -- bin/rubocop app lib test` — no offenses
- [ ] `mise exec -- bin/brakeman --no-pager` — no warnings
- [ ] The 8 `/sources/apple-photos/*` endpoints match the reference contract
  (sync/claim/complete lifecycle, `already_active`, partial/error precedence,
  stale sync recovery, bridge lease expiry, known dedupe, multipart ingest with
  duplicate + retried handling)
- [ ] Uploads land in `library/apple-photos/{uuid}.{suffix}`, assets are keyed
  by `source_asset_id`, and `ImportJob` reuses the existing pipeline without
  deleting Apple Photos originals on failure
- [ ] `/admin/library` returns the inventory walk + catalog counts
- [ ] `/catalog/overview` shows the real apple funnel, readiness, sync object,
  and `photos_libraries`; the Photos source card renders bridge states and sync
  controls
- [ ] Creating/updating a `SourceSync` updates `/catalog/overview` over the
  `"catalog"` Turbo Stream without a page reload
- [ ] The bridge CLI command in the UI copy points at `http://localhost:3000`
