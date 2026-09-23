require "test_helper"

class PersonsJsonTest < ActionDispatch::IntegrationTest
  setup do
    @asset = Asset.create!(path: Rails.root.join("test/fixtures/tiny.jpg"), sha256: "json-test", size_bytes: 1, mime: "image/jpeg")
    @person = Person.create!(name: "Sam")
  end

  test "index returns persons, suggestions, and enrichment" do
    get "/persons", headers: { "ACCEPT" => "application/json" }
    assert_response :success
    body = JSON.parse(response.body)
    assert body.key?("persons")
    assert body.key?("suggestions")
    assert body.key?("enrichment")
  end

  test "search returns matching persons" do
    get "/persons/search?q=Sam", headers: { "ACCEPT" => "application/json" }
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body["persons"].length
    assert_equal "Sam", body["persons"].first["name"]
    assert_equal 0, body["persons"].first["face_count"]
  end

  test "confirms a suggestion with a name" do
    face = Face.create!(asset: @asset, bbox: "0,0,1,1", crop_path: "missing.jpg")
    run = ClusteringRun.create!(model: "m", model_version: "v", algorithm: "dbscan", metric: "cosine", eps: 0.35, min_samples: 2)
    suggestion = ClusterSuggestion.create!(run: run, cluster_key: 1, face_count: 1, confidence: "high")
    FaceAssignment.create!(run: run, face: face, suggestion: suggestion, status: "suggested")

    post "/persons/suggestions/#{suggestion.id}/confirm",
      params: { name: "Sam" }, headers: { "ACCEPT" => "application/json" }

    assert_response :success
    assert_equal "Sam", suggestion.reload.person.name
  end

  test "index includes rejected suggestions and filters for html" do
    run = ClusteringRun.create!(model: "m", model_version: "v", algorithm: "dbscan", metric: "cosine", eps: 0.35, min_samples: 2)
    rejected = ClusterSuggestion.create!(run: run, cluster_key: 2, face_count: 1, confidence: "candidate", status: "rejected")

    get "/persons", headers: { "ACCEPT" => "application/json" }
    body = JSON.parse(response.body)
    assert_equal [ "rejected" ], body["suggestions"].map { |s| s["status"] }

    get "/persons"
    assert_response :success
    assert_no_match /Review again/, response.body

    get "/persons?show_rejected=1"
    assert_response :success
    assert_match /Review again/, response.body

    post "/persons/suggestions/#{rejected.id}/restore", headers: { "ACCEPT" => "application/json" }
    assert_response :success
    assert_equal "unreviewed", rejected.reload.status
  end
end
