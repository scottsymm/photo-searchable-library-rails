require "test_helper"

class FaceEnrichmentTest < ActiveSupport::TestCase
  test "reports completed runs without suggestions" do
    run = ClusteringRun.new(status: "done")

    assert_equal "completed_no_suggestions", FaceEnrichment.clustering_status(1, run)
  end

  test "reports failed runs as errors" do
    run = ClusteringRun.new(status: "error")

    assert_equal "error", FaceEnrichment.clustering_status(1, run)
  end
end
