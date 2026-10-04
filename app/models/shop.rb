# frozen_string_literal: true

class Shop < ActiveRecord::Base
  include ShopifyApp::ShopSessionStorage

  # ChurnGuard associations
  has_many :customers,               dependent: :destroy
  has_many :orders,                  dependent: :destroy
  has_many :events,                  dependent: :destroy
  has_many :actions,                 dependent: :destroy
  has_many :webhook_deduplications,  dependent: :destroy

  # Klaviyo API key stored per-shop (encrypted in production via Rails credentials)
  # Not encrypted here yet — Phase 8 hardening will add encrypts :klaviyo_api_key
  # attr_encrypted :klaviyo_api_key, key: Rails.application.credentials.encryption_key

  ONBOARDING_MIN_CUSTOMERS = 10
  ONBOARDING_MIN_ORDERS    = 30

  # True when the shop has enough data for useful RFM scoring
  def ready_for_scoring?
    customers.count >= ONBOARDING_MIN_CUSTOMERS &&
      orders.count >= ONBOARDING_MIN_ORDERS
  end

  def api_version
    ShopifyApp.configuration.api_version
  end
end
