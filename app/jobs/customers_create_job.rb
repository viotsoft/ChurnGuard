class CustomersCreateJob < ApplicationJob
  queue_as :scoring

  def perform(shop_domain:, webhook:, webhook_id: nil)
    shop = Shop.find_by(shopify_domain: shop_domain)
    unless shop
      Rails.logger.error("[CustomersCreateJob] Shop not found: #{shop_domain}")
      return
    end

    RlsContext.set!(shop.id)
    payload = webhook.is_a?(String) ? JSON.parse(webhook) : webhook

    EventNormalizer.call(
      event_type: :customers_create,
      shop:       shop,
      payload:    payload,
      webhook_id: webhook_id
    )

    Rails.logger.info(
      "[CustomersCreateJob] Processed for #{shop_domain} " \
      "(customer_id=#{payload['id']}, webhook_id=#{webhook_id})"
    )
  end
end
