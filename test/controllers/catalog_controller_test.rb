require "test_helper"

class CatalogControllerTest < ActionDispatch::IntegrationTest
  test "overview returns funnel" do
    get "/catalog/overview", headers: { "ACCEPT" => "application/json" }
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal %w[discovered ready_to_import importing imported processing searchable failed_or_blocked],
                 body["funnel"].keys
  end

  test "renders html page" do
    get "/catalog/overview"
    assert_response :success
    assert_match "Photos", response.body
  end

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

  test "apple entry separates active imports from stuck assets" do
    apple = Source.find_by!(kind: "apple_photos")
    active_path = File.join(PICS_LIBRARY, "apple-photos", "active.jpg")
    stuck_path = File.join(PICS_LIBRARY, "apple-photos", "stuck.jpg")
    Asset.create!(path: active_path, sha256: "active", size_bytes: 1, mime: "image/jpeg", source: apple)
    Asset.create!(path: stuck_path, sha256: "stuck", size_bytes: 1, mime: "image/jpeg", source: apple)
    Job.create!(kind: "import", status: "working", params: { paths: [ active_path ] }.to_json)

    overview = CatalogOverview.call
    apple_entry = overview[:sources].find { |source| source[:kind] == "apple_photos" }

    assert_equal 2, apple_entry[:stages]["imported"]
    assert_equal 1, apple_entry[:stages]["processing"]
    assert_equal 1, apple_entry[:stages]["failed_or_blocked"]
  end

  test "mounted folder reports failed when the watch root is unavailable" do
    get "/catalog/overview", headers: { "ACCEPT" => "application/json" }
    body = JSON.parse(response.body)
    mounted = body["sources"].find { |s| s["kind"] == "mounted_folder" }
    assert_equal "failed", mounted["readiness"]
    assert_includes mounted["readiness_detail"], "watch root is not available"
  end
end
