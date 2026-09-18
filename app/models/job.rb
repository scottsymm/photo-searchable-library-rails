class Job < ApplicationRecord
  validates :kind, presence: true

  def mark_working!
    update!(status: "working", progress: 0)
  end

  def bump_progress!(value)
    update!(progress: value.clamp(0.0, 1.0))
  end

  def complete!
    update!(status: "done", progress: 1)
  end

  def fail!(message)
    update!(status: "error", error: message.to_s[0, 4000])
  end
end
