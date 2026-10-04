# ChurnGuard Architecture

ChurnGuard is a Rails modular monolith for Shopify-first churn prevention. The product thesis is action-first: detect at-risk customers, create an owner approval, and execute the approved retention action through Klaviyo.

## Current System

1. Shopify sends webhooks to `WebhooksController`.
2. Webhooks are HMAC-verified, deduplicated by `X-Shopify-Webhook-Id`, then enqueued.
3. Normalizer jobs call `EventNormalizer` to upsert customers, orders, and normalized events.
4. `DailyScoringJob` runs `ScoringEngine`, a rule-based RFM scorer configured by `config/scoring.yml`.
5. `ActionCreator` creates one pending action per at-risk customer, generates a single-use approval token, and emails the owner.
6. The owner approves from the dashboard or one-tap email link.
7. `KlaviyoExecutionJob` posts a Klaviyo event that triggers the merchant's retention flow.
8. Dashboard views show pending approvals first, with history and insights separated from the primary queue.

## Boundaries

- Controllers handle authentication, request validation, and response shape.
- Jobs own async orchestration and set RLS context before tenant-scoped reads/writes.
- Services own business operations: normalization, scoring, action creation, webhook deduplication, Klaviyo API calls.
- Models keep associations, validations, and small state transitions.
- PostgreSQL RLS is the tenant isolation layer; app code must set `app.current_shop_id` for all tenant work.

## Runtime Dependencies

- Ruby 3.3.11
- Rails 8.1
- PostgreSQL 16+
- Redis 7+ for Sidekiq
- Shopify app credentials
- Postmark for owner email delivery
- Klaviyo API keys stored per shop

## Main Risks

- RLS is powerful but unforgiving. Every background job must set and clear shop context.
- Approval links are GET requests by design. Tokens must remain short-lived, single-use, and hashed at rest.
- Klaviyo execution currently assumes merchants configure a matching flow for the `ChurnGuard Retention Triggered` event.
- Production config must stay on Sidekiq. Mixing Solid Queue defaults with Sidekiq jobs breaks retries and queue priority.
- API keys are currently plain columns; use Rails encryption before onboarding real merchants.

## Next Architecture Improvements

1. Add `encrypts :klaviyo_api_key` and migrate existing data.
2. Add a recurring scheduler for `DailyScoringJob.enqueue_all` and `TokenExpiryJob`.
3. Split production deployment into web and worker roles.
4. Add a typed execution result table or use `execution_queue_items` in `KlaviyoExecutionJob`.
5. Add a shop onboarding state for insufficient data instead of an empty approval queue.
6. Add an integration health check for Klaviyo keys before saving settings.
7. Move inline dashboard CSS into component stylesheets once the UI stabilizes.
