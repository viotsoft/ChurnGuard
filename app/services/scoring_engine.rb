# ScoringEngine — RFM-based customer risk tier calculation
#
# Algorithm (all thresholds from config/scoring.yml — do not hardcode here):
#   1. Recency tier:   days since last paid order > 180 → high, > 90 → medium, else low
#   2. Frequency tier: paid order count == 1 → high, 2–4 → medium, 5+ → low
#   3. Combined tier:  worst of (recency, frequency)
#   4. Monetary adj:   combined=high + above median LTV → reduce to medium
#                      combined=low  + below median LTV → raise  to medium
#                      medium stays medium (monetary never moves the needle two levels)
#
# Data guard: shops with <10 customers or <30 paid orders are skipped (onboarding state).
# Customers without any paid orders are excluded from scoring (LEFT JOIN → HAVING).
#
# Regression-pinned: spec/scoring/golden_fixtures_spec.rb asserts all 10 canonical
# customer profiles produce the expected tier. Any threshold change that moves a
# fixture must update that spec explicitly — the diff shows in code review.
class ScoringEngine
  TIER_RANK = { "high" => 2, "medium" => 1, "low" => 0 }.freeze

  def self.call(shop:)
    new(shop: shop).call
  end

  def initialize(shop:)
    @shop   = shop
    @config = Rails.application.config_for(:scoring)
  end

  def call
    unless sufficient_data?
      Rails.logger.info(
        "[ScoringEngine] Skipping #{@shop.shopify_domain} — insufficient data " \
        "(customers=#{@shop.customers.count}, paid_orders=#{@shop.orders.paid.count})"
      )
      return { status: :skipped, reason: :insufficient_data }
    end

    rfm_rows   = fetch_rfm_data
    median_ltv = compute_median_ltv

    rfm_rows.each do |row|
      tier = calculate_tier(row, median_ltv)
      Customer.where(id: row[:customer_id])
              .update_all(risk_tier: tier, last_scored_on: Date.current)
    end

    Rails.logger.info(
      "[ScoringEngine] Scored #{rfm_rows.size} customers for #{@shop.shopify_domain} " \
      "(median_ltv=#{median_ltv.round(2)})"
    )

    { status: :scored, count: rfm_rows.size }
  end

  private

  # ── Data sufficiency ────────────────────────────────────────────────────────

  def sufficient_data?
    @shop.customers.count >= @config[:minimum_customers] &&
      @shop.orders.paid.count >= @config[:minimum_orders]
  end

  # ── Bulk RFM query ──────────────────────────────────────────────────────────
  # Single query per shop; returns one row per customer with at least 1 paid order.

  def fetch_rfm_data
    sql = <<~SQL
      SELECT
        c.id                                                            AS customer_id,
        c.lifetime_value,
        EXTRACT(EPOCH FROM (NOW() - MAX(o.ordered_at)))::bigint / 86400 AS days_since_last_order,
        COUNT(o.id) FILTER (WHERE o.status = 'paid')                    AS paid_order_count
      FROM customers c
      LEFT JOIN orders o ON o.customer_id = c.id AND o.shop_id = c.shop_id
      WHERE c.shop_id = $1
      GROUP BY c.id, c.lifetime_value
      HAVING COUNT(o.id) FILTER (WHERE o.status = 'paid') > 0
    SQL

    binds  = [ActiveRecord::Relation::QueryAttribute.new(
      "shop_id", @shop.id, ActiveRecord::Type::Integer.new
    )]
    result = ActiveRecord::Base.connection.exec_query(sql, "ScoringEngine RFM", binds)

    result.map do |row|
      {
        customer_id:           row["customer_id"].to_i,
        lifetime_value:        row["lifetime_value"].to_f,
        days_since_last_order: row["days_since_last_order"].to_i,
        paid_order_count:      row["paid_order_count"].to_i
      }
    end
  end

  # Median LTV across all customers in the shop.
  # Returns 0.0 on empty — safe because monetary adjustment is skipped when median ≤ 0.
  def compute_median_ltv
    ltvs = @shop.customers.pluck(:lifetime_value).map(&:to_f).compact.sort
    return 0.0 if ltvs.empty?

    mid = ltvs.size / 2
    ltvs.size.odd? ? ltvs[mid] : (ltvs[mid - 1] + ltvs[mid]) / 2.0
  end

  # ── Tier calculation ────────────────────────────────────────────────────────

  def calculate_tier(row, median_ltv)
    r_tier   = recency_tier_for(row[:days_since_last_order])
    f_tier   = frequency_tier_for(row[:paid_order_count])
    combined = [r_tier, f_tier].max_by { |t| TIER_RANK.fetch(t, 0) }

    apply_monetary_adjustment(combined, row[:lifetime_value], median_ltv)
  end

  def recency_tier_for(days)
    if days > @config.dig(:recency, :high_risk_days)
      "high"
    elsif days > @config.dig(:recency, :medium_risk_days)
      "medium"
    else
      "low"
    end
  end

  def frequency_tier_for(count)
    if count <= @config.dig(:frequency, :high_risk_orders)
      "high"
    elsif count <= @config.dig(:frequency, :medium_risk_max)
      "medium"
    else
      "low"
    end
  end

  # Monetary adjustment rules — calibrated against golden fixtures:
  #   HIGH + above/at median → MEDIUM  (valuable customer; ease off)
  #   LOW  + below median    → MEDIUM  (low spender drifting; flag for attention)
  #   MEDIUM stays MEDIUM regardless (monetary can't move the needle two levels)
  def apply_monetary_adjustment(tier, ltv, median_ltv)
    return tier unless @config.dig(:monetary, :below_median_bumps_tier)
    return tier if median_ltv <= 0.0

    below_median = ltv < median_ltv

    case tier
    when "high" then below_median ? "high" : "medium"
    when "low"  then below_median ? "medium" : "low"
    else             "medium"
    end
  end
end
