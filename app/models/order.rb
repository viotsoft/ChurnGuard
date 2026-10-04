class Order < ApplicationRecord
  belongs_to :shop
  belongs_to :customer

  STATUSES = %w[paid cancelled refunded].freeze

  validates :shopify_order_id, presence: true, uniqueness: { scope: :shop_id }
  validates :amount, numericality: { greater_than_or_equal_to: 0 }
  validates :ordered_at, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :paid,      -> { where(status: "paid") }
  scope :cancelled, -> { where(status: "cancelled") }
  scope :recent,    -> { order(ordered_at: :desc) }
end
