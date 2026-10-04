# frozen_string_literal: true

require "rails_helper"

RSpec.describe OnlineRetailMlDemoImporter do
  let(:export_dir) { Rails.root.join("spec/fixtures/files/online_retail_ml_demo") }
  let(:shopify_domain) { "online-retail-ii-test.myshopify.com" }

  subject(:importer) { described_class.new(export_dir: export_dir, shopify_domain: shopify_domain) }

  it "imports customers, orders, ML predictions, and pending actions" do
    result = importer.call
    shop = result.shop

    expect(result.customers_imported).to eq(3)
    expect(result.orders_imported).to eq(4)
    expect(result.predictions_imported).to eq(3)
    expect(result.actions_created).to eq(2)
    expect(result.actions_updated).to eq(0)

    expect(shop.customers.count).to eq(3)
    expect(shop.orders.count).to eq(4)
    expect(shop.actions.pending.count).to eq(2)

    high_risk_customer = shop.customers.find_by!(shopify_customer_id: "1001")
    expect(high_risk_customer.risk_score).to eq(BigDecimal("0.9210"))
    expect(high_risk_customer.risk_tier).to eq("high")
    expect(high_risk_customer.last_scored_on).to eq(Date.new(2011, 12, 9))

    high_risk_action = shop.actions.find_by!(customer: high_risk_customer)
    expect(high_risk_action.risk_tier).to eq("high")
    expect(high_risk_action.proposed_discount).to eq("15%")
    expect(high_risk_action.revenue_at_risk).to eq(BigDecimal("387.28"))
    expect(high_risk_action.reason).to include("ML v2 predicts 92% churn risk")

    low_risk_customer = shop.customers.find_by!(shopify_customer_id: "1003")
    expect(shop.actions.find_by(customer: low_risk_customer)).to be_nil
  end

  it "is idempotent for customers, orders, and pending actions" do
    first = importer.call
    second = importer.call

    shop = second.shop

    expect(shop.customers.count).to eq(3)
    expect(shop.orders.count).to eq(4)
    expect(shop.actions.pending.count).to eq(2)
    expect(second.actions_created).to eq(0)
    expect(second.actions_updated).to eq(2)
    expect(first.shop.id).to eq(second.shop.id)
  end

  it "raises a clear error when exports are missing" do
    missing_dir = Rails.root.join("tmp/missing-online-retail-exports")

    expect do
      described_class.new(export_dir: missing_dir, shopify_domain: shopify_domain).call
    end.to raise_error(ArgumentError, /Missing ML demo export/)
  end
end
