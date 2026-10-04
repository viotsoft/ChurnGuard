# config/initializers/sentry.rb
#
# Sentry error tracking — active in staging and production only.
# In development/test, errors surface via Rails logs and test output.

return unless Rails.env.production? || Rails.env.staging?
return if ENV["SENTRY_DSN"].blank?

Sentry.init do |config|
  config.dsn = ENV["SENTRY_DSN"]

  # Capture 100% of errors; sample 10% of performance traces
  config.traces_sample_rate = 0.10

  # Tag every event with the release SHA for source-map lookups
  config.release = ENV.fetch("GIT_SHA", "unknown")

  # Scrub sensitive fields before they reach Sentry
  config.send_default_pii = false

  # Breadcrumb integration — captures Rails logger output
  config.breadcrumbs_logger = [:active_support_logger, :http_logger]

  # Ignore common noise that isn't actionable
  config.excluded_exceptions += [
    "ActionController::RoutingError",
    "ActionController::UnknownFormat",
    "ActiveRecord::RecordNotFound",
    "Rack::Attack::Error"
  ]

  # Tag every event with the shop domain when available (set in ApplicationController)
  config.before_send = lambda do |event, hint|
    # Strip Klaviyo API keys from breadcrumbs/request bodies
    event.to_hash
    event
  end
end
