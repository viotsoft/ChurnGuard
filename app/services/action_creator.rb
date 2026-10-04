# ActionCreator — produces Action records + approval emails for at-risk customers.
#
# Called by DailyScoringJob after ScoringEngine has updated customer risk tiers.
# For each HIGH or MEDIUM risk customer in the shop:
#   1. INSERT into actions (partial unique index prevents duplicate pending actions)
#   2. Generate a signed JWT ApprovalToken (72h TTL, single-use)
#   3. Deliver ApprovalMailer.notify_owner via Sidekiq (notifications queue)
#
# Idempotent by design: if a customer already has a pending action, the DB unique
# index raises RecordNotUnique → rescued and logged → customer is skipped silently.
# This means re-running after a crash is always safe.
class ActionCreator
  # Discount level by risk tier (shown in email + executed by Klaviyo)
  DISCOUNT_BY_TIER = { "high" => "15%", "medium" => "10%" }.freeze

  def self.call(shop:)
    new(shop: shop).call
  end

  def initialize(shop:)
    @shop = shop
  end

  def call
    at_risk = @shop.customers.at_risk.includes(:orders)
    created  = 0

    at_risk.find_each do |customer|
      action = build_action(customer)
      next unless action   # duplicate pending action — skip

      raw_jwt = ApprovalToken.generate_for!(action: action)
      ApprovalMailer.notify_owner(action: action, token: raw_jwt).deliver_later
      created += 1
    end

    Rails.logger.info(
      "[ActionCreator] Created #{created} actions for #{@shop.shopify_domain} " \
      "(#{at_risk.count} at-risk customers evaluated)"
    )

    { created: created }
  end

  private

  # Attempts to insert a pending Action. Returns nil on duplicate (idempotent).
  def build_action(customer)
    Action.create!(
      shop:              @shop,
      customer:          customer,
      action_type:       "klaviyo_campaign",
      status:            "pending",
      risk_tier:         customer.risk_tier,
      revenue_at_risk:   customer.lifetime_value.to_f,
      proposed_discount: DISCOUNT_BY_TIER.fetch(customer.risk_tier, "10%"),
      reason:            compute_reason(customer),
      expires_at:        72.hours.from_now
    )
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    # Partial unique index: one_pending_per_customer ON actions(shop_id, customer_id)
    # WHERE status = 'pending'. Second call for the same customer is a silent no-op.
    Rails.logger.info(
      "[ActionCreator] Pending action already exists for customer #{customer.id} — skipped"
    )
    nil
  end

  # Human-readable risk reason shown in the email and dashboard card.
  # Computed from the customer's last paid order and order count.
  def compute_reason(customer)
    paid_orders = customer.orders.select { |o| o.status == "paid" }
    order_count = paid_orders.size
    last_order  = paid_orders.max_by(&:ordered_at)

    if last_order.nil?
      return "Customer signed up but has never placed an order"
    end

    days_ago = (Date.current - last_order.ordered_at.to_date).to_i

    case customer.risk_tier
    when "high"
      if days_ago > 180
        "Last ordered #{days_ago} days ago — likely to be lost to a competitor without action"
      else
        "Only #{pluralize(order_count, 'order')} ever — needs encouragement to become a repeat buyer"
      end
    when "medium"
      if days_ago > 90
        "Last ordered #{days_ago} days ago — showing early signs of drifting away"
      else
        "Purchase frequency is lower than expected for a customer at this spend level"
      end
    else
      "Customer is showing signs of churn risk"
    end
  end

  def pluralize(count, word)
    count == 1 ? "#{count} #{word}" : "#{count} #{word}s"
  end
end
