require "test_helper"

class HealthControllerTest < ActionDispatch::IntegrationTest
  test "returns ok" do
    get "/", headers: { "ACCEPT" => "application/json" }
    assert_response :success
    assert_equal({ "ok" => true }, JSON.parse(response.body))
  end

  test "renders the dashboard for browsers" do
    get "/", headers: { "ACCEPT" => "text/html" }

    assert_response :success
    assert_includes response.body, "Photo Library"
  end

  test "provides an explicit health endpoint" do
    get "/health", headers: { "ACCEPT" => "application/json" }

    assert_response :success
    assert_equal({ "ok" => true }, JSON.parse(response.body))
  end
end
