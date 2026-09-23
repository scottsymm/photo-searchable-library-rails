require "test_helper"

class SearchQueryTest < ActiveSupport::TestCase
  test "extracts free text and structured filters" do
    parsed = SearchQuery.parse("picnic who:Sam place:Lisbon before:2020")
    assert_equal "picnic", parsed[:text]
    assert_equal "Sam", parsed[:who]
    assert_equal "Lisbon", parsed[:place]
    assert_equal "2020", parsed[:before]
  end

  test "handles empty and whitespace input" do
    assert_equal({ text: "" }, SearchQuery.parse(""))
    assert_equal({ text: "" }, SearchQuery.parse("   "))
  end

  test "keeps unknown prefixes as free text" do
    assert_equal({ text: "color:red picnic" }, SearchQuery.parse("color:red picnic"))
  end

  test "is case insensitive for field prefixes" do
    parsed = SearchQuery.parse("Who:Sam PLACE:Paris")
    assert_equal "Sam", parsed["who"] || parsed[:who]
    assert_equal "Paris", parsed["place"] || parsed[:place]
  end
end
