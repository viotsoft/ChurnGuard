class ExecutionQueueItem < ApplicationRecord
  belongs_to :action

  STATUSES = %w[queued processing completed failed dead].freeze
  validates :status, inclusion: { in: STATUSES }
  validates :attempts, numericality: { greater_than_or_equal_to: 0 }

  MAX_RETRIES = 5

  scope :dead,   -> { where(status: "dead") }
  scope :failed, -> { where(status: "failed") }

  def dead?
    attempts >= MAX_RETRIES || status == "dead"
  end

  def record_attempt!(error: nil)
    update!(
      attempts: attempts + 1,
      last_attempted_at: Time.current,
      last_error: error,
      status: attempts + 1 >= MAX_RETRIES ? "dead" : "failed"
    )
  end

  def mark_completed!
    update!(status: "completed", last_attempted_at: Time.current)
  end
end
