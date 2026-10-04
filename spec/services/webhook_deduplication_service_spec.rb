require "rails_helper"

RSpec.describe WebhookDeduplicationService do
  let(:shop) { create(:shop) }

  # Set RLS context so inserts into webhook_deduplications work
  before { RlsContext.set!(shop.id) }

  describe ".call" do
    context "with a new webhook_id" do
      it "returns true (process this webhook)" do
        result = described_class.call(shop_id: shop.id, webhook_id: "wh_abc123")
        expect(result).to be true
      end

      it "creates a deduplication record" do
        expect {
          described_class.call(shop_id: shop.id, webhook_id: "wh_new_001")
        }.to change(WebhookDeduplication, :count).by(1)
      end
    end

    context "with a duplicate webhook_id (same shop)" do
      before { described_class.call(shop_id: shop.id, webhook_id: "wh_dup_001") }

      it "returns false (skip this webhook)" do
        result = described_class.call(shop_id: shop.id, webhook_id: "wh_dup_001")
        expect(result).to be false
      end

      it "does not create a second deduplication record" do
        expect {
          described_class.call(shop_id: shop.id, webhook_id: "wh_dup_001")
        }.not_to change(WebhookDeduplication, :count)
      end
    end

    context "with the same webhook_id but different shops" do
      let(:shop2) { create(:shop) }

      it "allows the same webhook_id across different shops" do
        described_class.call(shop_id: shop.id, webhook_id: "wh_shared")

        RlsContext.set!(shop2.id)
        result = described_class.call(shop_id: shop2.id, webhook_id: "wh_shared")
        expect(result).to be true
      end
    end

    context "with a blank webhook_id" do
      it "returns false and does not insert a record" do
        expect {
          result = described_class.call(shop_id: shop.id, webhook_id: "")
          expect(result).to be false
        }.not_to change(WebhookDeduplication, :count)
      end

      it "handles nil webhook_id" do
        result = described_class.call(shop_id: shop.id, webhook_id: nil)
        expect(result).to be false
      end
    end
  end
end
