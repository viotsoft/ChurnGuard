class AppUninstalledJob < ActiveJob::Base
  extend ShopifyAPI::Webhooks::WebhookHandler

  def self.handle(topic:, shop:, body:, webhook_id:, api_version:)
    perform_later(topic: topic, shop_domain: shop, webhook: body)
  end

  def perform(topic:, shop_domain:, webhook:)
    shop = Shop.find_by(shopify_domain: shop_domain)

    if shop.nil?
      logger.error("#{self.class} failed: cannot find shop with domain '#{shop_domain}'")
      raise ActiveRecord::RecordNotFound, "Shop Not Found"
    end

    logger.info("#{self.class}: shop '#{shop_domain}' uninstalled — enqueuing GDPR cleanup")

    # GDPR Article 17: anonymize PII immediately, hard-delete after 30 days.
    # Do NOT call shop.destroy here — that would violate the erasure window and
    # lose the audit trail before the merchant can appeal.
    ShopDataCleanupJob.perform_later(shop_id: shop.id, hard_delete: false)
  end
end
