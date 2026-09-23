require "test_helper"

class PersonMutationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @asset = Asset.create!(path: Rails.root.join("test/fixtures/tiny.jpg"), sha256: "person-test", size_bytes: 1, mime: "image/jpeg")
    @face = Face.create!(asset: @asset, bbox: "0,0,1,1", crop_path: "missing.jpg")
    @person = Person.create!(name: "Alex")
  end

  test "rejects unsafe face crop paths" do
    get "/persons/faces/#{@face.id}/crop"

    assert_response :not_found
  end

  test "assigns a face to a person" do
    post "/persons/#{@person.id}/faces/#{@face.id}", headers: { "ACCEPT" => "application/json" }

    assert_response :success
    assert_equal 1, @person.reload.person_faces.count
  end
end
