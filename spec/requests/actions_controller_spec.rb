require "rails_helper"

RSpec.describe "ActionsController", type: :request do
  let(:shop)     { create(:shop) }
  let(:customer) { create(:customer, shop: shop, name: "Maria Kowalski", risk_tier: "high") }
  let(:action) do
    RlsContext.set!(shop.id)
    create(:action, shop: shop, customer: customer,
           status: "pending", risk_tier: "high",
           proposed_discount: "15%", revenue_at_risk: 89.0,
           expires_at: 72.hours.from_now)
  end

  before do
    sign_in_shop(shop)
    action  # ensure it's created with correct RLS
    RlsContext.set!(shop.id)
  end

  # ── PATCH /actions/:id/approve ───────────────────────────────────────────────

  describe "PATCH /actions/:id/approve" do
    it "marks the action as approved" do
      patch approve_action_path(action)
      expect(action.reload.status).to eq("approved")
    end

    it "stamps approved_at" do
      patch approve_action_path(action)
      expect(action.reload.approved_at).to be_within(5.seconds).of(Time.current)
    end

    it "enqueues a KlaviyoExecutionJob" do
      expect {
        patch approve_action_path(action)
      }.to have_enqueued_job(KlaviyoExecutionJob).with(action_id: action.id)
    end

    it "redirects to the approval queue with a notice" do
      patch approve_action_path(action)
      expect(response).to redirect_to(dashboard_index_path)
      follow_redirect!
      expect(response.body).to match(/Maria Kowalski|queued/i)
    end

    context "with turbo_stream format" do
      it "returns turbo stream" do
        patch approve_action_path(action), headers: { "Accept" => "text/vnd.turbo-stream.html" }
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      end

      it "replaces the action card" do
        patch approve_action_path(action), headers: { "Accept" => "text/vnd.turbo-stream.html" }
        expect(response.body).to include("action_#{action.id}")
        expect(response.body).to include("turbo-stream")
      end
    end
  end

  # ── PATCH /actions/:id/skip ──────────────────────────────────────────────────

  describe "PATCH /actions/:id/skip" do
    it "marks the action as skipped" do
      patch skip_action_path(action)
      expect(action.reload.status).to eq("skipped")
    end

    it "stamps skipped_at" do
      patch skip_action_path(action)
      expect(action.reload.skipped_at).to be_within(5.seconds).of(Time.current)
    end

    it "does NOT enqueue a KlaviyoExecutionJob" do
      expect {
        patch skip_action_path(action)
      }.not_to have_enqueued_job(KlaviyoExecutionJob)
    end

    it "redirects to the approval queue" do
      patch skip_action_path(action)
      expect(response).to redirect_to(dashboard_index_path)
    end

    context "with turbo_stream format" do
      it "returns turbo stream replacing the card" do
        patch skip_action_path(action), headers: { "Accept" => "text/vnd.turbo-stream.html" }
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        expect(response.body).to include("action_#{action.id}")
      end
    end
  end
end
