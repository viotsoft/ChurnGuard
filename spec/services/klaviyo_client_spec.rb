require "rails_helper"

RSpec.describe KlaviyoClient do
  let(:api_key) { "pk_test_abc123" }
  let(:shop)    { build_stubbed(:shop, klaviyo_api_key: api_key) }
  let(:customer) do
    build_stubbed(:customer,
                  shop: shop,
                  email: "maria@example.com",
                  name: "Maria Kowalski")
  end
  let(:action) do
    build_stubbed(:action,
                  shop: shop,
                  customer: customer,
                  proposed_discount: "15%",
                  risk_tier: "high",
                  revenue_at_risk: 89.0)
  end

  subject(:client) { described_class.new(api_key: api_key) }

  # ── Instantiation ────────────────────────────────────────────────────────────

  describe ".new" do
    it "raises MissingApiKey when api_key is blank" do
      expect { described_class.new(api_key: "") }
        .to raise_error(KlaviyoClient::MissingApiKey, /blank/)
    end

    it "raises MissingApiKey when api_key is nil" do
      expect { described_class.new(api_key: nil) }
        .to raise_error(KlaviyoClient::MissingApiKey)
    end

    it "constructs successfully with a valid key" do
      expect { client }.not_to raise_error
    end
  end

  # ── #trigger_campaign ────────────────────────────────────────────────────────

  describe "#trigger_campaign" do
    let(:klaviyo_url) { "https://a.klaviyo.com/api/events/" }

    context "when Klaviyo returns 202 Accepted" do
      before do
        stub_request(:post, klaviyo_url).to_return(status: 202, body: "", headers: {})
      end

      it "returns the Faraday response" do
        result = client.trigger_campaign(action: action)
        expect(result.status).to eq(202)
      end

      it "sends the Authorization header with the API key" do
        client.trigger_campaign(action: action)
        expect(WebMock).to have_requested(:post, klaviyo_url)
          .with(headers: { "Authorization" => "Klaviyo-API-Key #{api_key}" })
      end

      it "pins the Klaviyo API revision header" do
        client.trigger_campaign(action: action)
        expect(WebMock).to have_requested(:post, klaviyo_url)
          .with(headers: { "revision" => KlaviyoClient::API_VERSION })
      end

      it "sends the event name in the request body" do
        client.trigger_campaign(action: action)
        expect(WebMock).to have_requested(:post, klaviyo_url)
          .with(body: hash_including(
            "data" => hash_including(
              "attributes" => hash_including(
                "metric" => hash_including(
                  "data" => hash_including(
                    "attributes" => { "name" => KlaviyoClient::EVENT_NAME }
                  )
                )
              )
            )
          ))
      end

      it "includes the customer email in the profile payload" do
        client.trigger_campaign(action: action)
        expect(WebMock).to have_requested(:post, klaviyo_url)
          .with(body: hash_including(
            "data" => hash_including(
              "attributes" => hash_including(
                "profile" => hash_including(
                  "data" => hash_including(
                    "attributes" => hash_including("email" => "maria@example.com")
                  )
                )
              )
            )
          ))
      end

      it "includes action properties in the event" do
        client.trigger_campaign(action: action)
        expect(WebMock).to have_requested(:post, klaviyo_url)
          .with(body: hash_including(
            "data" => hash_including(
              "attributes" => hash_including(
                "properties" => hash_including(
                  "proposed_discount" => "15%",
                  "risk_tier"         => "high"
                )
              )
            )
          ))
      end
    end

    context "when Klaviyo returns 429 Too Many Requests" do
      before do
        stub_request(:post, klaviyo_url)
          .to_return(status: 429, body: "", headers: { "Retry-After" => "60" })
      end

      it "raises KlaviyoClient::RateLimitError" do
        expect { client.trigger_campaign(action: action) }
          .to raise_error(KlaviyoClient::RateLimitError, /429/)
      end

      it "is a subclass of KlaviyoClient::Error" do
        expect(KlaviyoClient::RateLimitError.ancestors).to include(KlaviyoClient::Error)
      end
    end

    context "when Klaviyo returns 401 Unauthorized" do
      before do
        stub_request(:post, klaviyo_url)
          .to_return(status: 401, body: '{"errors":[{"detail":"Invalid API key"}]}', headers: {})
      end

      it "raises KlaviyoClient::ApiError" do
        expect { client.trigger_campaign(action: action) }
          .to raise_error(KlaviyoClient::ApiError, /401/)
      end
    end

    context "when Klaviyo returns 500 Server Error" do
      before do
        stub_request(:post, klaviyo_url)
          .to_return(status: 500, body: "Internal Server Error", headers: {})
      end

      it "raises KlaviyoClient::ApiError" do
        expect { client.trigger_campaign(action: action) }
          .to raise_error(KlaviyoClient::ApiError, /500/)
      end

      it "is a subclass of KlaviyoClient::Error" do
        expect(KlaviyoClient::ApiError.ancestors).to include(KlaviyoClient::Error)
      end
    end
  end
end
