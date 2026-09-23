require "test_helper"
require "securerandom"

class SearchServiceTest < ActiveSupport::TestCase
  setup do
    @paris = Asset.create!(path: "/tmp/test/p-#{SecureRandom.hex}.jpg", sha256: SecureRandom.hex, size_bytes: 1, mime: "image/jpeg",
                           taken_at: Time.utc(2021, 6, 1), place_city: "Paris", place_country: "FR")
    @rome = Asset.create!(path: "/tmp/test/r-#{SecureRandom.hex}.jpg", sha256: SecureRandom.hex, size_bytes: 1, mime: "image/jpeg",
                          taken_at: Time.utc(2020, 1, 1), place_city: "Rome", place_country: "IT")
  end

  test "filters by place" do
    ids = SearchService.search(place: "Paris").map { |r| r[:id] }
    assert_equal [ @paris.id ], ids
  end

  test "filters by date window" do
    ids = SearchService.search(after: "2021-01-01", before: "2021-12-31").map { |r| r[:id] }
    assert_equal [ @paris.id ], ids
  end

  test "recent-first ordering without a query" do
    ids = SearchService.search.map { |r| r[:id] }
    assert_equal [ @paris.id, @rome.id ], ids
  end

  test "filters by person name" do
    person = Person.create!(name: "Leo")
    asset = Asset.create!(path: "/tmp/test/leo.jpg", sha256: SecureRandom.hex, size_bytes: 1, mime: "image/jpeg")
    face = Face.create!(asset: asset, bbox: "0,0,1,1")
    person.assign_face!(face)

    ids = SearchService.search(who: "Leo").map { |result| result[:id] }

    assert_equal [ asset.id ], ids
  end
end
