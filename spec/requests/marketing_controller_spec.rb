require "rails_helper"

RSpec.describe "MarketingController", type: :request do
  describe "GET /" do
    it "renders the public landing page" do
      get root_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Recover revenue before repeat customers disappear")
      expect(response.body).to include("landing-approval-queue")
      expect(response.body).to include("Request pilot")
    end
  end

  describe "GET /landing" do
    it "renders the same landing page" do
      get landing_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("ChurnGuard")
      expect(response.body).to include("Action-first workflow")
    end
  end
end
