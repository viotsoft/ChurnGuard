# Processes orders/paid Shopify webhooks asynchronously.
# Enqueued by WebhooksController after HMAC verification + deduplication.
# Calls EventNormalizer to upsert Customer, create Order, and create Event.
class OrdersPaidJob < ApplicationJob
  queue_as :scoring

  def perform(shop_domain:, webhook:, webhook_id: nil)
    shop = Shop.find_by(shopify_domain: shop_domain)
    unless shop
      Rails.logger.error("[OrdersPaidJob] Shop not found: #{shop_domain}")
      return
    end

    RlsContext.set!(shop.id)
    payload = webhook.is_a?(String) ? JSON.parse(webhook) : webhook

    EventNormalizer.call(
      event_type: :orders_paid,
      shop:       shop,
      payload:    payload,
      webhook_id: webhook_id
    )

    Rails.logger.info(
      "[OrdersPaidJob] Processed for #{shop_domain} " \
      "(order_id=#{payload['id']}, webhook_id=#{webhook_id})"
    )
  end
end
