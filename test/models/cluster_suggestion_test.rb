require "test_helper"

class ClusterSuggestionTest < ActiveSupport::TestCase
  test "reuses the confirmed person when confirmation is retried" do
    run = ClusteringRun.create!(
      model: "test",
      model_version: "1",
      algorithm: "test",
      metric: "cosine",
      eps: 0.5,
      min_samples: 2
    )
    suggestion = ClusterSuggestion.create!(run: run, cluster_key: 1, face_count: 0)

    suggestion.confirm!
    first_person = suggestion.reload.person
    person_count = Person.count

    suggestion.confirm!
    second_person = suggestion.reload.person

    assert_equal first_person, second_person
    assert_equal person_count, Person.count
    assert_equal "confirmed", suggestion.reload.status
  end
end
