require "test_helper"

class UploadsControllerTest < ActionDispatch::IntegrationTest
  test "renders the upload form" do
    get "/assets/upload"

    assert_response :success
    assert_includes response.body, "Import a photo"
    assert_includes response.body, 'enctype="multipart/form-data"'
  end

  test "queues an HTML upload and redirects to jobs" do
    upload = Rack::Test::UploadedFile.new(Rails.root.join("test/fixtures/tiny.jpg"), "image/jpeg")

    post "/assets/upload", params: { file: upload }, headers: { "ACCEPT" => "text/html" }

    assert_response :redirect
    assert_redirected_to "/jobs"
    assert_equal "queued", Job.order(:id).last.status
  end
end
