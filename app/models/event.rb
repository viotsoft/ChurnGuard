class Event < ApplicationRecord
  belongs_to :shop
  belongs_to :customer, optional: true

  EVENT_TYPES = %w[orders_paid orders_cancelled customers_create].freeze

  validates :event_type, inclusion: { in: EVENT_TYPES }
  validates :occurred_at, presence: true

  scope :by_type, ->(type) { where(event_type: type) }
  scope :recent,  -> { order(occurred_at: :desc) }
end
