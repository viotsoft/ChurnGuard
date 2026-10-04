require "rails_helper"

RSpec.describe TokenExpiryJob, type: :job do
  let(:shop)     { create(:shop) }
  let(:customer) { create(:customer, shop: shop) }

  before { RlsContext.set!(shop.id) }

  describe "#perform" do
    it "expires pending actions whose expires_at has passed" do
      overdue = create(:action, :overdue, shop: shop, customer: customer)

      described_class.new.perform

      expect(overdue.reload.status).to eq("expired")
    end

    it "does not touch pending actions that are still within their window" do
      valid = create(:action, shop: shop, customer: customer,
                     status: "pending", expires_at: 24.hours.from_now)

      described_class.new.perform

      expect(valid.reload.status).to eq("pending")
    end

    it "does not change already-expired actions" do
      already = create(:action, :expired, shop: shop, customer: customer)

      described_class.new.perform

      expect(already.reload.status).to eq("expired")
    end

    it "does not affect approved or skipped actions" do
      approved = create(:action, :approved, shop: shop, customer: customer,
                        expires_at: 1.day.ago)
      skipped  = create(:action, :skipped,  shop: shop,
                        customer: create(:customer, shop: shop),
                        expires_at: 1.day.ago)

      described_class.new.perform

      expect(approved.reload.status).to eq("approved")
      expect(skipped.reload.status).to eq("skipped")
    end

    it "returns the count of newly expired actions" do
      # Each action needs its own customer (partial unique index: one pending per customer)
      3.times { create(:action, :overdue, shop: shop, customer: create(:customer, shop: shop)) }

      result = described_class.new.perform

      expect(result).to eq(3)
    end

    it "returns 0 when nothing to expire" do
      result = described_class.new.perform
      expect(result).to eq(0)
    end

    it "handles multiple overdue actions in a single bulk update" do
      3.times do
        create(:action, :overdue, shop: shop,
               customer: create(:customer, shop: shop))
      end

      expect { described_class.new.perform }
        .to change { Action.where(status: "expired").count }.by(3)
    end
  end
end
