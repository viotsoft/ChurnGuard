require "rails_helper"

RSpec.describe "DashboardController", type: :request do
  let(:shop)     { create(:shop) }
  let(:customer) { create(:customer, shop: shop, name: "Maria Kowalski", email: "maria@example.com", lifetime_value: 89.0, risk_tier: "high") }

  before { sign_in_shop(shop) }

  # ── GET / (index — approval queue) ──────────────────────────────────────────

  describe "GET /" do
    context "with pending actions" do
      before do
        RlsContext.set!(shop.id)
        create(:action, shop: shop, customer: customer,
               status: "pending", risk_tier: "high",
               proposed_discount: "15%", revenue_at_risk: 89.0,
               expires_at: 72.hours.from_now,
               reason: "Last ordered 207 days ago")
      end

      it "returns 200 OK" do
        get dashboard_index_path
        expect(response).to have_http_status(:ok)
      end

      it "renders the customer name in Fraunces" do
        get dashboard_index_path
        expect(response.body).to include("Maria Kowalski")
      end

      it "renders revenue at risk first (top-right, DESIGN.md rule)" do
        get dashboard_index_path
        expect(response.body).to include("at risk")
        expect(response.body).to include("89")
      end

      it "renders the risk reason" do
        get dashboard_index_path
        expect(response.body).to include("207 days ago")
      end

      it "renders the approve button in terracotta (DESIGN.md)" do
        get dashboard_index_path
        expect(response.body).to match(/btn-primary/)
        expect(response.body).to include("Send Discount")
      end

      it "renders the skip button" do
        get dashboard_index_path
        expect(response.body).to include("Skip for now")
      end

      it "shows the HIGH RISK badge" do
        get dashboard_index_path
        expect(response.body).to include("HIGH RISK")
      end

      it "does not include charts (DESIGN.md anti-pattern guard)" do
        get dashboard_index_path
        expect(response.body).not_to include("<canvas")
        expect(response.body).not_to include("chart.js")
        expect(response.body).not_to include("Chart(")
      end

      it "shows the pending count pill in the header" do
        get dashboard_index_path
        expect(response.body).to include("1 pending")
      end

      it "uses Fraunces font (DESIGN.md)" do
        get dashboard_index_path
        expect(response.body).to include("Fraunces")
      end

      it "uses warm cream #F5F0E8 background (DESIGN.md)" do
        get dashboard_index_path
        expect(response.body).to include("#F5F0E8")
      end

      it "uses terracotta #D4500A for CTAs (DESIGN.md)" do
        get dashboard_index_path
        expect(response.body).to include("#D4500A")
      end

      it "uses Geist Mono for revenue figures (DESIGN.md)" do
        get dashboard_index_path
        expect(response.body).to include("Geist Mono")
      end
    end

    context "with no pending actions (empty state)" do
      it "returns 200 OK" do
        get dashboard_index_path
        expect(response).to have_http_status(:ok)
      end

      it "shows the empty state message" do
        get dashboard_index_path
        expect(response.body).to match(/all caught up/i)
      end

      it "shows the revenue impact calculator" do
        get dashboard_index_path
        expect(response.body).to match(/churn costs/i)
      end
    end

    context "with executed actions this month" do
      before do
        RlsContext.set!(shop.id)
        create(:action, :executed, shop: shop, customer: customer,
               revenue_at_risk: 89.0, executed_at: Time.current)
      end

      it "shows the metrics bar with this month's data" do
        get dashboard_index_path
        expect(response.body).to include("Sent this month")
        expect(response.body).to include("Revenue recovered")
      end
    end
  end

  # ── GET /dashboard/history ───────────────────────────────────────────────────

  describe "GET /dashboard/history" do
    context "with completed actions" do
      before do
        RlsContext.set!(shop.id)
        create(:action, :executed, shop: shop, customer: customer,
               revenue_at_risk: 89.0, executed_at: 1.day.ago)
        create(:action, :skipped, shop: shop, customer: customer,
               revenue_at_risk: 50.0)
      end

      it "returns 200 OK" do
        get history_dashboard_index_path
        expect(response).to have_http_status(:ok)
      end

      it "shows the customer name" do
        get history_dashboard_index_path
        expect(response.body).to include("Maria Kowalski")
      end

      it "shows the executed status pill" do
        get history_dashboard_index_path
        expect(response.body).to include("executed")
      end

      it "shows the skipped status pill" do
        get history_dashboard_index_path
        expect(response.body).to include("skipped")
      end
    end

    context "with no completed actions" do
      it "returns 200 and shows empty message" do
        get history_dashboard_index_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to match(/no completed actions/i)
      end
    end
  end

  # ── GET /dashboard/insights ──────────────────────────────────────────────────

  describe "GET /dashboard/insights" do
    it "returns 200 OK" do
      get insights_dashboard_index_path
      expect(response).to have_http_status(:ok)
    end

    it "renders the insights heading" do
      get insights_dashboard_index_path
      expect(response.body).to match(/retention insights/i)
    end

    it "shows the metrics sections" do
      get insights_dashboard_index_path
      expect(response.body).to include("This month")
      expect(response.body).to include("All time")
      expect(response.body).to include("Action breakdown")
    end
  end

  # ── GET /dashboard/demo_results ─────────────────────────────────────────────

  describe "GET /dashboard/demo_results" do
    before do
      RlsContext.set!(shop.id)
      create(:customer, shop: shop, risk_tier: "medium", lifetime_value: 180.0)
      create(:order, shop: shop, customer: customer, status: "paid", amount: 89.0)
      create(:action, :uplift_v3, shop: shop, customer: customer,
             status: "pending", risk_tier: "high",
             proposed_discount: "15%", revenue_at_risk: 89.0,
             expires_at: 72.hours.from_now)
    end

    it "returns 200 OK" do
      get demo_results_dashboard_index_path
      expect(response).to have_http_status(:ok)
    end

    it "shows investor demo metrics" do
      get demo_results_dashboard_index_path
      expect(response.body).to include("Demo results")
      expect(response.body).to include("Customers scored")
      expect(response.body).to include("Expected incremental")
      expect(response.body).to include("Avg uplift")
      expect(response.body).to include("Top Uplift V3 decisions")
      expect(response.body).to include("From risk scoring to action selection")
      expect(response.body).to include("RFM")
      expect(response.body).to include("ML churn")
      expect(response.body).to include("High risk, low action value")
      expect(response.body).to include("Medium risk, high uplift")
    end
  end
end
