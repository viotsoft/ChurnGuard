class WebhookDeduplication < ApplicationRecord
  belongs_to :shop

  validates :webhook_id, presence: true, uniqueness: { scope: :shop_id }

  # Returns true if this webhook_id is new (not a duplicate).
  # INSERT ON CONFLICT DO NOTHING is the atomic, race-safe implementation.
  # Used by WebhookDeduplicationService in Phase 2.
  def self.register!(shop_id:, webhook_id:)
    create!(shop_id: shop_id, webhook_id: webhook_id)
    true
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    # RecordInvalid  → Ruby uniqueness validation caught it first (single-process)
    # RecordNotUnique → DB unique index caught it (concurrent requests race condition)
    false  # duplicate — already processed, skip silently
  end
end
