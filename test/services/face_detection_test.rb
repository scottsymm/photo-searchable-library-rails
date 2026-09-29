require "test_helper"

class FaceDetectionTest < ActiveSupport::TestCase
  setup do
    @crop_root = Pathname.new(Dir.mktmpdir("face-crops-#{Process.pid}-"))
    @original_crop_root = FaceCrop.method(:crop_root)
    crop_root = @crop_root.to_s
    FaceCrop.define_singleton_method(:crop_root) { crop_root }

    @path = Rails.root.join("test/fixtures/tiny.jpg").to_s
    @asset = Asset.create!(
      path: @path,
      sha256: Digest::SHA256.file(@path).hexdigest,
      size_bytes: File.size(@path),
      mime: "image/jpeg"
    )
  end

  test "persists face crops and vectors idempotently" do
    embedding = Array.new(512, 0.01)
    response = [
      { "box" => [ 0, 0, 1, 1 ], "embedding" => embedding },
      { "box" => [ 0, 0, 1, 1 ], "embedding" => embedding }
    ]

    original = SidecarClient.method(:detect_faces)
    SidecarClient.define_singleton_method(:detect_faces) { |*| response }
    FaceDetection.process(@asset)
    FaceDetection.process(@asset)

    assert_equal 1, @asset.faces.count
    assert_equal 1, FaceEmbed.count
    assert_equal 1, ActiveRecord::Base.connection.select_value("SELECT count(*) FROM vec0_face").to_i
    crop = FaceCrop.contained_path(@asset.faces.first.crop_path)
    assert File.file?(crop)
  ensure
    SidecarClient.define_singleton_method(:detect_faces, original) if original
  end

  test "preserves an existing crop when reprocessing fails" do
    embedding = Array.new(512, 0.01)
    response = [ { "box" => [ 0, 0, 1, 1 ], "embedding" => embedding } ]
    original_detect = SidecarClient.method(:detect_faces)
    original_upsert = FaceEmbed.method(:upsert)
    SidecarClient.define_singleton_method(:detect_faces) { |*| response }
    FaceDetection.process(@asset)
    face = @asset.faces.first
    crop_path = FaceCrop.contained_path(face.crop_path)
    original_crop = File.binread(crop_path)
    FaceEmbed.define_singleton_method(:upsert) { |*| raise "embedding persistence failed" }

    assert_raises(RuntimeError) { FaceDetection.process(@asset) }

    assert_equal original_crop, File.binread(crop_path)
    assert_equal face.id, @asset.faces.first.id
    assert_equal face.crop_path, @asset.faces.first.crop_path
  ensure
    SidecarClient.define_singleton_method(:detect_faces, original_detect) if original_detect
    FaceEmbed.define_singleton_method(:upsert, original_upsert) if original_upsert
  end

  test "removes faces missing from a reimport" do
    embedding = Array.new(512, 0.01)
    responses = [
      [
        { "box" => [ 0, 0, 1, 1 ], "embedding" => embedding },
        { "box" => [ 1, 1, 1, 1 ], "embedding" => embedding }
      ],
      [ { "box" => [ 0, 0, 1, 1 ], "embedding" => embedding } ]
    ]
    original = SidecarClient.method(:detect_faces)
    SidecarClient.define_singleton_method(:detect_faces) { |*| responses.shift }

    FaceDetection.process(@asset)
    removed_face = @asset.faces.find_by!(bbox: "1.0,1.0,1.0,1.0")
    removed_crop = FaceCrop.contained_path(removed_face.crop_path)
    person = Person.create!(name: "Removed")
    person.assign_face!(removed_face)

    FaceDetection.process(@asset)

    assert_equal 1, @asset.faces.count
    assert_not Face.exists?(removed_face.id)
    assert_not FaceEmbed.exists?(face_id: removed_face.id)
    assert_equal 0, person.reload.person_faces.count
    assert_equal 1, ActiveRecord::Base.connection.select_value("SELECT count(*) FROM vec0_face").to_i
    assert_not File.exist?(removed_crop)
  ensure
    SidecarClient.define_singleton_method(:detect_faces, original) if original
  end

  test "skips video assets" do
    @asset.update!(mime: "video/mp4")
    original = SidecarClient.method(:detect_faces)
    SidecarClient.define_singleton_method(:detect_faces) { |*| raise "should not call sidecar" }
    assert_empty FaceDetection.process(@asset)
  ensure
    SidecarClient.define_singleton_method(:detect_faces, original) if original
  end

  teardown do
    FaceCrop.define_singleton_method(:crop_root, @original_crop_root)
    FileUtils.rm_rf(@crop_root)
  end
end
