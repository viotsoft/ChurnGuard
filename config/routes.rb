require "sidekiq/web"

# Sidekiq Web UI — gated by HTTP Basic Auth in non-development environments.
# Credentials: SIDEKIQ_WEB_USERNAME / SIDEKIQ_WEB_PASSWORD env vars.
# Falls back to "admin" / random secure token (logs it on boot) if not set.
Sidekiq::Web.use(Rack::Auth::Basic) do |username, password|
  expected_user = ENV.fetch("SIDEKIQ_WEB_USERNAME", "admin")
  expected_pass = ENV.fetch("SIDEKIQ_WEB_PASSWORD") do
    # In development, generate a one-time password and log it so the developer
    # can still access the UI without setting the env var explicitly.
    @_sidekiq_dev_pass ||= SecureRandom.hex(16).tap do |p|
      Rails.logger.info "  [Sidekiq Web UI] dev password: #{p} (set SIDEKIQ_WEB_PASSWORD to fix)"
    end
  end
  # Constant-time comparison prevents timing attacks
  ActiveSupport::SecurityUtils.secure_compare(username, expected_user) &&
    ActiveSupport::SecurityUtils.secure_compare(password, expected_pass)
end unless Rails.env.test?

Rails.application.routes.draw do
  root to: "marketing#index"
  get "landing", to: "marketing#index"

  # Public, Shopify-independent CSV uplift sandbox.
  namespace :lab do
    root to: "projects#index"
    get :sign_in, to: "sessions#new"
    post :sign_in, to: "sessions#create"
    get :session, to: "sessions#show"
    delete :sign_out, to: "sessions#destroy"

    resources :projects, only: %i[index new create show destroy] do
      member do
        get :mapping
        patch :mapping, action: :update_mapping
        post :run
        get :status
        get :download
        get :download_source
      end
      collection do
        post :sample
      end
    end
  end

  # ── Shopify webhook ingestion ──────────────────────────────────────────────
  # Declared BEFORE mount ShopifyApp::Engine so our specific routes take
  # priority over the engine's catch-all /webhooks(/:type) route.
  # WebhooksController performs its own HMAC verification + deduplication.
  namespace :webhooks do
    post :orders_paid
    post :orders_cancelled
    post :customers_create
    # GDPR mandatory webhooks — required by Shopify Partner Program
    post :app_uninstalled
    post :customers_data_request
    post :customers_redact
    post :shop_redact
  end

  # ── Shopify OAuth + session management engine ──────────────────────────────
  # Must come after our webhook namespace so the engine's /webhooks(/:type)
  # catch-all does NOT shadow our specific webhook routes above.
  mount ShopifyApp::Engine, at: "/"

  # Health check for load balancers and uptime monitors
  get "up" => "rails/health#show", as: :rails_health_check

  # ── Dev backdoor (development only) ───────────────────────────────────────
  # Bypasses Shopify OAuth so you can see the dashboard without ngrok.
  # GET /dev/login?shop=viotsoft.myshopify.com
  # Creates the shop record if missing, seeds fixture customers, sets session.
  if Rails.env.development?
    get "dev/login", to: "dev/sessions#create"
    get "dev/seed",  to: "dev/sessions#seed"
  end

  # Sidekiq Web UI — HTTP Basic Auth applied above (before routes.draw block)
  mount Sidekiq::Web, at: "/admin/sidekiq"

  # Dashboard routes
  resources :dashboard, only: [:index] do
    collection do
      get :history    # Action history (approved/skipped/expired/failed)
      get :insights   # Metrics + ROI digest (charts live here, NOT on index)
      get :demo_results
    end
  end

  # Dashboard approve/skip — Shopify-OAuth authenticated, no token required.
  # Separate from the email one-tap flow (which uses ApprovalToken JWTs).
  resources :actions, only: [] do
    member do
      patch :approve
      patch :skip
    end
  end

  # One-tap approval flow (token-authenticated, no login required from email)
  # GET is intentional: email clients can only follow links (not submit forms).
  # The ApprovalToken JWT in the query string is the authentication mechanism.
  resources :approvals, only: [] do
    collection do
      get :approve   # GET /approvals/approve?token=... — email one-tap link
      get :skip      # GET /approvals/skip?token=...   — email skip link
    end
  end

  # Settings (Klaviyo connection, shop preferences)
  resource :settings, only: [:show, :update]
end
