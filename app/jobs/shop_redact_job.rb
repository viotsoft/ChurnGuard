# app/jobs/shop_redact_job.rb
#
# Shopify GDPR mandatory webhook: shop/redact
# Triggered 48 hours after app/uninstalled to request permanent data removal.
# At this point the 30-day soft-delete window should have elapsed or the
# ShopDataCleanupJob (hard_delete: true) is already scheduled.
#
# We verify our cleanup is complete; if not, we force it immediately.

class ShopRedactJob < ActiveJob::Base
  extend ShopifyAPI::Webhooks::WebhookHandler

  def self.handle(topic:, shop:, body:, webhook_id:, api_version:)
    perform_later(topic: topic, shop_domain: shop, webhook: body)
  end

  def perform(topic:, shop_domain:, webhook:)
    shop = Shop.find_by(shopify_domain: shop_domain)

    if shop.nil?
      # Shop is already gone — cleanup completed successfully, nothing to do.
      logger.info("#{self.class}: shop '#{shop_domain}' already removed — redact complete")
      return
    end

    logger.info("#{self.class}: forcing immediate hard delete for '#{shop_domain}' (shop/redact received)")

    # Force immediate cleanup bypassing the 30-day wait.
    # Shopify has explicitly requested we remove this shop's data now.
    ShopDataCleanupJob.perform_now(shop_id: shop.id, hard_delete: true)
  end
end