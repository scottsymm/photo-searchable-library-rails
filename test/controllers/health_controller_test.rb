require "test_helper"

class HealthControllerTest < ActionDispatch::IntegrationTest
  test "returns ok" do
    get "/"
    assert_response :success
    assert_equal({ "ok" => true }, JSON.parse(response.body))
  end
end
