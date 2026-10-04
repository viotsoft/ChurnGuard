# spec/support/shopify_auth.rb
#
# Stubs Shopify OAuth authentication for request specs that hit
# AuthenticatedController subclasses (DashboardController, ActionsController,
# SettingsController).
#
# ChurnGuard uses ShopifyApp's new embedded auth strategy (TokenExchange),
# which provides an around_action :activate_shopify_session via
# ShopifyApp::TokenExchange. This must be stubbed — not LoginProtection.
#
# Usage in a spec:
#   before { sign_in_shop(shop) }
#
module ShopifyAuthHelper
  def sign_in_shop(shop)
    RlsContext.set!(shop.id)

    # Bypass around_action :activate_shopify_session from ShopifyApp::TokenExchange.
    # The new embedded auth strategy (new_embedded_auth_strategy = true) uses TokenExchange,
    # not LoginProtection. Stubbing on AuthenticatedController covers all subclasses.
    allow_any_instance_of(AuthenticatedController)
      .to receive(:activate_shopify_session) do |_ctrl, &block|
        block.call
      end

    # Inject our test shop via current_shop — bypasses JWT session lookup entirely.
    allow_any_instance_of(AuthenticatedController)
      .to receive(:current_shop).and_return(shop)

    # Bypass set_rls_context — we already set it above, but stub for safety.
    allow_any_instance_of(AuthenticatedController)
      .to receive(:set_rls_context) { RlsContext.set!(shop.id) }
  end
end

RSpec.configure do |config|
  config.include ShopifyAuthHelper, type: :request
end
