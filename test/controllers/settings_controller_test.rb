require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  test "renders settings html page" do
    get "/settings"
    assert_response :success
    assert_match "Watch &amp; ingest", response.body
  end

  test "status json includes counts and settings" do
    get "/admin/status", as: :json
    assert_response :success
    body = JSON.parse(response.body)
    assert body.key?("counts")
    assert body.key?("settings")
    assert body.key?("jobs")
  end
end
