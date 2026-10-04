require "sidekiq"
require "sidekiq/web"

Sidekiq.configure_server do |config|
  config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }
end

# Sidekiq::Web is mounted in config/routes.rb (auth-gated to shop owners)
