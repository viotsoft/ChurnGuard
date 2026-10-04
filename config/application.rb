require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
# require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Churnguard
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Use Sidekiq for background jobs (replaces solid_queue)
    config.active_job.queue_adapter = :sidekiq

    # Use SQL schema format so Postgres-specific DDL (RLS policies, FORCE ROW
    # LEVEL SECURITY, custom functions) is preserved in structure.sql.
    # The Ruby schema format silently drops these statements.
    config.active_record.schema_format = :sql

    # Default to UTC; shop owners see times in their local timezone
    config.time_zone = "UTC"

    # Don't generate system test files.
    config.generators.system_tests = nil

    # Default generators to use RSpec and FactoryBot
    config.generators do |g|
      g.test_framework :rspec, fixtures: false
      g.fixture_replacement :factory_bot, dir: "spec/factories"
    end
  end
end
