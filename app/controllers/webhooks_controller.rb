require "openssl"
require "base64"

# WebhooksController — Shopify behavioral event ingestion
#
# Security model:
#   1. HMAC verification on every request (before_action :verify_shopify_hmac)
#      Computes HMAC-SHA256 of raw request body using SHOPIFY_API_SECRET,
#      compares to X-Shopify-Hmac-SHA256 header via constant-time comparison.
#      Returns 401 on mismatch — body is never processed.
#
#   2. Idempotency via WebhookDeduplicationService
#      Uses X-Shopify-Webhook-Id header + UNIQUE index to prevent double-processing.
#      Returns 200 immediately on duplicate (Shopify expects 2xx to stop retrying).
#
#   3. Async processing via Sidekiq jobs (scoring queue)
#      Controller returns 200 in < 5s. EventNormalizer runs in the background.
#      Shopify retries on 5xx; 200 after dedup silences retries on duplicates.
#
# Flow: POST /webhooks/orders_paid
#   → verify_shopify_hmac (401 on failure)
#   → find shop by X-Shopify-Shop-Domain
#   → WebhookDeduplicationService (200 + return on duplicate)
#   → enqueue job (OrdersPaidJob, scoring queue)
#   → 200 OK
class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :verify_shopify_hmac
  before_action :find_shop

  # POST /webhooks/orders_paid
  def orders_paid
    return if duplicate?

    OrdersPaidJob.perform_later(
      shop_domain: @shop.shopify_domain,
      webhook:     raw_payload,
      webhook_id:  webhook_id
    )
    head :ok
  end

  # POST /webhooks/orders_cancelled
  def orders_cancelled
    return if duplicate?

    OrdersCancelledJob.perform_later(
      shop_domain: @shop.shopify_domain,
      webhook:     raw_payload,
      webhook_id:  webhook_id
    )
    head :ok
  end

  # POST /webhooks/customers_create
  def customers_create
    return if duplicate?

    CustomersCreateJob.perform_later(
      shop_domain: @shop.shopify_domain,
      webhook:     raw_payload,
      webhook_id:  webhook_id
    )
    head :ok
  end

  # ── GDPR endpoints ─────────────────────────────────────────────────────────
  # These are required by Shopify for all apps.
  # AppUninstalledJob (from shopify_app generator) handles data cleanup.

  # POST /webhooks/app_uninstalled
  def app_uninstalled
    AppUninstalledJob.perform_later(
      topic:       "app/uninstalled",
      shop_domain: @shop.shopify_domain,
      webhook:     raw_payload
    )
    head :ok
  end

  # POST /webhooks/customers_data_request
  def customers_data_request
    CustomersDataRequestJob.perform_later(
      topic:       "customers/data_request",
      shop_domain: @shop.shopify_domain,
      webhook:     raw_payload
    )
    head :ok
  end

  # POST /webhooks/customers_redact
  def customers_redact
    CustomersRedactJob.perform_later(
      topic:       "customers/redact",
      shop_domain: @shop.shopify_domain,
      webhook:     raw_payload
    )
    head :ok
  end

  # POST /webhooks/shop_redact
  def shop_redact
    ShopRedactJob.perform_later(
      topic:       "shop/redact",
      shop_domain: @shop.shopify_domain,
      webhook:     raw_payload
    )
    head :ok
  end

  private

  # ── HMAC verification ───────────────────────────────────────────────────────

  def verify_shopify_hmac
    hmac_header = request.headers["X-Shopify-Hmac-SHA256"]

    if hmac_header.blank? || !valid_hmac?(hmac_header)
      Rails.logger.warn(
        "[WebhooksController] HMAC verification failed for " \
        "#{request.path} from #{shop_domain_header}"
      )
      head :unauthorized
    end
  end

  def valid_hmac?(hmac_header)
    return false if hmac_header.blank?

    body   = request.raw_post.to_s   # guard against nil body
    secret = ShopifyApp.configuration.secret
    computed = Base64.strict_encode64(
      OpenSSL::HMAC.digest("SHA256", secret, body)
    )
    # Constant-time comparison prevents timing attacks
    ActiveSupport::SecurityUtils.secure_compare(computed, hmac_header)
  end

  # ── Shop resolution ─────────────────────────────────────────────────────────

  def find_shop
    @shop = Shop.find_by(shopify_domain: shop_domain_header)

    unless @shop
      Rails.logger.warn(
        "[WebhooksController] Unknown shop domain: #{shop_domain_header}"
      )
      head :unprocessable_entity
    end
  end

  # ── Deduplication ───────────────────────────────────────────────────────────

  # Returns true (and responds 200) if this webhook has already been processed.
  def duplicate?
    return false if webhook_id.blank?

    unless WebhookDeduplicationService.call(shop_id: @shop.id, webhook_id: webhook_id)
      Rails.logger.info(
        "[WebhooksController] Duplicate webhook ignored: #{webhook_id}"
      )
      head :ok
      return true
    end

    false
  end

  # ── Request helpers ─────────────────────────────────────────────────────────

  def shop_domain_header
    request.headers["X-Shopify-Shop-Domain"]
  end

  def webhook_id
    request.headers["X-Shopify-Webhook-Id"]
  end

  def raw_payload
    request.raw_post
  end
end
