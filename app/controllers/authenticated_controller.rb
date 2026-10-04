# frozen_string_literal: true

class AuthenticatedController < ApplicationController
  include ShopifyApp::EnsureHasSession

  # Shopify-authenticated pages are served via the embedded app — only modern
  # browsers need apply. This does NOT apply to ApprovalsController or
  # WebhooksController (those serve email clients and Shopify's servers).
  allow_browser versions: :modern

  before_action :set_rls_context

  helper_method :current_shop

  private

  # Returns the Shop AR record for the currently authenticated Shopify merchant.
  # In development, falls back to the dev session set by Dev::SessionsController
  # (accessed via GET /dev/login) so the app is usable without ngrok + Shopify OAuth.
  def current_shop
    @current_shop ||= begin
      if Rails.env.development? && session[:shopify_domain].present?
        Shop.find_by(shopify_domain: session[:shopify_domain])
      else
        Shop.find_by(shopify_domain: current_shopify_domain)
      end
    end
  end

  # Set Postgres RLS context so all queries are scoped to this shop's rows.
  def set_rls_context
    RlsContext.set!(current_shop.id) if current_shop
  end

  # ── Dev session bypass ─────────────────────────────────────────────────────
  # activate_shopify_session is an around_action added by ShopifyApp::TokenExchange
  # (via EnsureHasSession). It requires a valid Shopify JWT — which doesn't exist
  # locally without ngrok. When a dev session cookie is present, skip it entirely.
  def activate_shopify_session
    if Rails.env.development? && session[:shopify_domain].present?
      yield  # skip OAuth check, go straight to the action
    else
      super  # normal Shopify JWT validation
    end
  end
end
