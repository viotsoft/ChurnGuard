require "rails_helper"

RSpec.describe "ApprovalsController", type: :request do
  let(:shop)     { create(:shop) }
  let(:customer) do
    create(:customer, shop: shop, name: "Maria Kowalski",
           lifetime_value: 89.0, risk_tier: "high")
  end
  let(:action) do
    create(:action, shop: shop, customer: customer,
           status: "pending", risk_tier: "high",
           proposed_discount: "15%", revenue_at_risk: 89.0,
           expires_at: 72.hours.from_now)
  end

  # Generate a real JWT for each test — RLS context set here for DB setup.
  let(:raw_jwt) do
    RlsContext.set!(shop.id)
    ApprovalToken.generate_for!(action: action)
  end

  before { RlsContext.set!(shop.id) }

  # ── GET /approvals/approve ───────────────────────────────────────────────────

  describe "GET /approvals/approve" do
    context "with a valid, unconsumed, unexpired token" do
      it "returns 200 OK" do
        get approve_approvals_path, params: { token: raw_jwt }
        expect(response).to have_http_status(:ok)
      end

      it "marks the action as approved" do
        get approve_approvals_path, params: { token: raw_jwt }
        expect(action.reload.status).to eq("approved")
      end

      it "stamps approved_at on the action" do
        get approve_approvals_path, params: { token: raw_jwt }
        expect(action.reload.approved_at).to be_within(5.seconds).of(Time.current)
      end

      it "marks the token as consumed (single-use enforcement)" do
        get approve_approvals_path, params: { token: raw_jwt }
        RlsContext.set!(shop.id)
        expect(ApprovalToken.find_by_jwt(raw_jwt).consumed?).to be true
      end

      it "enqueues a KlaviyoExecutionJob with the action id" do
        expect {
          get approve_approvals_path, params: { token: raw_jwt }
        }.to have_enqueued_job(KlaviyoExecutionJob).with(action_id: action.id)
      end

      it "renders the approved confirmation page" do
        get approve_approvals_path, params: { token: raw_jwt }
        expect(response.body).to include("Maria Kowalski")
        expect(response.body).to include("sent")
        expect(response.body).to include("15%")
      end

      it "shows revenue at risk on the confirmation page" do
        get approve_approvals_path, params: { token: raw_jwt }
        expect(response.body).to include("89")
      end
    end

    # ── Replayed token ─────────────────────────────────────────────────────────

    context "with a replayed (already consumed) token" do
      before { get approve_approvals_path, params: { token: raw_jwt } }

      it "returns 200 (graceful, no error page)" do
        get approve_approvals_path, params: { token: raw_jwt }
        expect(response).to have_http_status(:ok)
      end

      it "does not change the action status again" do
        get approve_approvals_path, params: { token: raw_jwt }
        expect(action.reload.status).to eq("approved")
      end

      it "does not enqueue a second KlaviyoExecutionJob" do
        expect {
          get approve_approvals_path, params: { token: raw_jwt }
        }.not_to have_enqueued_job(KlaviyoExecutionJob)
      end

      it "renders the already-used page" do
        get approve_approvals_path, params: { token: raw_jwt }
        expect(response.body).to match(/already/i)
      end
    end

    # ── Expired token (DB-level expiry) ────────────────────────────────────────

    context "with a token whose expires_at has passed" do
      let(:expired_raw_jwt) do
        RlsContext.set!(shop.id)
        jwt = ApprovalToken.generate_for!(action: action)
        # Expire the DB record (JWT exp claim is still in future — that's intentional;
        # DB expires_at is the authoritative TTL, JWT exp is the backup layer)
        ApprovalToken.find_by_jwt(jwt).update_columns(expires_at: 3.days.ago)
        jwt
      end

      it "returns 200 (not a 4xx — graceful expiry)" do
        get approve_approvals_path, params: { token: expired_raw_jwt }
        expect(response).to have_http_status(:ok)
      end

      it "does not approve the action" do
        get approve_approvals_path, params: { token: expired_raw_jwt }
        expect(action.reload.status).to eq("pending")
      end

      it "does not consume the token" do
        get approve_approvals_path, params: { token: expired_raw_jwt }
        RlsContext.set!(shop.id)
        expect(ApprovalToken.find_by_jwt(expired_raw_jwt).consumed?).to be false
      end

      it "renders the expired page with the customer name" do
        get approve_approvals_path, params: { token: expired_raw_jwt }
        expect(response.body).to match(/expired/i)
        expect(response.body).to include("Maria Kowalski")
      end

      it "does not enqueue a job" do
        expect {
          get approve_approvals_path, params: { token: expired_raw_jwt }
        }.not_to have_enqueued_job(KlaviyoExecutionJob)
      end
    end

    # ── JWT-expired token (exp claim in past) ──────────────────────────────────

    context "with a JWT whose exp claim is already in the past" do
      let(:past_exp_jwt) do
        payload = { action_id: action.id, shop_id: shop.id, exp: 1.hour.ago.to_i }
        JWT.encode(payload, Rails.application.secret_key_base, "HS256")
      end

      it "returns 401 Unauthorized" do
        get approve_approvals_path, params: { token: past_exp_jwt }
        expect(response).to have_http_status(:unauthorized)
      end

      it "renders the invalid page" do
        get approve_approvals_path, params: { token: past_exp_jwt }
        expect(response.body).to match(/invalid/i)
      end
    end

    # ── Missing token ──────────────────────────────────────────────────────────

    context "with no token parameter" do
      it "returns 400 Bad Request" do
        get approve_approvals_path
        expect(response).to have_http_status(:bad_request)
      end

      it "renders the invalid page" do
        get approve_approvals_path
        expect(response.body).to match(/invalid/i)
      end
    end

    # ── Tampered / invalid JWT ─────────────────────────────────────────────────

    context "with a tampered token (bad signature)" do
      it "returns 401 Unauthorized" do
        get approve_approvals_path, params: { token: "tampered.jwt.here" }
        expect(response).to have_http_status(:unauthorized)
      end

      it "renders the invalid page" do
        get approve_approvals_path, params: { token: "tampered.jwt.here" }
        expect(response.body).to match(/invalid/i)
      end

      it "does not enqueue any job" do
        expect {
          get approve_approvals_path, params: { token: "tampered.jwt.here" }
        }.not_to have_enqueued_job(KlaviyoExecutionJob)
      end
    end
  end

  # ── GET /approvals/skip ──────────────────────────────────────────────────────

  describe "GET /approvals/skip" do
    context "with a valid, unconsumed token" do
      it "returns 200 OK" do
        get skip_approvals_path, params: { token: raw_jwt }
        expect(response).to have_http_status(:ok)
      end

      it "marks the action as skipped" do
        get skip_approvals_path, params: { token: raw_jwt }
        expect(action.reload.status).to eq("skipped")
      end

      it "stamps skipped_at on the action" do
        get skip_approvals_path, params: { token: raw_jwt }
        expect(action.reload.skipped_at).to be_within(5.seconds).of(Time.current)
      end

      it "marks the token as consumed" do
        get skip_approvals_path, params: { token: raw_jwt }
        RlsContext.set!(shop.id)
        expect(ApprovalToken.find_by_jwt(raw_jwt).consumed?).to be true
      end

      it "does NOT enqueue a KlaviyoExecutionJob" do
        expect {
          get skip_approvals_path, params: { token: raw_jwt }
        }.not_to have_enqueued_job(KlaviyoExecutionJob)
      end

      it "renders the skipped confirmation page" do
        get skip_approvals_path, params: { token: raw_jwt }
        expect(response.body).to match(/skipped/i)
        expect(response.body).to include("Maria Kowalski")
      end
    end

    context "with a replayed skip token" do
      before { get skip_approvals_path, params: { token: raw_jwt } }

      it "returns 200 gracefully" do
        get skip_approvals_path, params: { token: raw_jwt }
        expect(response).to have_http_status(:ok)
      end

      it "renders the already-used page" do
        get skip_approvals_path, params: { token: raw_jwt }
        expect(response.body).to match(/already/i)
      end
    end

    context "with a missing token" do
      it "returns 400" do
        get skip_approvals_path
        expect(response).to have_http_status(:bad_request)
      end
    end
  end
end
