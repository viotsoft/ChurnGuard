require "rails_helper"

RSpec.describe ActionCreator, type: :service do
  let(:shop)     { create(:shop) }
  let(:customer) { create(:customer, shop: shop, lifetime_value: 89.0, risk_tier: "high") }

  before { RlsContext.set!(shop.id) }

  # ── Core behaviour ──────────────────────────────────────────────────────────

  describe ".call" do
    context "with at-risk customers" do
      before do
        create(:order, shop: shop, customer: customer, status: "paid",
               amount: 89.0, ordered_at: 200.days.ago)
        customer.update!(risk_tier: "high")
      end

      it "creates a pending Action for each at-risk customer" do
        expect { described_class.call(shop: shop) }
          .to change(Action, :count).by(1)
      end

      it "sets action fields correctly" do
        described_class.call(shop: shop)
        action = Action.last

        expect(action.shop).to eq(shop)
        expect(action.customer).to eq(customer)
        expect(action.action_type).to eq("klaviyo_campaign")
        expect(action.status).to eq("pending")
        expect(action.risk_tier).to eq("high")
        expect(action.proposed_discount).to eq("15%")
        expect(action.revenue_at_risk).to eq(customer.lifetime_value)
        expect(action.expires_at).to be_within(5.seconds).of(72.hours.from_now)
      end

      it "generates an ApprovalToken for each new action" do
        expect { described_class.call(shop: shop) }
          .to change(ApprovalToken, :count).by(1)
      end

      it "stores a token_hash (not the raw JWT) in the DB" do
        described_class.call(shop: shop)
        token = ApprovalToken.last

        expect(token.token_hash).to be_present
        expect(token.token_hash).to match(/\A[0-9a-f]{64}\z/)  # SHA-256 hex
      end

      it "enqueues an ApprovalMailer delivery" do
        expect { described_class.call(shop: shop) }
          .to have_enqueued_mail(ApprovalMailer, :notify_owner)
      end

      it "returns a hash with created count" do
        result = described_class.call(shop: shop)
        expect(result[:created]).to eq(1)
      end
    end

    context "with medium-risk customers" do
      let(:medium_customer) do
        create(:customer, shop: shop, lifetime_value: 210.0, risk_tier: "medium")
      end

      before do
        create(:order, shop: shop, customer: medium_customer, status: "paid",
               amount: 105.0, ordered_at: 95.days.ago)
      end

      it "creates an action with 10% discount for medium risk" do
        described_class.call(shop: shop)
        action = Action.find_by!(customer: medium_customer)

        expect(action.proposed_discount).to eq("10%")
        expect(action.risk_tier).to eq("medium")
      end
    end

    context "with no at-risk customers" do
      let!(:low_customer) do
        create(:customer, shop: shop, risk_tier: "low", lifetime_value: 500.0)
      end

      it "creates no actions" do
        expect { described_class.call(shop: shop) }
          .not_to change(Action, :count)
      end

      it "returns created: 0" do
        result = described_class.call(shop: shop)
        expect(result[:created]).to eq(0)
      end
    end

    context "with unscored customers" do
      let!(:unscored) do
        create(:customer, shop: shop, risk_tier: nil, lifetime_value: 100.0)
      end

      it "ignores unscored customers (nil risk_tier)" do
        expect { described_class.call(shop: shop) }
          .not_to change(Action, :count)
      end
    end
  end

  # ── Idempotency (partial unique index) ─────────────────────────────────────

  describe "duplicate prevention" do
    before do
      create(:order, shop: shop, customer: customer, status: "paid",
             amount: 89.0, ordered_at: 200.days.ago)
      customer.update!(risk_tier: "high")
    end

    it "does not create a second pending action for the same customer" do
      described_class.call(shop: shop)  # first run
      expect { described_class.call(shop: shop) }  # second run
        .not_to change(Action, :count)
    end

    it "does not enqueue a second approval email on re-run" do
      described_class.call(shop: shop)
      expect { described_class.call(shop: shop) }
        .not_to have_enqueued_mail(ApprovalMailer, :notify_owner)
    end

    it "allows a new action after the previous one is no longer pending" do
      described_class.call(shop: shop)
      Action.last.update!(status: "approved")

      expect { described_class.call(shop: shop) }
        .to change(Action, :count).by(1)
    end
  end

  # ── Risk reason text ────────────────────────────────────────────────────────

  describe "computed reason" do
    it "includes days since last order for old orders" do
      create(:order, shop: shop, customer: customer, status: "paid",
             amount: 89.0, ordered_at: 207.days.ago)

      described_class.call(shop: shop)

      expect(Action.last.reason).to match(/207 days ago/i)
    end

    it "mentions order count for frequency-driven high risk" do
      # Recent order but only 1 ever — frequency driven
      create(:order, shop: shop, customer: customer, status: "paid",
             amount: 89.0, ordered_at: 10.days.ago)

      described_class.call(shop: shop)

      expect(Action.last.reason).to match(/1 order/i)
    end
  end
end
