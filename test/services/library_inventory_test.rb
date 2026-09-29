require "test_helper"

class LibraryInventoryTest < ActiveSupport::TestCase
  test "scans a root and finds photos libraries and media" do
    LibraryInventory.clear!
    dir = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(dir, "Photos Library.photoslibrary", "sub"))
    File.write(File.join(dir, "Photos Library.photoslibrary", "sub", "inside.jpg"), "x")
    FileUtils.mkdir_p(File.join(dir, "vacation"))
    File.write(File.join(dir, "vacation", "picnic.jpg"), "x")
    File.write(File.join(dir, "notes.txt"), "x")

    inventory = LibraryInventory.call(dir)

    assert_equal 1, inventory[:media_files]
    assert_equal ".jpg", inventory[:extensions].keys.first
    assert_equal 1, inventory[:photos_libraries].length
    assert_equal "Photos Library.photoslibrary", inventory[:photos_libraries].first[:name]
    assert_equal true, inventory[:available]
    assert_equal 0, inventory[:directory_errors].length
  ensure
    LibraryInventory.clear!
    FileUtils.rm_rf(dir) if dir
  end

  test "reports an unavailable root" do
    LibraryInventory.clear!
    inventory = LibraryInventory.call(File.join(Dir.tmpdir, "missing-root-#{SecureRandom.hex}"))
    assert_equal false, inventory[:available]
    assert_empty inventory[:photos_libraries]
  ensure
    LibraryInventory.clear!
  end

  test "does not follow directory symlinks" do
    LibraryInventory.clear!
    dir = Dir.mktmpdir
    File.write(File.join(dir, "photo.jpg"), "x")
    FileUtils.ln_s(dir, File.join(dir, "loop"))

    inventory = LibraryInventory.call(dir)

    assert_equal 1, inventory[:media_files]
    assert_empty inventory[:directory_errors]
  ensure
    LibraryInventory.clear!
    FileUtils.rm_rf(dir) if dir
  end
end
