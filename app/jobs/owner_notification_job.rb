# OwnerNotificationJob — sends a single aggregated failure email to the shop owner.
#
# Triggered by KlaviyoExecutionJob#sidekiq_retries_exhausted when a Klaviyo
# campaign could not be delivered after 5 retries.
#
# Aggregates all currently-failed actions for the shop so one email covers
# multiple failures rather than one email per action. Idempotent: calling it
# again just sends an updated count.
#
# Queue: notifications (priority 5).
class OwnerNotificationJob < ApplicationJob
  queue_as :notifications

  def perform(shop_id:)
    shop = Shop.find_by(id: shop_id)
    unless shop
      Rails.logger.error("[OwnerNotificationJob] Shop #{shop_id} not found — skipping")
      return
    end

    RlsContext.set!(shop.id)
    failed_count = shop.actions.where(status: "failed").count

    if failed_count.zero?
      Rails.logger.info("[OwnerNotificationJob] No failed actions for shop #{shop_id} — skipping")
      return
    end

    OwnerNotificationMailer.execution_failed(shop: shop, failed_count: failed_count).deliver_now

    Rails.logger.info(
      "[OwnerNotificationJob] Sent failure notification for shop #{shop_id} " \
      "(#{failed_count} failed action(s))"
    )
  end
end
