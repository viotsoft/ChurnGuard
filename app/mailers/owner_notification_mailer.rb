# OwnerNotificationMailer — operational alerts sent to the shop owner.
#
# Unlike ApprovalMailer (customer-facing), these are system alerts.
# Design: same warm cream brand tone, but informational rather than action-driving.
# The single CTA is a deep link to settings where the owner can fix Klaviyo config.
class OwnerNotificationMailer < ApplicationMailer
  default from: ENV.fetch("MAIL_FROM", "ChurnGuard <noreply@churnguard.io>")

  # Notifies the shop owner that one or more retention actions failed to reach Klaviyo.
  #
  # Triggered by OwnerNotificationJob after KlaviyoExecutionJob retries are exhausted.
  # Shows the total number of currently-failed actions so the owner knows the scope.
  #
  # @param shop         [Shop]    the shop whose owner receives the alert
  # @param failed_count [Integer] number of actions currently in "failed" status
  def execution_failed(shop:, failed_count:)
    @shop         = shop
    @failed_count = failed_count
    @settings_url = settings_url(host: ENV.fetch("HOST", "app.churnguard.io"))

    mail(
      to:      owner_email_for(shop),
      subject: subject_line
    )
  end

  private

  def subject_line
    noun = @failed_count == 1 ? "retention action" : "retention actions"
    "⚠️ #{@failed_count} #{noun} failed to send — action needed"
  end

  def owner_email_for(shop)
    ENV.fetch("OWNER_EMAIL_OVERRIDE",
              "owner@#{shop.shopify_domain.sub('.myshopify.com', '.com')}")
  end
end
