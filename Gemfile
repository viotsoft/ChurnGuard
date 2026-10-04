source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.3"

# Pin connection_pool < 3.0 — Sidekiq 7.3.x scheduler is incompatible with
# the breaking TimedStack API change introduced in connection_pool 3.0.
gem "connection_pool", "~> 2.4"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# -------------------------------------------------------------------
# ChurnGuard: Shopify integration
# -------------------------------------------------------------------
gem "shopify_app"           # Shopify OAuth + webhook HMAC + session storage

# -------------------------------------------------------------------
# ChurnGuard: Background jobs (Sidekiq replaces Rails solid_queue)
# -------------------------------------------------------------------
gem "sidekiq", "~> 7.0"     # Background job processing with named priority queues
gem "sidekiq-failures"      # Dead-letter queue visibility in Sidekiq Web UI

# -------------------------------------------------------------------
# ChurnGuard: Email delivery
# -------------------------------------------------------------------
gem "postmark-rails"        # Transactional email (owner approval emails)

# -------------------------------------------------------------------
# ChurnGuard: Token security
# -------------------------------------------------------------------
gem "jwt"                   # Signed approval tokens (action_id + shop_id + 72h expiry)

# -------------------------------------------------------------------
# ChurnGuard: Klaviyo API client
# -------------------------------------------------------------------
gem "faraday"               # HTTP client for Klaviyo REST API calls
gem "faraday-retry"         # Retry middleware for Klaviyo rate limit handling

# -------------------------------------------------------------------
# ChurnGuard: Error tracking & observability
# -------------------------------------------------------------------
gem "sentry-rails"          # Error tracking (Sentry)
gem "sentry-sidekiq"        # Sentry integration for Sidekiq jobs

# Use the database-backed adapter for Rails.cache
gem "solid_cache"

# Private CSV/model artifacts for the public Data Lab.
gem "aws-sdk-s3", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma
gem "thruster", require: false

group :development, :test do
  # Load .env into ENV automatically in development and test
  gem "dotenv-rails"

  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # RSpec testing framework
  gem "rspec-rails", "~> 7.0"
  gem "factory_bot_rails"   # Test data factories
  gem "faker"               # Realistic fake data for factories

  # Audits gems for known security defects
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities
  gem "brakeman", require: false

  # Omakase Ruby styling
  gem "rubocop-rails-omakase", require: false
end

group :development do
  # Use console on exceptions pages
  gem "web-console"
end

group :test do
  gem "shoulda-matchers"    # Clean RSpec matchers for Rails models
  gem "database_cleaner-active_record"  # Clean test DB between specs
  gem "webmock"             # Stub HTTP requests in specs (Faraday / Klaviyo)
end
