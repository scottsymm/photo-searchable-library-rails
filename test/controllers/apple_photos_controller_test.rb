require "test_helper"

class ApplePhotosControllerTest < ActionDispatch::IntegrationTest
  setup do
    SourceSync.delete_all
  end

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
    upload = Rack::Test::UploadedFile.new(Rails.root.join("public/icon.png"), "image/png")

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
      file: Rack::Test::UploadedFile.new(Rails.root.join("public/icon.png"), "image/png"),
      source_asset_id: "ABC/L0/001",
      original_filename: "IMG_0001.JPG"
    }
    assert_equal "duplicate", JSON.parse(response.body)["status"]
  ensure
    ApplePhotosBridge.define_singleton_method(:library_root, original) if original
    FileUtils.rm_rf(tmpdir) if tmpdir
  end

  test "ingest rejects unsupported file types before writing or queuing" do
    tmpdir = Dir.mktmpdir
    original = ApplePhotosBridge.method(:library_root)
    ApplePhotosBridge.define_singleton_method(:library_root) { Pathname.new(tmpdir) }

    assert_no_difference "Job.count" do
      post "/sources/apple-photos/assets", params: {
        file: Rack::Test::UploadedFile.new(Rails.root.join("public/icon.png"), "image/png"),
        source_asset_id: "ABC/L0/003",
        original_filename: "notes.txt"
      }
    end

    assert_response :bad_request
    assert_not Dir.exist?(File.join(tmpdir, "apple-photos"))
  ensure
    ApplePhotosBridge.define_singleton_method(:library_root, original) if original
    FileUtils.rm_rf(tmpdir) if tmpdir
  end

  test "ingest rejects files larger than the upload limit before writing or queuing" do
    tmpdir = Dir.mktmpdir
    original = ApplePhotosBridge.method(:library_root)
    ApplePhotosBridge.define_singleton_method(:library_root) { Pathname.new(tmpdir) }
    oversized = Tempfile.new("oversized-upload")
    oversized.truncate(PICS_MAX_UPLOAD_BYTES + 1)

    assert_no_difference "Job.count" do
      post "/sources/apple-photos/assets", params: {
        file: Rack::Test::UploadedFile.new(oversized.path, "image/jpeg"),
        source_asset_id: "ABC/L0/004",
        original_filename: "large.jpg"
      }
    end

    assert_response :bad_request
    assert_not Dir.exist?(File.join(tmpdir, "apple-photos"))
  ensure
    oversized&.close!
    ApplePhotosBridge.define_singleton_method(:library_root, original) if original
    FileUtils.rm_rf(tmpdir) if tmpdir
  end

  test "ingest retries a previously failed import without re-writing the file" do
    tmpdir = Dir.mktmpdir
    original = ApplePhotosBridge.method(:library_root)
    ApplePhotosBridge.define_singleton_method(:library_root) { Pathname.new(tmpdir) }
    post "/sources/apple-photos/assets", params: {
      file: Rack::Test::UploadedFile.new(Rails.root.join("public/icon.png"), "image/png"),
      source_asset_id: "ABC/L0/002",
      original_filename: "IMG_0002.JPG"
    }
    asset = Asset.find_by!(source_asset_id: "ABC/L0/002")
    Job.where(kind: "import").update_all(status: "error")

    assert_difference "Job.count" do
      post "/sources/apple-photos/assets", params: {
        file: Rack::Test::UploadedFile.new(Rails.root.join("public/icon.png"), "image/png"),
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
end
