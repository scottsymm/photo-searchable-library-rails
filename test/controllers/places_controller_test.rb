require "test_helper"

class PlacesControllerTest < ActionDispatch::IntegrationTest
  setup do
    Asset.create!(path: "/tmp/places/1.jpg", sha256: "pl1", size_bytes: 1, mime: "image/jpeg", place_city: "Lisbon", place_country: "PT")
    Asset.create!(path: "/tmp/places/2.jpg", sha256: "pl2", size_bytes: 1, mime: "image/jpeg", place_city: "Lisbon", place_country: "PT")
    Asset.create!(path: "/tmp/places/3.jpg", sha256: "pl3", size_bytes: 1, mime: "image/jpeg")
  end

  test "returns aggregated places as json" do
    get "/places", as: :json
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body["places"].length
    assert_equal "Lisbon", body["places"].first["place_city"]
    assert_equal 2, body["places"].first["count"]
  end

  test "renders html page" do
    get "/places"
    assert_response :success
    assert_match "Places", response.body
  end
end
