require "test_helper"

class FaceClusteringTest < ActiveSupport::TestCase
  test "creates a reviewable suggestion for a cluster" do
    asset = Asset.create!(path: Rails.root.join("test/fixtures/tiny.jpg"), sha256: "cluster-test", size_bytes: 1, mime: "image/jpeg")
    faces = 2.times.map { |index| Face.create!(asset: asset, bbox: "#{index},0,1,1") }
    vector = Array.new(512, 0.01)
    faces.each { |face| FaceEmbed.create!(face: face, model: "insightface", embed: EmbeddingStore.to_blob(vector)) }
    response = { "labels" => [ 0, 0 ] }

    original = SidecarClient.method(:cluster_faces)
    SidecarClient.define_singleton_method(:cluster_faces) { |*| response }
    run = FaceClustering.run
    assert_equal "done", run.status
    assert_equal 1, run.cluster_suggestions.count
    assert_equal 2, run.face_assignments.count
  ensure
    SidecarClient.define_singleton_method(:cluster_faces, original) if original
  end
end
