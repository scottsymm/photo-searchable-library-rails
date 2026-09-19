require "test_helper"

class JobTest < ActiveSupport::TestCase
  test "progress and completion are based on finished imports" do
    job = Job.create!(kind: "scan")

    job.record_completion!(3)
    assert_in_delta 1.0 / 3, job.reload.progress, 0.0001
    assert_equal "queued", job.status

    job.record_completion!(3)
    assert_in_delta 2.0 / 3, job.reload.progress, 0.0001
    assert_equal "queued", job.status

    job.record_completion!(3)
    job.reload
    assert_equal 1, job.progress
    assert_equal "done", job.status
  end

  test "an error does not overwrite a completed job" do
    job = Job.create!(kind: "scan", status: "done", progress: 1)

    job.fail!("late import failure")

    job.reload
    assert_equal "done", job.status
    assert_nil job.error
  end
end
