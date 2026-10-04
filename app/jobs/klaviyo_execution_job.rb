# KlaviyoExecutionJob — delivers an approved ChurnGuard retention action via Klaviyo.
#
# Flow:
#   1. Locate the action + set RLS context.
#   2. Call KlaviyoClient#trigger_campaign — POST event to Klaviyo Events API.
#   3. On success: mark action as "executed".
#   4. On HTTP 429 (rate limit): re-raise → Sidekiq retries with exponential backoff.
#   5. On other API errors: re-raise → Sidekiq retries; after 5 exhausted retries
#      the sidekiq_retries_exhausted callback marks action "failed" and enqueues
#      OwnerNotificationJob to alert the shop owner.
#
# Retry schedule (custom via sidekiq_retry_in):
#   attempt 1 → 1 s, 2 → 2 s, 3 → 4 s, 4 → 8 s, 5 → 16 s  (2^count seconds)
#
# Queue: execution (priority 10 — highest). Never waits behind scoring jobs.
class KlaviyoExecutionJob < ApplicationJob
  queue_as :execution

  sidekiq_options retry: 5

  # Exponential backoff: 1 → 2 → 4 → 8 → 16 seconds.
  # Applied for both RateLimitError and ApiError retries.
  sidekiq_retry_in do |count, _ex, _jobinst|
    2 ** count
  end

  # Called by Sidekiq after the 5th (final) retry fails.
  # Marks the action "failed" and notifies the shop owner.
  sidekiq_retries_exhausted do |msg, ex|
    # ActiveJob wraps perform args one level deep inside the Sidekiq job hash.
    aj_payload = msg.dig("args", 0) || {}
    args       = (aj_payload["arguments"] || []).first || {}
    action_id  = args["action_id"]

    Rails.logger.error(
      "[KlaviyoExecutionJob] Retries exhausted for action_id=#{action_id.inspect}: #{ex.message}"
    )

    next unless action_id

    action = Action.find_by(id: action_id)
    next unless action

    RlsContext.set!(action.shop_id)
    action.update!(status: "failed")
    OwnerNotificationJob.perform_later(shop_id: action.shop_id)
  end

  # ── perform ───────────────────────────────────────────────────────────────────

  def perform(action_id:)
    action = Action.find_by(id: action_id)

    unless action
      Rails.logger.error("[KlaviyoExecutionJob] Action #{action_id} not found — skipping")
      return
    end

    shop = action.shop
    RlsContext.set!(shop.id)

    api_key = shop.klaviyo_api_key
    if api_key.blank?
      Rails.logger.warn(
        "[KlaviyoExecutionJob] Shop #{shop.shopify_domain} has no Klaviyo API key — skipping"
      )
      return
    end

    KlaviyoClient.new(api_key: api_key).trigger_campaign(action: action)
    action.execute!

    Rails.logger.info(
      "[KlaviyoExecutionJob] Executed action #{action_id} " \
      "(customer=#{action.customer_id}, shop=#{shop.shopify_domain}, " \
      "discount=#{action.proposed_discount})"
    )

  rescue KlaviyoClient::RateLimitError => e
    Rails.logger.warn("[KlaviyoExecutionJob] Rate limited for action #{action_id}: #{e.message}")
    raise  # Sidekiq retries with custom exponential backoff

  rescue KlaviyoClient::ApiError => e
    Rails.logger.error("[KlaviyoExecutionJob] API error for action #{action_id}: #{e.message}")
    raise  # Sidekiq retries; exhausted → sidekiq_retries_exhausted callback
  end
end
