# frozen_string_literal: true

require "csv"

class OnlineRetailMlDemoImporter
  DEFAULT_SHOPIFY_DOMAIN = "online-retail-ii.myshopify.com"
  DEFAULT_EXPORT_DIR = Rails.root.join("research/exports")

  Result = Struct.new(
    :shop,
    :customers_imported,
    :orders_imported,
    :predictions_imported,
    :actions_created,
    :actions_updated,
    keyword_init: true
  )

  def initialize(export_dir: DEFAULT_EXPORT_DIR, shopify_domain: DEFAULT_SHOPIFY_DOMAIN)
    @export_dir = export_dir.is_a?(Pathname) ? export_dir : Pathname.new(export_dir.to_s)
    @shopify_domain = shopify_domain
  end

  def call
    assert_files_exist!

    counters = Hash.new(0)
    shop = nil

    ActiveRecord::Base.transaction do
      shop = find_or_create_shop!
      customers_by_external_id = import_customers(shop, counters)
      import_orders(shop, customers_by_external_id, counters)
      import_predictions(shop, customers_by_external_id, counters)
    end

    Result.new(
      shop: shop,
      customers_imported: counters[:customers],
      orders_imported: counters[:orders],
      predictions_imported: counters[:predictions],
      actions_created: counters[:actions_created],
      actions_updated: counters[:actions_updated]
    )
  end

  private

  attr_reader :export_dir, :shopify_domain

  def customers_path
    export_dir.join("online_retail_customers_v2.csv")
  end

  def orders_path
    export_dir.join("online_retail_orders_v2.csv")
  end

  def predictions_path
    export_dir.join("churnguard_predictions_v2.csv")
  end

  def assert_files_exist!
    [customers_path, orders_path, predictions_path].each do |path|
      raise ArgumentError, "Missing ML demo export: #{path}" unless path.exist?
    end
  end

  def find_or_create_shop!
    Shop.find_or_create_by!(shopify_domain: shopify_domain) do |shop|
      shop.shopify_token = "online-retail-ii-demo-token"
      shop.klaviyo_api_key = "pk_demo_online_retail_ii"
    end
  end

  def import_customers(shop, counters)
    customers_by_external_id = {}

    each_csv(customers_path) do |row|
      external_id = row.fetch("shopify_customer_id").to_s
      customer = shop.customers.find_or_initialize_by(shopify_customer_id: external_id)
      customer.assign_attributes(
        name: row["name"].presence || "Customer #{external_id}",
        email: row["email"].presence,
        lifetime_value: decimal(row["lifetime_value"]),
        risk_score: bounded_score(row["risk_score"]),
        risk_tier: normalized_risk_tier(row["risk_tier"]),
        last_scored_on: parse_date(row["scored_on"])
      )
      customer.save!
      customers_by_external_id[external_id] = customer
      counters[:customers] += 1
    end

    customers_by_external_id
  end

  def import_orders(shop, customers_by_external_id, counters)
    each_csv(orders_path) do |row|
      customer = customers_by_external_id.fetch(row.fetch("shopify_customer_id").to_s)
      order = shop.orders.find_or_initialize_by(shopify_order_id: row.fetch("shopify_order_id").to_s)
      order.assign_attributes(
        customer: customer,
        amount: decimal(row["amount"]),
        currency: row["currency"].presence || "EUR",
        status: row["status"].presence || "paid",
        ordered_at: Time.zone.parse(row.fetch("ordered_at").to_s)
      )
      order.save!
      counters[:orders] += 1
    end
  end

  def import_predictions(shop, customers_by_external_id, counters)
    each_csv(predictions_path) do |row|
      customer = customers_by_external_id.fetch(row.fetch("shopify_customer_id").to_s)
      risk_tier = normalized_risk_tier(row["risk_tier"])

      customer.update!(
        lifetime_value: decimal(row["lifetime_value"]),
        risk_score: bounded_score(row["risk_score"]),
        risk_tier: risk_tier,
        last_scored_on: parse_date(row["scored_on"])
      )
      counters[:predictions] += 1

      next unless %w[high medium].include?(risk_tier)

      action = shop.actions.pending.find_or_initialize_by(customer: customer)
      was_new = action.new_record?
      action.assign_attributes(
        action_type: "klaviyo_campaign",
        risk_tier: risk_tier,
        revenue_at_risk: decimal(row["revenue_at_risk"]),
        proposed_discount: row["proposed_discount"].presence || default_discount_for(risk_tier),
        reason: row["reason"].presence || default_reason_for(customer, row),
        expires_at: 72.hours.from_now
      )
      action.save!
      counters[was_new ? :actions_created : :actions_updated] += 1
    end
  end

  def each_csv(path, &block)
    CSV.foreach(path, headers: true) do |row|
      block.call(row.to_h.transform_keys { |key| key.to_s.strip })
    end
  end

  def decimal(value)
    BigDecimal(value.to_s.presence || "0")
  end

  def bounded_score(value)
    score = BigDecimal(value.to_s.presence || "0")
    [[score, BigDecimal("0")].max, BigDecimal("0.9999")].min
  end

  def normalized_risk_tier(value)
    tier = value.to_s.downcase.strip
    Customer::RISK_TIERS.include?(tier) ? tier : "low"
  end

  def parse_date(value)
    return Date.current if value.blank?

    Date.parse(value.to_s)
  end

  def default_discount_for(risk_tier)
    risk_tier == "high" ? "15%" : "10%"
  end

  def default_reason_for(customer, row)
    score = (bounded_score(row["risk_score"]) * 100).round
    "ML v2 predicts #{score}% churn risk for #{customer.display_name}."
  end
end
