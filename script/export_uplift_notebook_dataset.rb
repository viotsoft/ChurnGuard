# frozen_string_literal: true

require "csv"

# Export the current ChurnGuard demo shop into notebook-friendly CSV files.
#
# Usage:
#   bin/rails runner script/export_uplift_notebook_dataset.rb
#   DEMO_SHOP=warsawstyle.myshopify.com bin/rails runner script/export_uplift_notebook_dataset.rb

domain = ENV.fetch("DEMO_SHOP", "warsawstyle.myshopify.com")
out_dir = Rails.root.join("research/uplift_v3_notebook/data")
FileUtils.mkdir_p(out_dir)

shop = Shop.find_by!(shopify_domain: domain)
RlsContext.set!(shop.id)

customers_path = out_dir.join("current_app_customers.csv")
orders_path = out_dir.join("current_app_orders.csv")
actions_path = out_dir.join("current_app_actions.csv")

CSV.open(customers_path, "w") do |csv|
  csv << %w[
    shopify_customer_id name email lifetime_value days_since_last_order
    frequency aov risk_tier risk_score last_scored_on
  ]

  shop.customers.includes(:orders).order(:shopify_customer_id).find_each do |customer|
    paid_orders = customer.orders.select { |order| order.status == "paid" }
    last_order = paid_orders.max_by(&:ordered_at)
    days_since_last_order = last_order ? (Date.current - last_order.ordered_at.to_date).to_i : nil
    frequency = paid_orders.size
    aov = frequency.positive? ? paid_orders.sum { |order| order.amount.to_f } / frequency : 0.0

    csv << [
      customer.shopify_customer_id,
      customer.name,
      customer.email,
      customer.lifetime_value.to_f.round(2),
      days_since_last_order,
      frequency,
      aov.round(2),
      customer.risk_tier,
      customer.risk_score&.to_f,
      customer.last_scored_on
    ]
  end
end

CSV.open(orders_path, "w") do |csv|
  csv << %w[shopify_order_id shopify_customer_id amount currency status ordered_at]

  shop.orders.includes(:customer).order(:shopify_order_id).find_each do |order|
    csv << [
      order.shopify_order_id,
      order.customer.shopify_customer_id,
      order.amount.to_f.round(2),
      order.currency,
      order.status,
      order.ordered_at&.to_date
    ]
  end
end

CSV.open(actions_path, "w") do |csv|
  csv << %w[
    shopify_customer_id status treatment_key risk_tier uplift_score
    expected_incremental_revenue revenue_at_risk proposed_discount
    model_version holdout outcome_window_days
  ]

  shop.actions.includes(:customer).order(created_at: :desc).find_each do |action|
    csv << [
      action.customer.shopify_customer_id,
      action.status,
      action.treatment_key,
      action.risk_tier,
      action.uplift_score&.to_f,
      action.expected_incremental_revenue&.to_f,
      action.revenue_at_risk&.to_f,
      action.proposed_discount,
      action.model_version,
      action.holdout,
      action.outcome_window_days
    ]
  end
end

puts "Exported notebook dataset for #{shop.shopify_domain}"
puts "  #{customers_path} (#{shop.customers.count} customers)"
puts "  #{orders_path} (#{shop.orders.count} orders)"
puts "  #{actions_path} (#{shop.actions.count} actions)"
