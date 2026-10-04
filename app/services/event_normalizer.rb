# EventNormalizer
#
# Maps raw Shopify webhook payloads into ChurnGuard's normalized data model:
#   - Creates/updates Customer records
#   - Creates Order records
#   - Creates Event records
#
# Supported event types:
#   :orders_paid       → upsert Customer + create Order (paid) + Event
#   :orders_cancelled  → update Order status + Event
#   :customers_create  → upsert Customer + Event
#
# Usage:
#   EventNormalizer.call(
#     event_type:  :orders_paid,
#     shop:        shop,
#     payload:     parsed_json_hash,
#     webhook_id:  "abc123"
#   )
#
# RLS note: caller must set RlsContext before calling (jobs do this automatically).

class EventNormalizer
  SUPPORTED_TYPES = %w[orders_paid orders_cancelled customers_create].freeze

  def self.call(event_type:, shop:, payload:, webhook_id:)
    new(event_type: event_type.to_s, shop: shop,
        payload: payload, webhook_id: webhook_id).call
  end

  def initialize(event_type:, shop:, payload:, webhook_id:)
    @event_type  = event_type.to_s
    @shop        = shop
    @payload     = payload.is_a?(String) ? JSON.parse(payload) : payload
    @webhook_id  = webhook_id
  end

  def call
    unless SUPPORTED_TYPES.include?(@event_type)
      Rails.logger.warn("[EventNormalizer] Unknown event type: #{@event_type}")
      return nil
    end

    send(:"normalize_#{@event_type}")
  rescue StandardError => e
    Rails.logger.error(
      "[EventNormalizer] Failed to normalize #{@event_type} " \
      "(webhook_id=#{@webhook_id}): #{e.class} — #{e.message}"
    )
    raise
  end

  private

  # ── orders/paid ────────────────────────────────────────────────────────────
  # Shopify payload includes order + embedded customer object.
  # Upserts the customer, creates the order record, creates an event.
  def normalize_orders_paid
    customer = find_or_create_customer(customer_data_from_order)
    order    = upsert_order(customer, status: "paid")

    # Update customer LTV with the new order amount
    new_ltv = @shop.orders.where(customer: customer, status: "paid").sum(:amount)
    customer.update!(lifetime_value: new_ltv)

    create_event("orders_paid", customer: customer)

    { customer: customer, order: order }
  end

  # ── orders/cancelled ───────────────────────────────────────────────────────
  # Marks an existing order as cancelled. Deducts from customer LTV.
  def normalize_orders_cancelled
    order = Order.find_by(shop: @shop, shopify_order_id: @payload["id"].to_s)

    if order
      order.update!(status: "cancelled")
      # Recalculate LTV excluding cancelled orders
      new_ltv = @shop.orders.where(customer: order.customer, status: "paid").sum(:amount)
      order.customer.update!(lifetime_value: new_ltv)
    else
      Rails.logger.warn(
        "[EventNormalizer] orders/cancelled for unknown order " \
        "#{@payload['id']} in shop #{@shop.shopify_domain}"
      )
    end

    customer = order&.customer || find_customer_from_order_payload
    create_event("orders_cancelled", customer: customer)

    { customer: customer, order: order }
  end

  # ── customers/create ───────────────────────────────────────────────────────
  # Shopify fires this when a new customer account is created.
  def normalize_customers_create
    customer = find_or_create_customer(@payload)
    create_event("customers_create", customer: customer)

    { customer: customer }
  end

  # ── Shared helpers ──────────────────────────────────────────────────────────

  def find_or_create_customer(data)
    return nil if data.blank? || data["id"].blank?

    shopify_id = data["id"].to_s
    full_name  = [data["first_name"], data["last_name"]].compact.join(" ").presence

    Customer.find_or_create_by!(
      shop:                 @shop,
      shopify_customer_id:  shopify_id
    ) do |c|
      c.name           = full_name
      c.email          = data["email"]
      c.lifetime_value = 0.0
    end.tap do |c|
      updates = {}
      updates[:name] = full_name if full_name.present? && c.name != full_name
      updates[:email] = data["email"] if data["email"].present? && c.email != data["email"]
      c.update!(updates) if updates.any?
    end
  end

  def upsert_order(customer, status: "paid")
    ordered_at = parse_time(@payload["created_at"])
    amount     = parse_amount

    Order.find_or_create_by!(
      shop:            @shop,
      shopify_order_id: @payload["id"].to_s
    ) do |o|
      o.customer   = customer
      o.amount     = amount
      o.currency   = @payload["currency"] || "EUR"
      o.status     = status
      o.ordered_at = ordered_at
    end
  end

  def create_event(type, customer: nil)
    Event.create!(
      shop:               @shop,
      customer:           customer,
      event_type:         type,
      payload:            @payload,
      shopify_webhook_id: @webhook_id,
      occurred_at:        parse_time(@payload["created_at"]) || Time.current
    )
  end

  def customer_data_from_order
    @payload["customer"] || {}
  end

  def find_customer_from_order_payload
    shopify_id = customer_data_from_order["id"]&.to_s
    return nil if shopify_id.blank?

    Customer.find_by(shop: @shop, shopify_customer_id: shopify_id)
  end

  def parse_amount
    # Shopify sends current_total_price (after discounts/refunds) or total_price
    raw = @payload["current_total_price"] || @payload["total_price"] || "0.0"
    raw.to_f.round(2)
  end

  def parse_time(value)
    return nil if value.blank?

    Time.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
