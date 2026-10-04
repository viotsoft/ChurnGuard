require "rails_helper"

RSpec.describe OwnerNotificationJob, type: :job do
  let(:shop)     { create(:shop) }
  let(:customer) { create(:customer, shop: shop) }

  before { RlsContext.set!(shop.id) }

  it "is queued on the notifications queue" do
    expect(described_class.queue_name).to eq("notifications")
  end

  describe "#perform" do
    context "when there are failed actions" do
      before do
        create(:action, shop: shop, customer: customer,
               status: "failed", expires_at: 72.hours.from_now)
      end

      it "sends the execution_failed email" do
        expect {
          described_class.new.perform(shop_id: shop.id)
        }.to change { ActionMailer::Base.deliveries.count }.by(1)
      end

      it "addresses the email to the shop owner" do
        described_class.new.perform(shop_id: shop.id)
        last_mail = ActionMailer::Base.deliveries.last
        expect(last_mail.to.first).to include("@")
      end
    end

    context "when there are no failed actions" do
      it "does not send an email" do
        expect {
          described_class.new.perform(shop_id: shop.id)
        }.not_to change { ActionMailer::Base.deliveries.count }
      end
    end

    context "when the shop does not exist" do
      it "returns early without raising" do
        expect { described_class.new.perform(shop_id: 999_999) }.not_to raise_error
      end
    end
  end
end
