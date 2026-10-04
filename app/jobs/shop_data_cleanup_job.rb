# app/jobs/shop_data_cleanup_job.rb
#
# GDPR Article 17 — Right to Erasure
#
# Enqueued when a Shopify merchant uninstalls ChurnGuard. The 30-day window
# gives the owner time to reconnect (accidental uninstall) before hard delete.
#
# Flow:
#   1. Immediate: anonymize PII on customers (email + name)
#   2. +30 days: destroy all shop data (shop + all tenant rows via cascade)
#
# Idempotent: safe to enqueue multiple times for the same shop_id.
# Uses RLS bypass (set! on superuser connection) so the cleanup job can
# read data without a real shop session.

class ShopDataCleanupJob < ApplicationJob
  queue_as :default

  # Phase 1 — runs immediately on uninstall (or when perform is called).
  # Anonymizes customer PII in-place so the data is no longer personally
  # identifiable while we wait out the 30-day window before hard deletion.
  def perform(shop_id:, hard_delete: false)
    shop = Shop.find_by(id: shop_id)
    return unless shop  # already deleted — nothing to do

    RlsContext.set!(shop.id)

    if hard_delete
      hard_delete_shop!(shop)
    else
      anonymize_customer_pii!(shop)
      schedule_hard_delete(shop)
    end
  ensure
    RlsContext.clear!
  end

  private

  # ── Anonymization (immediate) ──────────────────────────────────────────────

  def anonymize_customer_pii!(shop)
    # Replace email and name with non-reversible placeholders.
    # Keep customer records so action history / metrics remain intact.
    shop.customers.find_each do |customer|
      customer.update_columns(
        email: "redacted-#{customer.id}@deleted.invalid",
        name:  "Deleted Customer #{customer.id}"
      )
    end

    # Clear the shop's Klaviyo API key — no longer valid after uninstall
    shop.update_columns(
      klaviyo_api_key: nil,
      shopify_token:   "[REVOKED]"
    )
  end

  # ── Hard delete (30 days later) ────────────────────────────────────────────

  def hard_delete_shop!(shop)
    # All tenant rows are deleted by Postgres FK cascades defined in the schema.
    # Order: approval_tokens → actions → customers/orders/events → shop
    shop.destroy!
  end

  def schedule_hard_delete(shop)
    # Schedule the destructive step 30 days out (GDPR Art. 17 window).
    # perform_at is a Sidekiq-specific helper; ActiveJob wraps it via set().
    ShopDataCleanupJob
      .set(wait: 30.days)
      .perform_later(shop_id: shop.id, hard_delete: true)
  end
end
