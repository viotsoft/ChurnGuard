# KlaviyoClient — thin Faraday wrapper around the Klaviyo REST API (revision 2024-10-15).
#
# Raises typed exceptions so callers can distinguish retryable errors:
#   KlaviyoClient::RateLimitError  — HTTP 429 (Sidekiq should retry with backoff)
#   KlaviyoClient::ApiError        — HTTP 4xx/5xx (fatal after retries → DLQ)
#   KlaviyoClient::MissingApiKey   — shop has no Klaviyo key configured
#
# The client is intentionally thin — one public method, no business logic.
# Campaign triggering works by posting a named Klaviyo Event. Flows configured
# in Klaviyo listen for "ChurnGuard Retention Triggered" and send the discount.
#
# Usage:
#   KlaviyoClient.new(api_key: shop.klaviyo_api_key).trigger_campaign(action: action)
class KlaviyoClient
  class Error          < StandardError; end
  class RateLimitError < Error; end
  class ApiError       < Error; end
  class MissingApiKey  < Error; end

  BASE_URL    = "https://a.klaviyo.com"
  API_VERSION = "2024-10-15"
  EVENT_NAME  = "ChurnGuard Retention Triggered"

  def initialize(api_key:)
    raise MissingApiKey, "Klaviyo API key is blank" if api_key.blank?

    @api_key = api_key
    @conn    = build_connection
  end

  # POST an event to Klaviyo's Events API to trigger a retention flow.
  #
  # The event carries proposed_discount, risk_tier, and action_id as properties.
  # A Klaviyo flow (configured externally) listens for EVENT_NAME and delivers
  # the personalised discount email to the customer.
  #
  # @param action [Action] an approved action with a linked customer
  # @return [Faraday::Response] 2xx response on success
  # @raise [RateLimitError]  on HTTP 429 — caller should retry
  # @raise [ApiError]        on HTTP 4xx/5xx — fatal, DLQ after retries exhausted
  def trigger_campaign(action:)
    customer = action.customer
    payload  = build_event_payload(action, customer)
    response = @conn.post("/api/events/", payload.to_json)

    case response.status
    when 200..299
      response
    when 429
      raise RateLimitError,
        "Klaviyo rate limit (429). Retry-After: #{response.headers['retry-after'].inspect}"
    else
      raise ApiError,
        "Klaviyo API error HTTP #{response.status}: #{response.body.to_s.truncate(300)}"
    end
  end

  private

  def build_connection
    Faraday.new(url: BASE_URL) do |f|
      f.headers["Authorization"] = "Klaviyo-API-Key #{@api_key}"
      f.headers["revision"]      = API_VERSION
      f.headers["Content-Type"]  = "application/vnd.api+json"
      f.headers["Accept"]        = "application/vnd.api+json"
    end
  end

  def build_event_payload(action, customer)
    {
      data: {
        type: "event",
        attributes: {
          metric: {
            data: {
              type: "metric",
              attributes: { name: EVENT_NAME }
            }
          },
          profile: {
            data: {
              type: "profile",
              attributes: {
                email: customer.email,
                properties: {
                  churnguard_proposed_discount: action.proposed_discount,
                  churnguard_risk_tier:         action.risk_tier
                }
              }
            }
          },
          properties: {
            proposed_discount: action.proposed_discount,
            risk_tier:         action.risk_tier,
            revenue_at_risk:   action.revenue_at_risk.to_f,
            action_id:         action.id
          },
          time: Time.current.iso8601
        }
      }
    }
  end
end
