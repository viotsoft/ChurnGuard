# TokenExpiryJob — sweeps pending actions whose 72-hour window has closed.
#
# Runs daily (via Sidekiq Cron / system cron — Phase 8 scheduling).
# Updates actions.status = 'expired' in bulk; does NOT iterate per-record.
# The corresponding ApprovalToken records expire naturally via their own
# expires_at column — no cascade update needed.
#
# Idempotent: re-running on already-expired rows is a no-op (SQL WHERE clause).
class TokenExpiryJob < ApplicationJob
  queue_as :scoring

  def perform
    expired_count = Action
                      .where(status: "pending")
                      .where("expires_at < ?", Time.current)
                      .update_all(status: "expired")

    if expired_count > 0
      Rails.logger.info("[TokenExpiryJob] Expired #{expired_count} pending actions")
    else
      Rails.logger.debug("[TokenExpiryJob] No pending actions to expire")
    end

    expired_count
  end
end
