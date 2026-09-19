require "test_helper"

class SourceTest < ActiveSupport::TestCase
  test "classifies mounted folder paths" do
    source = Source.find_by!(kind: "mounted_folder")
    path = File.join(PICS_WATCH_ROOT, "2021", "picnic.jpg")
    assert_equal source, Source.classify_path(path)
  end

  test "classifies uploads under PICS_LIBRARY/imports" do
    source = Source.find_by!(kind: "uploads")
    path = File.join(PICS_LIBRARY, "imports", "abc123.jpg")
    assert_equal source, Source.classify_path(path)
  end

  test "returns nil for unrelated paths" do
    assert_nil Source.classify_path("/tmp/not-a-library/photo.jpg")
  end
end
