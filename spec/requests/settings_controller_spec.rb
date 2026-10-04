require "rails_helper"

RSpec.describe "SettingsController", type: :request do
  let(:shop) { create(:shop, klaviyo_api_key: "pk_existing_key_123") }

  before { sign_in_shop(shop) }

  # ── GET /settings ────────────────────────────────────────────────────────────

  describe "GET /settings" do
    it "returns 200 OK" do
      get settings_path
      expect(response).to have_http_status(:ok)
    end

    it "shows the Klaviyo settings section" do
      get settings_path
      expect(response.body).to match(/klaviyo/i)
    end

    it "shows the connected badge when API key is present" do
      get settings_path
      expect(response.body).to include("Connected")
    end

    it "shows the shop domain" do
      get settings_path
      expect(response.body).to include(shop.shopify_domain)
    end

    context "when Klaviyo key is missing" do
      before { shop.update_columns(klaviyo_api_key: nil) }

      it "shows the disconnected badge" do
        get settings_path
        expect(response.body).to include("Not connected")
      end
    end

    it "uses warm cream #F5F0E8 background (DESIGN.md)" do
      get settings_path
      expect(response.body).to include("#F5F0E8")
    end
  end

  # ── PATCH /settings ──────────────────────────────────────────────────────────

  describe "PATCH /settings" do
    it "updates the Klaviyo API key" do
      patch settings_path, params: { shop: { klaviyo_api_key: "pk_new_key_abc" } }
      RlsContext.set!(shop.id)
      expect(shop.reload.klaviyo_api_key).to eq("pk_new_key_abc")
    end

    it "redirects to settings with a success notice" do
      patch settings_path, params: { shop: { klaviyo_api_key: "pk_new_key_abc" } }
      expect(response).to redirect_to(settings_path)
      follow_redirect!
      expect(response.body).to match(/saved/i)
    end
  end
end
