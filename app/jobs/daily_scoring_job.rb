# DailyScoringJob — runs ScoringEngine for one shop.
#
# Enqueued by a scheduler (system cron / Sidekiq Cron) once per shop per day,
# ideally at 2am in the shop's local timezone. Timezone scheduling is a Phase 8
# addition — for now shops default to UTC 2am via infrastructure cron.
#
# Queue: scoring (lowest priority) so it never delays execution-queue jobs.
# Retries: 3 (Sidekiq default for scoring queue; a skipped shop is not an error).
class DailyScoringJob < ApplicationJob
  queue_as :scoring

  def perform(shop_id)
    shop = Shop.find_by(id: shop_id)

    unless shop
      Rails.logger.error("[DailyScoringJob] Shop not found: id=#{shop_id}")
      return
    end

    RlsContext.set!(shop.id)

    result = ScoringEngine.call(shop: shop)

    case result[:status]
    when :scored
      Rails.logger.info(
        "[DailyScoringJob] Scored #{result[:count]} customers for #{shop.shopify_domain}"
      )
      # Create actions + send approval emails for newly at-risk customers
      ActionCreator.call(shop: shop)
    when :skipped
      Rails.logger.info(
        "[DailyScoringJob] Skipped #{shop.shopify_domain} — #{result[:reason]}"
      )
    end
  end

  # Convenience: enqueue a scoring job for every known shop.
  # Called from a scheduler or manually: DailyScoringJob.enqueue_all
  def self.enqueue_all
    Shop.find_each do |shop|
      perform_later(shop.id)
    end
    Rails.logger.info("[DailyScoringJob] Enqueued scoring jobs for #{Shop.count} shops")
  end
end
