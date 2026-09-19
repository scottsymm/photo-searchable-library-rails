require "test_helper"

class CatalogControllerTest < ActionDispatch::IntegrationTest
  test "overview returns funnel" do
    get "/catalog/overview", headers: { "ACCEPT" => "application/json" }
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal %w[discovered ready_to_import importing imported processing searchable failed_or_blocked],
                 body["funnel"].keys
  end

  test "renders html page" do
    get "/catalog/overview"
    assert_response :success
    assert_match "Catalog Overview", response.body
  end
end
