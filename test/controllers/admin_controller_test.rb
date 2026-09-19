require "test_helper"

class AdminControllerTest < ActionDispatch::IntegrationTest
  test "status reports catalog counts" do
    get "/admin/status", headers: { "ACCEPT" => "application/json" }

    assert_response :success
    assert_equal 0, JSON.parse(response.body).fetch("counts").fetch("persons")
  end
end
