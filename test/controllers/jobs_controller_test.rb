require "test_helper"

class JobsControllerTest < ActionDispatch::IntegrationTest
  test "lists jobs" do
    Job.create!(kind: "scan")
    get "/jobs", headers: { "ACCEPT" => "application/json" }
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body["jobs"].length
    assert_equal "scan", body["jobs"].first["kind"]
  end
end
