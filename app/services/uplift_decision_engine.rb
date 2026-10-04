require "zlib"

# UpliftDecisionEngine — demo-ready decision layer for ChurnGuard Uplift V3.
#
# This service does not replace the RFM/ML churn baseline. It sits one level
# later in the workflow: given scored customers, estimate whether a concrete
# retention treatment is worth sending and create approval cards only for
# positive expected incremental revenue.
class UpliftDecisionEngine
  MODEL_VERSION = "uplift-v3-demo-baseline"
  OUTCOME_WINDOW_DAYS = 30
  MIN_EXPECTED_INCREMENTAL_REVENUE = 10.0
  DEFAULT_HOLDOUT_RATE = 0.10

  TREATMENTS = {
    "winback_15" => {
      discount: "15%",
      cost_rate: 0.15,
      label: "15% win-back offer"
    },
    "nudge_10" => {
      discount: "10%",
      cost_rate: 0.10,
      label: "10% repeat-purchase nudge"
    },
    "vip_personal_offer" => {
      discount: "12%",
      cost_rate: 0.12,
      label: "VIP personal offer"
    }
  }.freeze

  Decision = Struct.new(
    :customer,
    :treatment_key,
    :risk_tier,
    :uplift_score,
    :expected_incremental_revenue,
    :revenue_at_risk,
    :proposed_discount,
    :reason,
    :holdout,
    keyword_init: true
  )

  def self.call(shop:, holdout_rate: DEFAULT_HOLDOUT_RATE)
    new(shop: shop, holdout_rate: holdout_rate).call
  end

  def initialize(shop:, holdout_rate: DEFAULT_HOLDOUT_RATE)
    @shop = shop
    @holdout_rate = holdout_rate.to_f.clamp(0.0, 1.0)
  end

  def call
    counters = Hash.new(0)

    eligible_customers.find_each do |customer|
      decision = decision_for(customer)

      if decision.expected_incremental_revenue < MIN_EXPECTED_INCREMENTAL_REVENUE
        counters[:below_threshold] += 1
        next
      end

      if decision.holdout
        counters[:holdout] += 1
        next
      end

      action, was_new = build_action(decision)
      next unless action

      if was_new
        raw_jwt = ApprovalToken.generate_for!(action: action)
        ApprovalMailer.notify_owner(action: action, token: raw_jwt).deliver_later
        counters[:created] += 1
      else
        counters[:updated] += 1
      end
    end

    Rails.logger.info(
      "[UpliftDecisionEngine] Created #{counters[:created]} uplift actions for " \
      "#{@shop.shopify_domain} (holdout=#{counters[:holdout]}, " \
      "below_threshold=#{counters[:below_threshold]})"
    )

    counters
  end

  def decisions
    eligible_customers.map { |customer| decision_for(customer) }
  end

  private

  def eligible_customers
    @shop.customers
         .at_risk
         .includes(:orders)
         .where.not(lifetime_value: nil)
  end

  def build_action(decision)
    action = @shop.actions.pending.find_or_initialize_by(customer: decision.customer)
    was_new = action.new_record?

    action.assign_attributes(
      action_type: "klaviyo_campaign",
      status: "pending",
      risk_tier: decision.risk_tier,
      revenue_at_risk: decision.revenue_at_risk,
      proposed_discount: decision.proposed_discount,
      reason: decision.reason,
      expires_at: 72.hours.from_now,
      treatment_key: decision.treatment_key,
      uplift_score: decision.uplift_score,
      expected_incremental_revenue: decision.expected_incremental_revenue,
      model_version: MODEL_VERSION,
      holdout: false,
      outcome_window_days: OUTCOME_WINDOW_DAYS
    )
    action.save!
    [action, was_new]
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    Rails.logger.info(
      "[UpliftDecisionEngine] Pending action already exists for customer " \
      "#{decision.customer.id} — skipped"
    )
    [nil, false]
  end

  def decision_for(customer)
    treatment_key = treatment_for(customer)
    uplift_score = estimate_uplift(customer, treatment_key)
    expected_revenue = expected_incremental_revenue(customer, treatment_key, uplift_score)
    risk_tier = customer.risk_tier.presence || "medium"

    Decision.new(
      customer: customer,
      treatment_key: treatment_key,
      risk_tier: risk_tier,
      uplift_score: uplift_score,
      expected_incremental_revenue: expected_revenue,
      revenue_at_risk: [expected_revenue, customer.lifetime_value.to_f * 0.25].max.round(2),
      proposed_discount: TREATMENTS.fetch(treatment_key).fetch(:discount),
      reason: reason_for(customer, treatment_key, uplift_score, expected_revenue),
      holdout: holdout?(customer, treatment_key)
    )
  end

  def treatment_for(customer)
    orders = paid_orders(customer)
    recency_days = days_since_last_order(orders)
    frequency = orders.size

    if customer.lifetime_value.to_f >= shop_median_ltv * 1.4 && frequency >= 3
      "vip_personal_offer"
    elsif recency_days >= 150 || customer.risk_tier == "high"
      "winback_15"
    else
      "nudge_10"
    end
  end

  def estimate_uplift(customer, treatment_key)
    orders = paid_orders(customer)
    recency_days = days_since_last_order(orders)
    frequency = orders.size
    risk_score = customer.risk_score&.to_f || fallback_risk_score(customer.risk_tier)

    recency_component = [[recency_days / 240.0, 0.0].max, 1.0].min * 0.08
    frequency_component = frequency <= 1 ? 0.045 : 0.025
    risk_component = risk_score * 0.075
    value_component = customer.lifetime_value.to_f >= shop_median_ltv ? 0.025 : 0.01
    treatment_component = case treatment_key
                          when "winback_15" then 0.035
                          when "vip_personal_offer" then 0.03
                          else 0.02
                          end

    (recency_component + frequency_component + risk_component +
      value_component + treatment_component).clamp(0.02, 0.32).round(4)
  end

  def expected_incremental_revenue(customer, treatment_key, uplift_score)
    expected_order_value = average_order_value(customer)
    incentive_cost = expected_order_value * TREATMENTS.fetch(treatment_key).fetch(:cost_rate)
    ((uplift_score * expected_order_value) - (uplift_score * incentive_cost)).round(2)
  end

  def reason_for(customer, treatment_key, uplift_score, expected_revenue)
    treatment_label = TREATMENTS.fetch(treatment_key).fetch(:label)
    percent = (uplift_score * 100).round(1)
    amount = expected_revenue.round

    "Uplift V3 estimates +#{percent}% incremental purchase lift from a " \
      "#{treatment_label}. Expected incremental revenue: €#{amount} over " \
      "#{OUTCOME_WINDOW_DAYS} days."
  end

  def holdout?(customer, treatment_key)
    return false if @holdout_rate.zero?

    seed = "#{@shop.id}:#{customer.id}:#{treatment_key}:#{MODEL_VERSION}"
    bucket = Zlib.crc32(seed) % 10_000
    bucket < (@holdout_rate * 10_000)
  end

  def paid_orders(customer)
    customer.orders.select { |order| order.status == "paid" }
  end

  def days_since_last_order(orders)
    last_order = orders.max_by(&:ordered_at)
    return 365 unless last_order

    (Date.current - last_order.ordered_at.to_date).to_i.clamp(0, 365)
  end

  def average_order_value(customer)
    orders = paid_orders(customer)
    return [customer.lifetime_value.to_f, 75.0].max if orders.empty?

    [orders.sum { |order| order.amount.to_f } / orders.size, 25.0].max
  end

  def shop_median_ltv
    @shop_median_ltv ||= begin
      values = @shop.customers.pluck(:lifetime_value).map(&:to_f).sort
      if values.empty?
        0.0
      else
        mid = values.size / 2
        values.size.odd? ? values[mid] : (values[mid - 1] + values[mid]) / 2.0
      end
    end
  end

  def fallback_risk_score(risk_tier)
    case risk_tier
    when "high" then 0.82
    when "medium" then 0.58
    else 0.25
    end
  end
end
