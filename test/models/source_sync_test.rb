require "test_helper"

class SourceSyncTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
  end

  teardown do
    ActiveJob::Base.queue_adapter = @queue_adapter
  end

  test "sync create enqueues a catalog overview broadcast" do
    apple = Source.find_by!(kind: "apple_photos")
    assert_enqueued_with(job: Turbo::Streams::ActionBroadcastJob) do
      SourceSync.create!(source: apple, limit_count: 25, full_sync: 0)
    end
  end
end
