# WebhookDeduplicationService
#
# Prevents processing the same Shopify webhook twice.
# Shopify guarantees at-least-once delivery — duplicates are expected.
#
# Implementation: INSERT INTO webhook_deduplications ON CONFLICT DO NOTHING
# The UNIQUE index on (shop_id, webhook_id) makes this atomic and race-safe.
#
# Usage:
#   WebhookDeduplicationService.call(shop_id: shop.id, webhook_id: "abc123")
#   # => true  (new — process this webhook)
#   # => false (duplicate — already processed, skip silently)
#
# The webhook_id comes from the X-Shopify-Webhook-Id request header.

class WebhookDeduplicationService
  # Returns true if the webhook is new and should be processed.
  # Returns false if it's a duplicate and should be silently skipped.
  def self.call(shop_id:, webhook_id:)
    return false if webhook_id.blank?

    WebhookDeduplication.register!(shop_id: shop_id, webhook_id: webhook_id)
  end
end
