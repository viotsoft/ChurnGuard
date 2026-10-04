require "rails_helper"

RSpec.describe EventNormalizer do
  let(:shop) { create(:shop) }

  before { RlsContext.set!(shop.id) }

  # ── Shared payloads ──────────────────────────────────────────────────────────

  let(:customer_payload) do
    {
      "id"         => 9001,
      "email"      => "maria.kowalski@example.com",
      "first_name" => "Maria",
      "last_name"  => "Kowalski"
    }
  end

  let(:orders_paid_payload) do
    {
      "id"                  => 5001,
      "created_at"          => 10.days.ago.iso8601,
      "current_total_price" => "149.99",
      "currency"            => "EUR",
      "customer"            => customer_payload
    }
  end

  let(:orders_cancelled_payload) do
    {
      "id"         => 5001,
      "created_at" => 8.days.ago.iso8601,
      "customer"   => customer_payload
    }
  end

  let(:customers_create_payload) { customer_payload.merge("created_at" => 20.days.ago.iso8601) }

  # ── orders/paid ──────────────────────────────────────────────────────────────

  describe "orders_paid" do
    subject(:normalize) do
      described_class.call(
        event_type: :orders_paid,
        shop:       shop,
        payload:    orders_paid_payload,
        webhook_id: "wh_paid_001"
      )
    end

    it "creates a Customer record" do
      expect { normalize }.to change(Customer, :count).by(1)
    end

    it "sets the customer name from Shopify payload" do
      normalize
      expect(Customer.last.name).to eq("Maria Kowalski")
    end

    it "sets the customer email" do
      normalize
      expect(Customer.last.email).to eq("maria.kowalski@example.com")
    end

    it "creates an Order record" do
      expect { normalize }.to change(Order, :count).by(1)
    end

    it "sets the order amount from current_total_price" do
      normalize
      expect(Order.last.amount).to eq(149.99)
    end

    it "sets the order status to paid" do
      normalize
      expect(Order.last.status).to eq("paid")
    end

    it "creates an Event record with type orders_paid" do
      expect { normalize }.to change(Event, :count).by(1)
      expect(Event.last.event_type).to eq("orders_paid")
    end

    it "stores the webhook_id on the event" do
      normalize
      expect(Event.last.shopify_webhook_id).to eq("wh_paid_001")
    end

    it "updates the customer LTV to reflect the order amount" do
      normalize
      expect(Customer.last.lifetime_value).to eq(149.99)
    end

    context "when the customer already exists" do
      before do
        Customer.create!(
          shop:                shop,
          shopify_customer_id: "9001",
          name:                "Maria Kowalski",
          email:               "maria.kowalski@example.com",
          lifetime_value:      200.0
        )
      end

      it "does not create a duplicate customer" do
        expect { normalize }.not_to change(Customer, :count)
      end

      it "still creates the order" do
        expect { normalize }.to change(Order, :count).by(1)
      end
    end

    context "when the same order is ingested twice" do
      before { normalize }

      it "does not create a duplicate order" do
        expect { normalize }.not_to change(Order, :count)
      end
    end

    context "with a JSON string payload" do
      it "parses the string and normalizes correctly" do
        expect {
          described_class.call(
            event_type: :orders_paid,
            shop:       shop,
            payload:    orders_paid_payload.to_json,
            webhook_id: "wh_json_string"
          )
        }.to change(Order, :count).by(1)
      end
    end
  end

  # ── orders/cancelled ─────────────────────────────────────────────────────────

  describe "orders_cancelled" do
    let!(:customer) do
      Customer.create!(
        shop: shop, shopify_customer_id: "9001",
        name: "Maria Kowalski", email: "m@example.com", lifetime_value: 149.99
      )
    end
    let!(:existing_order) do
      Order.create!(
        shop: shop, customer: customer,
        shopify_order_id: "5001", amount: 149.99,
        currency: "EUR", status: "paid", ordered_at: 10.days.ago
      )
    end

    subject(:normalize) do
      described_class.call(
        event_type: :orders_cancelled,
        shop:       shop,
        payload:    orders_cancelled_payload,
        webhook_id: "wh_cancelled_001"
      )
    end

    it "marks the order as cancelled" do
      normalize
      expect(existing_order.reload.status).to eq("cancelled")
    end

    it "recalculates customer LTV (excludes cancelled orders)" do
      normalize
      expect(customer.reload.lifetime_value).to eq(0.0)
    end

    it "creates an Event record with type orders_cancelled" do
      expect { normalize }.to change(Event, :count).by(1)
      expect(Event.last.event_type).to eq("orders_cancelled")
    end

    context "when the order does not exist" do
      let(:unknown_payload) { orders_cancelled_payload.merge("id" => 99999) }

      it "does not raise" do
        expect {
          described_class.call(
            event_type: :orders_cancelled,
            shop:       shop,
            payload:    unknown_payload,
            webhook_id: "wh_unknown"
          )
        }.not_to raise_error
      end

      it "still creates an event" do
        expect {
          described_class.call(
            event_type: :orders_cancelled,
            shop:       shop,
            payload:    unknown_payload,
            webhook_id: "wh_unknown"
          )
        }.to change(Event, :count).by(1)
      end
    end
  end

  # ── customers/create ─────────────────────────────────────────────────────────

  describe "customers_create" do
    subject(:normalize) do
      described_class.call(
        event_type: :customers_create,
        shop:       shop,
        payload:    customers_create_payload,
        webhook_id: "wh_create_001"
      )
    end

    it "creates a Customer record" do
      expect { normalize }.to change(Customer, :count).by(1)
    end

    it "sets the correct name and email" do
      normalize
      customer = Customer.last
      expect(customer.name).to eq("Maria Kowalski")
      expect(customer.email).to eq("maria.kowalski@example.com")
    end

    it "initialises lifetime_value to 0" do
      normalize
      expect(Customer.last.lifetime_value).to eq(0.0)
    end

    it "creates an Event record with type customers_create" do
      expect { normalize }.to change(Event, :count).by(1)
      expect(Event.last.event_type).to eq("customers_create")
    end

    context "when the customer already exists" do
      before do
        Customer.create!(
          shop: shop, shopify_customer_id: "9001",
          name: "Maria Kowalski", email: "maria.kowalski@example.com",
          lifetime_value: 0.0
        )
      end

      it "does not create a duplicate" do
        expect { normalize }.not_to change(Customer, :count)
      end
    end
  end

  # ── Unknown event type ───────────────────────────────────────────────────────

  describe "unknown event type" do
    it "returns nil and does not raise" do
      result = described_class.call(
        event_type: :unknown_event,
        shop:       shop,
        payload:    {},
        webhook_id: "wh_unknown"
      )
      expect(result).to be_nil
    end
  end
end
