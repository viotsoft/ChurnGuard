# frozen_string_literal: true

# Prepare a repeatable local showroom dataset for investor/customer demos.
#
# Usage:
#   bin/rails runner script/demo_prepare.rb
#   DEMO_SHOP=example.myshopify.com bin/rails runner script/demo_prepare.rb
#
# This creates realistic commerce data, runs the scorer, creates pending approval
# actions, and adds a small amount of completed action history so the dashboard,
# history, and insights screens all have real records to show.

domain = ENV.fetch("DEMO_SHOP", "warsawstyle.myshopify.com")
domain += ".myshopify.com" unless domain.include?(".")

puts "Preparing ChurnGuard demo shop: #{domain}"

if domain == "warsawstyle.myshopify.com"
  load Rails.root.join("db/seeds/synthetic_shop.rb")
else
  shop = Shop.find_or_create_by!(shopify_domain: domain) do |s|
    s.shopify_token = "demo_token_#{SecureRandom.hex(8)}"
  end
  shop.update!(
    owner_email: "owner@#{domain.sub('.myshopify.com', '')}.example",
    klaviyo_api_key: "pk_demo_#{SecureRandom.hex(12)}"
  )
end

shop = Shop.find_by!(shopify_domain: domain)
shop.update!(
  owner_email: shop.owner_email.presence || "owner@warsawstyle.example",
  klaviyo_api_key: shop.klaviyo_api_key.presence || "pk_demo_#{SecureRandom.hex(12)}"
)

RlsContext.set!(shop.id)

# Keep the showroom repeatable. This script is explicitly for local demos, so
# it resets previous approval/history records before preparing the Uplift V3
# scenario.
shop.actions.destroy_all

score_result = ScoringEngine.call(shop: shop)
uplift_result = UpliftDecisionEngine.call(shop: shop, holdout_rate: 0.0)

# Create a small, stable action history for the secondary screens. This is
# intentionally separate from the approval queue so the primary demo still opens
# to pending cards.
history_customers = shop.customers
                        .where.not(risk_tier: nil)
                        .order(lifetime_value: :desc)
                        .limit(8)

history_customers.each_with_index do |customer, index|
  status = index < 5 ? "executed" : "skipped"
  timestamp = (index + 2).days.ago

  action = shop.actions.find_or_initialize_by(
    customer: customer,
    status: status,
    created_at: timestamp
  )

  action.assign_attributes(
    action_type: "klaviyo_campaign",
    risk_tier: customer.risk_tier || "medium",
    revenue_at_risk: customer.lifetime_value.to_f,
    proposed_discount: customer.risk_tier == "high" ? "15%" : "10%",
    reason: "Demo history: Uplift V3 selected a retention offer with positive expected incremental revenue.",
    expires_at: 72.hours.from_now,
    approved_at: status == "executed" ? timestamp : nil,
    skipped_at: status == "skipped" ? timestamp : nil,
    executed_at: status == "executed" ? timestamp + 8.minutes : nil,
    updated_at: timestamp + 8.minutes,
    treatment_key: customer.risk_tier == "high" ? "winback_15" : "nudge_10",
    uplift_score: customer.risk_tier == "high" ? 0.184 : 0.121,
    expected_incremental_revenue: (customer.lifetime_value.to_f * (customer.risk_tier == "high" ? 0.18 : 0.12)).round(2),
    model_version: UpliftDecisionEngine::MODEL_VERSION,
    holdout: false,
    outcome_window_days: UpliftDecisionEngine::OUTCOME_WINDOW_DAYS
  )
  action.save!
end

pending_count = shop.actions.pending.count
history_count = shop.actions.where.not(status: "pending").count
revenue_at_risk = shop.actions.pending.sum(:revenue_at_risk).to_f
recovered_revenue = shop.actions.executed.sum(:revenue_at_risk).to_f

puts ""
puts "Demo shop ready"
puts "  Shop:              #{shop.shopify_domain}"
puts "  Customers:         #{shop.customers.count}"
puts "  Orders:            #{shop.orders.count}"
puts "  Scoring result:    #{score_result.inspect}"
puts "  Uplift V3:         #{uplift_result.inspect}"
puts "  Pending actions:   #{pending_count}"
puts "  History actions:   #{history_count}"
puts "  Revenue at risk:   €#{revenue_at_risk.round}"
puts "  Demo recovered:    €#{recovered_revenue.round}"
puts ""
puts "Open locally:"
puts "  http://localhost:3000/dev/login?shop=#{shop.shopify_domain}"
