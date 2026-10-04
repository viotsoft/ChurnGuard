require "rails_helper"

RSpec.describe UpliftDecisionEngine, type: :service do
  let(:shop) { create(:shop) }
  let(:customer) do
    create(
      :customer,
      shop: shop,
      lifetime_value: 620.0,
      risk_tier: "high",
      risk_score: 0.83
    )
  end

  before do
    RlsContext.set!(shop.id)
    create(:order, shop: shop, customer: customer, amount: 180.0, ordered_at: 210.days.ago)
    create(:order, shop: shop, customer: customer, amount: 220.0, ordered_at: 170.days.ago)
    create(:order, shop: shop, customer: customer, amount: 220.0, ordered_at: 160.days.ago)
  end

  describe ".call" do
    it "creates an uplift pending action with expected incremental revenue" do
      expect { described_class.call(shop: shop, holdout_rate: 0.0) }
        .to change(Action, :count).by(1)
        .and change(ApprovalToken, :count).by(1)

      action = Action.last
      expect(action).to be_uplift_decision
      expect(action.model_version).to eq(described_class::MODEL_VERSION)
      expect(action.treatment_key).to eq("winback_15")
      expect(action.expected_incremental_revenue).to be_positive
      expect(action.outcome_window_days).to eq(30)
      expect(action.reason).to include("Expected incremental revenue")
    end

    it "updates an existing pending action instead of creating a duplicate" do
      create(:action, shop: shop, customer: customer, risk_tier: "high")

      expect { described_class.call(shop: shop, holdout_rate: 0.0) }
        .not_to change(Action, :count)

      action = Action.find_by!(customer: customer, status: "pending")
      expect(action.model_version).to eq(described_class::MODEL_VERSION)
      expect(action.uplift_score).to be_present
    end

    it "does not create actions for holdout customers" do
      expect { described_class.call(shop: shop, holdout_rate: 1.0) }
        .not_to change(Action, :count)
    end
  end

  describe "#decisions" do
    it "returns explainable decisions without mutating the database" do
      engine = described_class.new(shop: shop, holdout_rate: 0.0)

      expect { @decisions = engine.decisions }.not_to change(Action, :count)

      decision = @decisions.first
      expect(decision.customer).to eq(customer)
      expect(decision.uplift_score).to be_between(0.02, 0.32)
      expect(decision.expected_incremental_revenue).to be_positive
    end
  end
end
