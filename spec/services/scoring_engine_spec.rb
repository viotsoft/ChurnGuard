require "rails_helper"

RSpec.describe ScoringEngine, type: :service do
  let(:shop) { create(:shop) }

  before { RlsContext.set!(shop.id) }

  # ── Helpers ─────────────────────────────────────────────────────────────────

  # Creates a customer and N paid orders, ensuring the most recent order lands
  # exactly `days_ago` days in the past (± a few seconds; safe given ≥5-day margins).
  def create_customer_with_orders(days_ago:, order_count:, lifetime_value:)
    customer = create(:customer, shop: shop, lifetime_value: lifetime_value)

    order_count.times.each_with_index do |_, i|
      # Most recent order at days_ago, older orders spread further back
      ordered_at = (days_ago + i * 30).days.ago
      create(:order,
             shop:       shop,
             customer:   customer,
             status:     "paid",
             amount:     (lifetime_value / order_count).round(2),
             ordered_at: ordered_at)
    end

    customer
  end

  # Creates filler data so the shop passes the minimum data guard
  # (10 customers, 30 paid orders) without affecting median LTV.
  # Filler LTVs average to ~500 to form a known median when combined with test customers.
  def create_filler_data(customer_count: 10, orders_per_customer: 3, ltv: 500.0)
    customer_count.times do
      c = create(:customer, shop: shop, lifetime_value: ltv)
      orders_per_customer.times do
        create(:order, shop: shop, customer: c, status: "paid",
               amount: (ltv / orders_per_customer).round(2),
               ordered_at: 10.days.ago)
      end
    end
  end

  # ── Minimum data guard ───────────────────────────────────────────────────────

  describe "minimum data guard" do
    it "returns :skipped when shop has fewer than 10 customers" do
      create_list(:customer, 5, shop: shop)

      result = described_class.call(shop: shop)

      expect(result).to eq(status: :skipped, reason: :insufficient_data)
    end

    it "returns :skipped when shop has < 30 paid orders even with enough customers" do
      create_list(:customer, 10, shop: shop)
      # Only 5 paid orders
      create_list(:order, 5, shop: shop, customer: shop.customers.first, status: "paid")

      result = described_class.call(shop: shop)

      expect(result).to eq(status: :skipped, reason: :insufficient_data)
    end

    it "returns :scored when minimum thresholds are met" do
      create_filler_data(customer_count: 10, orders_per_customer: 3)

      result = described_class.call(shop: shop)

      expect(result[:status]).to eq(:scored)
    end

    it "does not update customer tiers when skipped" do
      customer = create(:customer, shop: shop, risk_tier: nil)
      # Insufficient data
      result = described_class.call(shop: shop)

      expect(result[:status]).to eq(:skipped)
      expect(customer.reload.risk_tier).to be_nil
    end
  end

  # ── Recency-driven tiers ────────────────────────────────────────────────────

  describe "recency tier" do
    before { create_filler_data }

    it "assigns high when last order > 180 days ago" do
      # LTV below filler median (500) so monetary adjustment does not save to medium.
      customer = create_customer_with_orders(days_ago: 200, order_count: 5,
                                             lifetime_value: 80.0)
      described_class.call(shop: shop)

      expect(customer.reload.risk_tier).to eq("high")
    end

    it "assigns medium when last order is between 90–180 days ago" do
      customer = create_customer_with_orders(days_ago: 120, order_count: 5,
                                             lifetime_value: 500.0)
      described_class.call(shop: shop)

      expect(customer.reload.risk_tier).to eq("medium")
    end

    it "assigns low when last order < 90 days ago (and frequent)" do
      customer = create_customer_with_orders(days_ago: 30, order_count: 6,
                                             lifetime_value: 500.0)
      described_class.call(shop: shop)

      expect(customer.reload.risk_tier).to eq("low")
    end
  end

  # ── Frequency-driven tiers ──────────────────────────────────────────────────

  describe "frequency tier" do
    before { create_filler_data }

    it "assigns high for exactly 1 paid order (regardless of recency)" do
      # LTV below filler median (500) so monetary adjustment does not save to medium.
      customer = create_customer_with_orders(days_ago: 10, order_count: 1,
                                             lifetime_value: 80.0)
      described_class.call(shop: shop)

      expect(customer.reload.risk_tier).to eq("high")
    end

    it "assigns medium for 2–4 paid orders combined with medium recency" do
      customer = create_customer_with_orders(days_ago: 100, order_count: 3,
                                             lifetime_value: 500.0)
      described_class.call(shop: shop)

      expect(customer.reload.risk_tier).to eq("medium")
    end

    it "assigns low for 5+ paid orders with recent purchase" do
      customer = create_customer_with_orders(days_ago: 15, order_count: 7,
                                             lifetime_value: 500.0)
      described_class.call(shop: shop)

      expect(customer.reload.risk_tier).to eq("low")
    end
  end

  # ── Monetary adjustment ──────────────────────────────────────────────────────

  describe "monetary adjustment" do
    # Build a shop where median LTV is ~500. Filler customers have ltv=500,
    # so median is predictable and test customers' ltv can be above/below.
    before { create_filler_data(customer_count: 10, orders_per_customer: 3, ltv: 500.0) }

    it "saves a high-risk customer to medium when LTV is above the shop median" do
      # Recency: HIGH (200d), Frequency: HIGH (1 order) → combined HIGH
      # Monetary: 1200 > 500 median → reduce to MEDIUM
      customer = create_customer_with_orders(days_ago: 200, order_count: 1,
                                             lifetime_value: 1200.0)
      described_class.call(shop: shop)

      expect(customer.reload.risk_tier).to eq("medium")
    end

    it "bumps a low-risk customer to medium when LTV is below the shop median" do
      # Recency: LOW (20d), Frequency: LOW (6 orders) → combined LOW
      # Monetary: 50 < 500 median → raise to MEDIUM
      customer = create_customer_with_orders(days_ago: 20, order_count: 6,
                                             lifetime_value: 50.0)
      described_class.call(shop: shop)

      expect(customer.reload.risk_tier).to eq("medium")
    end

    it "leaves medium-tier customers unchanged regardless of LTV" do
      # Recency: MEDIUM (100d), Frequency: MEDIUM (2 orders) → combined MEDIUM
      # LTV far below median should not push to HIGH
      customer = create_customer_with_orders(days_ago: 100, order_count: 2,
                                             lifetime_value: 10.0)
      described_class.call(shop: shop)

      expect(customer.reload.risk_tier).to eq("medium")
    end

    it "leaves low-risk customer as low when LTV is at or above median" do
      # Recency: LOW (20d), Frequency: LOW (6 orders) → combined LOW
      # Monetary: 800 > 500 median → stays LOW
      customer = create_customer_with_orders(days_ago: 20, order_count: 6,
                                             lifetime_value: 800.0)
      described_class.call(shop: shop)

      expect(customer.reload.risk_tier).to eq("low")
    end
  end

  # ── Metadata updates ────────────────────────────────────────────────────────

  describe "last_scored_on" do
    before { create_filler_data }

    it "stamps last_scored_on with today's date" do
      customer = create_customer_with_orders(days_ago: 50, order_count: 3,
                                             lifetime_value: 500.0)
      described_class.call(shop: shop)

      expect(customer.reload.last_scored_on).to eq(Date.current)
    end
  end

  # ── Exclusions ──────────────────────────────────────────────────────────────

  describe "customers without paid orders" do
    before { create_filler_data }

    it "does not score customers who have never placed a paid order" do
      customer = create(:customer, shop: shop, risk_tier: nil, lifetime_value: 0)
      # Cancelled order only — should not appear in RFM query
      create(:order, shop: shop, customer: customer, status: "cancelled",
             amount: 100.0, ordered_at: 30.days.ago)

      described_class.call(shop: shop)

      expect(customer.reload.risk_tier).to be_nil
    end

    it "does not score customers with no orders at all" do
      customer = create(:customer, shop: shop, risk_tier: nil, lifetime_value: 0)

      described_class.call(shop: shop)

      expect(customer.reload.risk_tier).to be_nil
    end
  end

  # ── Return value ─────────────────────────────────────────────────────────────

  describe "return value" do
    before { create_filler_data }

    it "returns status: :scored with count of customers scored" do
      create_customer_with_orders(days_ago: 50, order_count: 3, lifetime_value: 500.0)
      result = described_class.call(shop: shop)

      expect(result[:status]).to eq(:scored)
      expect(result[:count]).to be >= 1
    end
  end
end
