require "rails_helper"
require "openssl"
require "base64"

RSpec.describe "WebhooksController", type: :request do
  let(:shop)       { create(:shop) }
  let(:api_secret) { ShopifyApp.configuration.secret }
  let(:webhook_id) { "wh-test-#{SecureRandom.hex(8)}" }

  let(:orders_paid_payload) do
    {
      id:         7001,
      created_at: 5.days.ago.iso8601,
      current_total_price: "89.99",
      currency: "EUR",
      customer: {
        id:         8001,
        email:      "jan.nowak@example.com",
        first_name: "Jan",
        last_name:  "Nowak"
      }
    }.to_json
  end

  before { RlsContext.set!(shop.id) }

  # ── Header helpers ────────────────────────────────────────────────────────

  # Builds the full set of Shopify webhook headers.
  # shopify_api gem v16 validates all five headers are present before dispatching.
  def shopify_headers(body, topic: "orders/paid", webhook_id: self.webhook_id,
                      shop_domain: shop.shopify_domain)
    hmac = Base64.strict_encode64(
      OpenSSL::HMAC.digest("SHA256", api_secret, body.to_s)
    )
    {
      "X-Shopify-Hmac-SHA256"  => hmac,
      "X-Shopify-Webhook-Id"   => webhook_id,
      "X-Shopify-Shop-Domain"  => shop_domain,
      "X-Shopify-Topic"        => topic,
      "X-Shopify-Api-Version"  => ShopifyApp.configuration.api_version,
      "Content-Type"           => "application/json"
    }
  end

  def tampered_headers(body, **opts)
    shopify_headers(body, **opts).merge("X-Shopify-Hmac-SHA256" => "dGFtcGVyZWQ=")
  end

  # ── POST /webhooks/orders_paid ────────────────────────────────────────────

  describe "POST /webhooks/orders_paid" do
    context "with a valid HMAC signature" do
      it "returns 200 OK" do
        post webhooks_orders_paid_path,
             params:  orders_paid_payload,
             headers: shopify_headers(orders_paid_payload, topic: "orders/paid")

        expect(response).to have_http_status(:ok)
      end

      it "enqueues an OrdersPaidJob" do
        expect {
          post webhooks_orders_paid_path,
               params:  orders_paid_payload,
               headers: shopify_headers(orders_paid_payload, topic: "orders/paid")
        }.to have_enqueued_job(OrdersPaidJob).with(
          hash_including(shop_domain: shop.shopify_domain)
        )
      end
    end

    context "with an invalid HMAC signature (tampered body)" do
      it "returns 401 Unauthorized" do
        post webhooks_orders_paid_path,
             params:  orders_paid_payload,
             headers: tampered_headers(orders_paid_payload, topic: "orders/paid")

        expect(response).to have_http_status(:unauthorized)
      end

      it "does not enqueue a job" do
        expect {
          post webhooks_orders_paid_path,
               params:  orders_paid_payload,
               headers: tampered_headers(orders_paid_payload, topic: "orders/paid")
        }.not_to have_enqueued_job(OrdersPaidJob)
      end
    end

    context "with a missing HMAC header" do
      it "returns 401 Unauthorized" do
        post webhooks_orders_paid_path,
             params:  orders_paid_payload,
             headers: {
               "X-Shopify-Shop-Domain" => shop.shopify_domain,
               "X-Shopify-Topic"       => "orders/paid",
               "X-Shopify-Webhook-Id"  => webhook_id,
               "X-Shopify-Api-Version" => ShopifyApp.configuration.api_version,
               "Content-Type"          => "application/json"
             }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with an unknown shop domain" do
      it "returns 422 Unprocessable Entity" do
        post webhooks_orders_paid_path,
             params:  orders_paid_payload,
             headers: shopify_headers(orders_paid_payload, topic: "orders/paid",
                                      shop_domain: "ghost-shop.myshopify.com")

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "with a duplicate webhook_id" do
      let(:dup_id) { "wh-dup-#{SecureRandom.hex(6)}" }

      before do
        # First request — registered successfully
        post webhooks_orders_paid_path,
             params:  orders_paid_payload,
             headers: shopify_headers(orders_paid_payload, topic: "orders/paid",
                                      webhook_id: dup_id)
      end

      it "returns 200 OK (Shopify must stop retrying)" do
        post webhooks_orders_paid_path,
             params:  orders_paid_payload,
             headers: shopify_headers(orders_paid_payload, topic: "orders/paid",
                                      webhook_id: dup_id)

        expect(response).to have_http_status(:ok)
      end

      it "does not enqueue a second job" do
        expect {
          post webhooks_orders_paid_path,
               params:  orders_paid_payload,
               headers: shopify_headers(orders_paid_payload, topic: "orders/paid",
                                        webhook_id: dup_id)
        }.not_to have_enqueued_job(OrdersPaidJob)
      end
    end
  end

  # ── POST /webhooks/orders_cancelled ──────────────────────────────────────

  describe "POST /webhooks/orders_cancelled" do
    let(:payload) do
      { id: 7001, created_at: 2.days.ago.iso8601,
        customer: { id: 8001, email: "jan@example.com",
                    first_name: "Jan", last_name: "Nowak" } }.to_json
    end

    it "returns 200 with valid HMAC" do
      post webhooks_orders_cancelled_path,
           params:  payload,
           headers: shopify_headers(payload, topic: "orders/cancelled")

      expect(response).to have_http_status(:ok)
    end

    it "enqueues an OrdersCancelledJob" do
      expect {
        post webhooks_orders_cancelled_path,
             params:  payload,
             headers: shopify_headers(payload, topic: "orders/cancelled")
      }.to have_enqueued_job(OrdersCancelledJob).with(
        hash_including(shop_domain: shop.shopify_domain)
      )
    end

    it "returns 401 with invalid HMAC" do
      post webhooks_orders_cancelled_path,
           params:  payload,
           headers: tampered_headers(payload, topic: "orders/cancelled")

      expect(response).to have_http_status(:unauthorized)
    end
  end

  # ── POST /webhooks/customers_create ──────────────────────────────────────

  describe "POST /webhooks/customers_create" do
    let(:payload) do
      { id: 8002, email: "ewa@example.com",
        first_name: "Ewa", last_name: "Kowalczyk",
        created_at: 1.day.ago.iso8601 }.to_json
    end

    it "returns 200 with valid HMAC" do
      post webhooks_customers_create_path,
           params:  payload,
           headers: shopify_headers(payload, topic: "customers/create")

      expect(response).to have_http_status(:ok)
    end

    it "enqueues a CustomersCreateJob" do
      expect {
        post webhooks_customers_create_path,
             params:  payload,
             headers: shopify_headers(payload, topic: "customers/create")
      }.to have_enqueued_job(CustomersCreateJob).with(
        hash_including(shop_domain: shop.shopify_domain)
      )
    end

    it "returns 401 with invalid HMAC" do
      post webhooks_customers_create_path,
           params:  payload,
           headers: tampered_headers(payload, topic: "customers/create")

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
