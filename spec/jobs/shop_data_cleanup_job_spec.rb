# spec/jobs/shop_data_cleanup_job_spec.rb

require "rails_helper"

RSpec.describe ShopDataCleanupJob, type: :job do
  let(:shop)     { create(:shop) }
  let!(:customer) do
    RlsContext.set!(shop.id)
    create(:customer, shop: shop, email: "alice@example.com", name: "Alice Smith")
  end

  before { RlsContext.set!(shop.id) }

  # ── Phase 1: PII anonymization ────────────────────────────────────────────

  describe "PII anonymization (hard_delete: false)" do
    it "replaces customer email with a non-reversible placeholder" do
      described_class.perform_now(shop_id: shop.id, hard_delete: false)
      RlsContext.set!(shop.id)
      expect(customer.reload.email).to match(/redacted-\d+@deleted\.invalid/)
    end

    it "replaces customer name with a generic placeholder" do
      described_class.perform_now(shop_id: shop.id, hard_delete: false)
      RlsContext.set!(shop.id)
      expect(customer.reload.name).to match(/Deleted Customer \d+/)
    end

    it "clears the shop Klaviyo API key" do
      described_class.perform_now(shop_id: shop.id, hard_delete: false)
      expect(shop.reload.klaviyo_api_key).to be_nil
    end

    it "marks shopify_token as revoked" do
      described_class.perform_now(shop_id: shop.id, hard_delete: false)
      expect(shop.reload.shopify_token).to eq("[REVOKED]")
    end

    it "does NOT destroy the shop record" do
      described_class.perform_now(shop_id: shop.id, hard_delete: false)
      expect(Shop.find_by(id: shop.id)).to be_present
    end

    it "schedules a hard-delete job for 30 days later" do
      expect {
        described_class.perform_now(shop_id: shop.id, hard_delete: false)
      }.to have_enqueued_job(ShopDataCleanupJob)
        .with(shop_id: shop.id, hard_delete: true)
    end
  end

  # ── Phase 2: Hard delete ──────────────────────────────────────────────────

  describe "hard delete (hard_delete: true)" do
    it "destroys the shop record" do
      described_class.perform_now(shop_id: shop.id, hard_delete: true)
      expect(Shop.find_by(id: shop.id)).to be_nil
    end
  end

  # ── Idempotency ───────────────────────────────────────────────────────────

  describe "idempotency" do
    it "is safe to call when shop no longer exists" do
      shop.destroy
      expect {
        described_class.perform_now(shop_id: shop.id, hard_delete: false)
      }.not_to raise_error
    end
  end
end
