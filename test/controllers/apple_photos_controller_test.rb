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
end
