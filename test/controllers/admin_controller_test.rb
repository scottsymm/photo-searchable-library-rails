require "test_helper"

class AdminControllerTest < ActionDispatch::IntegrationTest
  test "status reports catalog counts" do
    get "/admin/status", headers: { "ACCEPT" => "application/json" }

    assert_response :success
    assert_equal 0, JSON.parse(response.body).fetch("counts").fetch("persons")
  end

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
end
