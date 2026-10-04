# Postmark transactional email configuration
# Used for: approval emails to shop owners, DLQ failure alerts, weekly ROI digest
# Documentation: https://github.com/wildbit/postmark-rails

Rails.application.config.action_mailer.delivery_method = :postmark
Rails.application.config.action_mailer.postmark_settings = {
  api_token: ENV.fetch("POSTMARK_API_TOKEN", nil)
}

# In development/test: use :test delivery to avoid real HTTP calls.
# The initializer runs after environment configs so we must guard here too.
if Rails.env.development? || Rails.env.test?
  Rails.application.config.action_mailer.delivery_method = :test
  Rails.application.config.action_mailer.perform_deliveries = true
  Rails.application.config.action_mailer.raise_delivery_errors = true
end

Rails.application.config.action_mailer.default_url_options = {
  host: ENV.fetch("APP_HOST", "localhost"),
  port: ENV.fetch("PORT", 3000)
}
