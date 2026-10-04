# ApprovalMailer — notifies the shop owner when a customer is at risk.
#
# Design constraints (DESIGN.md):
#   - Background #F5F0E8 (warm cream), never white
#   - Customer name in Fraunces serif — never Inter/system-ui
#   - Revenue at risk in Geist Mono, terracotta #D4500A — shown FIRST on card
#   - CTA button in terracotta #D4500A — never blue
#   - Two actions: approve (primary) + skip (ghost link)
#   - No login required — token is the auth
#
# Delivery: Postmark transactional, via Sidekiq notifications queue.
# The raw JWT is passed in and embedded in one-tap GET approval links.
class ApprovalMailer < ApplicationMailer
  default from: ENV.fetch("MAIL_FROM", "ChurnGuard <noreply@churnguard.io>")

  # Sends an approval request to the shop owner for a single at-risk customer.
  #
  # @param action [Action] the pending action record
  # @param token  [String] raw JWT (embedded in approve/skip links — never logged)
  def notify_owner(action:, token:)
    @action   = action
    @customer = action.customer
    @shop     = action.shop
    @token    = token

    @approve_url = approve_approvals_url(token: @token)
    @skip_url    = skip_approvals_url(token: @token)

    @revenue_formatted  = format_currency(@action.revenue_at_risk, @customer)
    @days_since_order   = days_since_last_order(@customer)

    owner_email = owner_email_for(@shop)

    mail(
      to:      owner_email,
      subject: subject_line
    )
  end

  private

  def subject_line
    risk_label = @action.risk_tier == "high" ? "⚠️" : "●"
    "#{risk_label} #{@customer.display_name} is at risk · #{@revenue_formatted} revenue"
  end

  def format_currency(amount, customer)
    currency = customer.orders.first&.currency || "EUR"
    symbol   = currency == "EUR" ? "€" : currency
    "#{symbol}#{amount.round(0).to_i}"
  end

  def days_since_last_order(customer)
    last_order = customer.orders.paid.order(ordered_at: :desc).first
    return nil unless last_order

    (Date.current - last_order.ordered_at.to_date).to_i
  end

  def owner_email_for(shop)
    shop.owner_email.presence ||
      ENV.fetch("OWNER_EMAIL_OVERRIDE", "owner@#{shop.shopify_domain.sub('.myshopify.com', '.com')}")
  end
end
