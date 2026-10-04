require "rails_helper"

# ── Golden Fixture Regression Tests ──────────────────────────────────────────
#
# These 10 canonical customer profiles are pinned to known expected tiers.
# They act as a regression gate: any change to config/scoring.yml that moves
# a fixture's tier MUST update the expectations below explicitly — visible in
# the git diff during code review. This is intentional friction.
#
# Thresholds (current config/scoring.yml):
#   Recency:   > 180 days → high, > 90 days → medium, ≤ 90 → low
#   Frequency: 1 order → high, 2–4 → medium, 5+ → low
#   Monetary:  combined=high + above/at median (270) → medium
#              combined=low  + below median       → medium
#              combined=medium → unchanged
#
# Median LTV across these 10 profiles: 270.0
# (sorted: 89, 130, 145, 210, 220, 320, 480, 750, 890, 1840 → avg(220,320)=270)
#
# DO NOT CHANGE expected_tier values without also updating config/scoring.yml
# and documenting why in the PR. These pins are the source of truth for scoring.

GOLDEN_FIXTURES = [
  #                                  days  orders  ltv      tier
  { name: "Maria Kowalski",     days: 207, orders: 1,  ltv: 89.0,    expected_tier: "high"   },
  { name: "Jan Nowak",          days: 195, orders: 2,  ltv: 145.0,   expected_tier: "high"   },
  { name: "Anna Wiśniewska",    days: 182, orders: 1,  ltv: 220.0,   expected_tier: "high"   },
  { name: "Piotr Zieliński",    days: 95,  orders: 2,  ltv: 210.0,   expected_tier: "medium" },
  { name: "Karolina Dąbrowska", days: 93,  orders: 4,  ltv: 130.0,   expected_tier: "medium" },
  { name: "Tomasz Wójcik",      days: 88,  orders: 1,  ltv: 890.0,   expected_tier: "medium" },
  { name: "Zofia Lewandowska",  days: 30,  orders: 5,  ltv: 750.0,   expected_tier: "low"    },
  { name: "Marek Kamiński",     days: 14,  orders: 8,  ltv: 480.0,   expected_tier: "low"    },
  { name: "Ewa Kowalczyk",      days: 7,   orders: 12, ltv: 1840.0,  expected_tier: "low"    },
  { name: "Bartosz Szymański",  days: 45,  orders: 6,  ltv: 320.0,   expected_tier: "low"    },
].freeze

RSpec.describe ScoringEngine, type: :service do
  describe "golden fixture regression" do
    let(:shop) { create(:shop) }

    # Runs once before every fixture example.
    # Creates all 10 fixture customers + their orders, then calls the engine.
    before do
      RlsContext.set!(shop.id)

      GOLDEN_FIXTURES.each do |fx|
        customer = create(:customer,
                          shop:           shop,
                          name:           fx[:name],
                          lifetime_value: fx[:ltv])

        # First (most-recent) paid order exactly fx[:days] days ago.
        # Subsequent orders are spread 30 days further back so MAX(ordered_at)
        # correctly reflects the fixture's recency.
        fx[:orders].times.each_with_index do |_, i|
          create(:order,
                 shop:       shop,
                 customer:   customer,
                 status:     "paid",
                 amount:     (fx[:ltv] / fx[:orders]).round(2),
                 ordered_at: (fx[:days] + i * 30).days.ago)
        end
      end

      described_class.call(shop: shop)
    end

    GOLDEN_FIXTURES.each do |fx|
      it "assigns #{fx[:expected_tier].upcase} to #{fx[:name]} " \
         "(#{fx[:days]}d, #{fx[:orders]} orders, LTV #{fx[:ltv]})" do
        customer = Customer.find_by!(shop: shop, name: fx[:name])
        expect(customer.risk_tier).to eq(fx[:expected_tier]),
          "#{fx[:name]}: expected #{fx[:expected_tier].upcase} but got #{customer.risk_tier&.upcase} " \
          "(#{fx[:days]}d, #{fx[:orders]} orders, LTV #{fx[:ltv]})"
      end
    end

    it "stamps last_scored_on = today for all 10 fixture customers" do
      shop.customers.find_each do |customer|
        expect(customer.last_scored_on).to eq(Date.current),
          "#{customer.name} was not stamped with last_scored_on"
      end
    end

    it "returns status: :scored with count = #{GOLDEN_FIXTURES.size}" do
      # Engine is idempotent — re-running overwrites tiers with the same values.
      result = described_class.call(shop: shop)
      expect(result[:status]).to eq(:scored)
      expect(result[:count]).to eq(GOLDEN_FIXTURES.size)
    end
  end
end
