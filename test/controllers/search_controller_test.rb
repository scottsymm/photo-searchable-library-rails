require "test_helper"

class SearchControllerTest < ActionDispatch::IntegrationTest
  test "returns empty results without a query" do
    get "/search", params: { q: "" }, headers: { "ACCEPT" => "application/json" }
    assert_response :success
    assert_equal({ "results" => [] }, JSON.parse(response.body))
  end

  test "allows JSON clients with an outdated browser user agent" do
    get "/search",
      params: { q: "" },
      headers: { "ACCEPT" => "application/json", "USER_AGENT" => "Chrome/100.0.0.0" }
    assert_response :success
  end

  test "renders html page" do
    get "/search"
    assert_response :success
    assert_match "Search", response.body
  end
end
