require "test_helper"
require "securerandom"

class EmbeddingStoreTest < ActiveSupport::TestCase
  test "inserts and queries content embeddings" do
    asset = Asset.create!(path: "/tmp/test/a-#{SecureRandom.hex}.jpg", sha256: SecureRandom.hex, size_bytes: 1, mime: "image/jpeg")
    vector = Array.new(512, 0.0); vector[0] = 1.0
    EmbeddingStore.add_content(asset_id: asset.id, model: "m", model_version: "v", vector: vector)
    assert_equal [ [ asset.id, 0.0 ] ], EmbeddingStore.content_knn(vector, 5)
  end

  test "knn returns the configured distance for differing vectors" do
    asset = Asset.create!(path: "/tmp/test/b-#{SecureRandom.hex}.jpg", sha256: SecureRandom.hex, size_bytes: 1, mime: "image/jpeg")
    first = Array.new(512, 0.0); first[0] = 1.0
    second = Array.new(512, 0.0); second[1] = 1.0
    EmbeddingStore.add_content(asset_id: asset.id, model: "m", model_version: "v", vector: first)
    result = EmbeddingStore.content_knn(second, 5)
    assert_equal 1, result.length
    assert_in_delta 1.4142135, result.first.last, 1e-4
  end
end
