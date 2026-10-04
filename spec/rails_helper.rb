# This file is copied to spec/ when you run 'rails generate rspec:install'
require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'

# Provide Shopify credentials before the initializer runs.
# These are fixed test values used only for HMAC computation in specs —
# they are NOT real API keys and must never be used in production.
ENV['SHOPIFY_API_KEY']    ||= 'test_api_key_rspec_placeholder'
ENV['SHOPIFY_API_SECRET'] ||= 'test_shopify_secret_rspec_only'

# ShopifyAPI::Context.host_scheme requires HOST to be non-nil.
# Without this, the CSP frame-ancestors middleware raises TypeError (T.must(nil)).
# Must be set before config/environment loads so ShopifyAPI::Context.setup gets it.
ENV['HOST'] ||= 'test.localhost:3000'
ENV['APP_HOST'] ||= 'test.localhost:3000'

require_relative '../config/environment'
# Prevent database truncation if the environment is production
abort("The Rails environment is running in production mode!") if Rails.env.production?
require 'rspec/rails'

# Support files: shared contexts, custom matchers, helpers
Rails.root.glob('spec/support/**/*.rb').sort_by(&:to_s).each { |f| require f }

# WebMock — stub HTTP requests in tests. Real outbound calls will raise unless stubbed.
require "webmock/rspec"
WebMock.disable_net_connect!(allow_localhost: true)

# Checks for pending migrations and applies them before tests are run.
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  # Use FactoryBot shorthand (create, build, etc.)
  config.include FactoryBot::Syntax::Methods

  # Use DatabaseCleaner instead of transactional fixtures for RLS tests
  config.use_transactional_fixtures = false

  config.before(:suite) do
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.clean_with(:truncation)
  end

  config.around(:each) do |example|
    DatabaseCleaner.cleaning { example.run }
  end

  # Infer spec type from file location
  config.infer_spec_type_from_file_location!

  # Filter lines from Rails gems in backtraces
  config.filter_rails_from_backtrace!
end

Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end
