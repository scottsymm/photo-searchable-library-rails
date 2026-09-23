require "test_helper"

class JobTest < ActiveSupport::TestCase
  test "continues tracking attempts after a failed file" do
    job = Job.create!(kind: "scan", status: "working")

    job.record_attempt!(2, error: "/media/photos/bad.heic: invalid image")
    assert_equal "working", job.reload.status
    assert_equal 0.5, job.progress
    assert_includes job.error, "bad.heic"

    job.record_attempt!(2)
    assert_equal "error", job.reload.status
    assert_equal 1.0, job.progress
  end
end
