require "test_helper"

class JobStreamTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
  end

  teardown do
    ActiveJob::Base.queue_adapter = @queue_adapter
  end

  test "job updates enqueue a broadcast to the jobs stream" do
    assert_enqueued_with(job: Turbo::Streams::ActionBroadcastJob) do
      job = Job.create!(kind: "scan")
      job.update!(status: "working", progress: 0.5)
    end
  end

  test "import job completion broadcasts the catalog overview" do
    job = Job.create!(kind: "import")
    path = Rails.root.join("test/fixtures/tiny.jpg").to_s
    assert_enqueued_with(job: Turbo::Streams::ActionBroadcastJob) do
      ImportJob.perform_now(job_id: job.id, path: path, index: 0, total: 1)
    end
  end
end
