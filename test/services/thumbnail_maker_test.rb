require "test_helper"

class ThumbnailMakerTest < ActiveSupport::TestCase
  test "makes a jpeg thumbnail from an image" do
    path = Rails.root.join("test", "fixtures", "tiny.jpg").to_s
    jpeg = ThumbnailMaker.thumbnail(path, "image/jpeg")
    assert jpeg.bytesize > 0
    assert_equal "\xFF\xD8".b, jpeg.byteslice(0, 2)
  end
end
