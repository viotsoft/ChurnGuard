class Customer < ApplicationRecord
  belongs_to :shop
  has_many :orders, dependent: :destroy
  has_many :events, dependent: :destroy
  has_many :actions, dependent: :destroy

  validates :shopify_customer_id, presence: true,
            uniqueness: { scope: :shop_id }
  validates :lifetime_value, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  RISK_TIERS = %w[high medium low].freeze
  validates :risk_tier, inclusion: { in: RISK_TIERS }, allow_nil: true

  scope :high_risk,   -> { where(risk_tier: "high") }
  scope :medium_risk, -> { where(risk_tier: "medium") }
  scope :at_risk,     -> { where(risk_tier: %w[high medium]) }
  scope :unscored,    -> { where(risk_tier: nil) }

  def display_name
    name.presence || email.presence || "Customer ##{shopify_customer_id}"
  end

  # Returns just the first name for use in UI labels ("Send Discount to Maria →").
  # Falls back to display_name if name is not available.
  def first_name
    name.present? ? name.split.first : display_name
  end
end
