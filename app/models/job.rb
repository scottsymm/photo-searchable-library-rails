class Job < ApplicationRecord
  include Turbo::Broadcastable

  after_create_commit { broadcast_prepend_later_to "jobs", target: "jobs_list", partial: "jobs/job", locals: { job: self } }
  after_update_commit { broadcast_replace_later_to "jobs", target: "job_#{id}", partial: "jobs/job", locals: { job: self } }

  validates :kind, presence: true

  def mark_working!
    update!(status: "working", progress: 0)
  end

  def record_completion!(total)
    record_attempt!(total)
  end

  def record_attempt!(total, error: nil)
    with_lock do
      return if status == "done"

      value = progress.to_f + (1.0 / total)
      attributes = { progress: value.clamp(0.0, 1.0), status: "working" }
      if error.present?
        combined_error = [ self.error, error ].compact.reject(&:empty?).join("\n")
        attributes[:error] = combined_error.last(4000)
      end
      if value >= 1.0
        attributes[:status] = "done"
      end
      update!(attributes)
    end
  end

  def complete!
    update!(status: "done", progress: 1)
  end

  def fail!(message)
    with_lock do
      update!(status: "error", error: message.to_s[0, 4000]) unless %w[done error].include?(status)
    end
  end
end
