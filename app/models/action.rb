class Action < ApplicationRecord
  belongs_to :shop
  belongs_to :customer
  has_one :approval_token, dependent: :destroy
  has_one :execution_queue_item, dependent: :destroy

  ACTION_TYPES = %w[klaviyo_campaign discount_code].freeze
  STATUSES     = %w[pending approved skipped expired executed failed].freeze
  TREATMENT_LABELS = {
    "winback_15" => "15% win-back offer",
    "nudge_10" => "10% repeat-purchase nudge",
    "vip_personal_offer" => "VIP personal offer",
    "birthday_offer" => "birthday offer"
  }.freeze

  validates :action_type, inclusion: { in: ACTION_TYPES }
  validates :status,      inclusion: { in: STATUSES }
  validates :risk_tier,   inclusion: { in: Customer::RISK_TIERS }
  validates :expires_at,  presence: true
  validates :uplift_score, numericality: {
    greater_than_or_equal_to: 0,
    less_than_or_equal_to: 1
  }, allow_nil: true
  validates :expected_incremental_revenue, numericality: true, allow_nil: true

  scope :pending,   -> { where(status: "pending") }
  scope :approved,  -> { where(status: "approved") }
  scope :skipped,   -> { where(status: "skipped") }
  scope :expired,   -> { where(status: "expired") }
  scope :executed,  -> { where(status: "executed") }
  scope :failed,    -> { where(status: "failed") }
  scope :completed, -> { where(status: %w[executed skipped]) }
  scope :recent,    -> { order(created_at: :desc) }
  scope :expiring,  -> { pending.where("expires_at < ?", Time.current) }
  scope :uplift_v3, -> { where(model_version: UpliftDecisionEngine::MODEL_VERSION) }

  def uplift_decision?
    model_version.present? && treatment_key.present? && uplift_score.present?
  end

  def treatment_label
    TREATMENT_LABELS.fetch(treatment_key, treatment_key.to_s.humanize)
  end

  def expired?
    expires_at < Time.current
  end

  def approve!
    update!(status: "approved", approved_at: Time.current)
  end

  def skip!
    update!(status: "skipped", skipped_at: Time.current)
  end

  def expire!
    update!(status: "expired")
  end

  def execute!
    update!(status: "executed", executed_at: Time.current)
  end
end
