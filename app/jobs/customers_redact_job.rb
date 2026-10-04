# app/jobs/customers_redact_job.rb
#
# Shopify GDPR mandatory webhook: customers/redact
# Triggered when a merchant requests erasure of a specific customer's data.
# The body contains the customer_id of the customer to delete.
#
# We anonymize that specific customer's PII while preserving the order history
# (aggregate revenue metrics are non-personal data under GDPR Recital 26).

class CustomersRedactJob < ActiveJob::Base
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

    RlsContext.set!(shop.id)
    webhook = JSON.parse(webhook) if webhook.is_a?(String)

    shopify_customer_id = webhook.dig("customer", "id")&.to_s
    if shopify_customer_id.blank?
      logger.error("#{self.class}: missing customer.id in webhook payload for '#{shop_domain}'")
      return
    end

    customer = shop.customers.find_by(shopify_customer_id: shopify_customer_id)
    if customer.nil?
      logger.info("#{self.class}: customer #{shopify_customer_id} not found in shop '#{shop_domain}' — nothing to redact")
      return
    end

    logger.info("#{self.class}: redacting customer #{customer.id} in shop '#{shop_domain}'")

    # Anonymize PII — keep the record for aggregate metrics (GDPR Recital 26)
    customer.update_columns(
      email: "redacted-#{customer.id}@deleted.invalid",
      name:  "Deleted Customer #{customer.id}",
      shopify_customer_id: "redacted-#{customer.id}"
    )
  ensure
    RlsContext.clear!
  end
end
