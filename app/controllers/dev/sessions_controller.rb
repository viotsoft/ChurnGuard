# app/controllers/dev/sessions_controller.rb
#
# DEV ONLY — bypasses Shopify OAuth for local development.
# Never runs in production (routes.rb gates on Rails.env.development?).
#
# Usage:
#   GET /dev/login                                  → uses first shop or creates one
#   GET /dev/login?shop=viotsoft.myshopify.com      → uses/creates specific shop
#   GET /dev/seed                                   → seeds 10 golden fixture customers + runs scoring

raise "Dev sessions controller loaded outside development!" unless Rails.env.development?

class Dev::SessionsController < ApplicationController
  skip_before_action :verify_authenticity_token

  # ── GET /dev/login ─────────────────────────────────────────────────────────
  def create
    domain = params[:shop].presence || "dev-store.myshopify.com"
    domain += ".myshopify.com" unless domain.include?(".")

    @shop = Shop.find_or_create_by!(shopify_domain: domain) do |s|
      s.shopify_token   = "dev_token_#{SecureRandom.hex(8)}"
      s.klaviyo_api_key = "pk_test_dev_#{SecureRandom.hex(8)}"
    end

    RlsContext.set!(@shop.id)

    # Store the shop domain in the session so AuthenticatedController can find it
    session[:shopify_domain] = @shop.shopify_domain

    flash[:notice] = "Dev login: #{@shop.shopify_domain} (id=#{@shop.id})"
    redirect_to safe_next_path || dashboard_index_path
  end

  # ── GET /dev/seed ──────────────────────────────────────────────────────────
  # Seeds 10 golden fixture customers with orders, then runs scoring.
  def seed
    domain = params[:shop].presence || session[:shopify_domain] || "dev-store.myshopify.com"
    domain += ".myshopify.com" unless domain.include?(".")

    @shop = Shop.find_or_create_by!(shopify_domain: domain) do |s|
      s.shopify_token   = "dev_token_#{SecureRandom.hex(8)}"
      s.klaviyo_api_key = "pk_test_dev_#{SecureRandom.hex(8)}"
    end

    RlsContext.set!(@shop.id)
    session[:shopify_domain] = @shop.shopify_domain

    seed_customers(@shop)

    DailyScoringJob.perform_now(@shop.id)
    RlsContext.set!(@shop.id)

    scored = @shop.customers.where.not(risk_tier: nil).count
    flash[:notice] = "Seeded 10 customers, ran scoring → #{scored} scored. Shop: #{@shop.shopify_domain}"
    redirect_to safe_next_path || dashboard_index_path
  end

  private

  def safe_next_path
    value = params[:next].to_s
    return if value.blank? || !value.start_with?("/") || value.start_with?("//")

    value
  end

  GOLDEN_PROFILES = [
    { name: "Alice High",   days_ago: 210, orders: 1, ltv: 80.0  },
    { name: "Bob High",     days_ago: 195, orders: 2, ltv: 120.0 },
    { name: "Carol Medium", days_ago: 95,  orders: 3, ltv: 180.0 },
    { name: "Dave Medium",  days_ago: 92,  orders: 2, ltv: 100.0 },
    { name: "Eve Low",      days_ago: 10,  orders: 6, ltv: 500.0 },
    { name: "Frank Low",    days_ago: 5,   orders: 8, ltv: 400.0 },
    { name: "Grace Low",    days_ago: 20,  orders: 5, ltv: 350.0 },
    { name: "Hank Low",     days_ago: 15,  orders: 7, ltv: 600.0 },
    { name: "Iris Medium",  days_ago: 100, orders: 2, ltv: 140.0 },
    { name: "Jack High",    days_ago: 185, orders: 1, ltv: 70.0  },
  ].freeze

  def seed_customers(shop)
    GOLDEN_PROFILES.each_with_index do |p, i|
      first = p[:name].split.first.downcase
      customer = Customer.find_or_create_by!(
        shop: shop,
        shopify_customer_id: "dev_#{i + 1}"
      ) do |c|
        c.name           = p[:name]
        c.email          = "#{first}@example.com"
        c.lifetime_value = p[:ltv]
      end

      p[:orders].times do |j|
        Order.find_or_create_by!(
          shop: shop,
          shopify_order_id: "dev_order_#{i}_#{j}"
        ) do |o|
          o.customer   = customer
          o.amount     = p[:ltv] / p[:orders]
          o.ordered_at = (p[:days_ago] + j).days.ago
          o.status     = "paid"
        end
      end
    end
  end
end
