# ChurnGuard Architecture

ChurnGuard is a Rails modular monolith with two isolated product surfaces:

- a Shopify-first retention workflow that scores customers, proposes actions, and executes approved campaigns through Klaviyo;
- Data Lab, a CSV sandbox for validating uplift models without connecting a Shopify store.

## Current System

1. Shopify sends webhooks to `WebhooksController`.
2. Webhooks are HMAC-verified, deduplicated by `X-Shopify-Webhook-Id`, then enqueued.
3. Normalizer jobs call `EventNormalizer` to upsert customers, orders, and normalized events.
4. `DailyScoringJob` runs `ScoringEngine`, a rule-based RFM scorer configured by `config/scoring.yml`.
5. `ActionCreator` creates one pending action per at-risk customer, generates a single-use approval token, and emails the owner.
6. The owner approves from the dashboard or one-tap email link.
7. `KlaviyoExecutionJob` posts a Klaviyo event that triggers the merchant's retention flow.
8. Dashboard views show pending approvals first, with history and insights separated from the primary queue.

## Data Lab Flow

1. A `SandboxUser` signs in through a short-lived, single-use magic link.
2. The user creates an `AnalysisProject` and attaches orders plus an optional treatment/control experiment CSV through Active Storage.
3. `CsvDatasetInspector` validates the schema, detects common column aliases, and rejects contact fields.
4. `UpliftAnalysisJob` builds a temporary configuration and invokes `research/ml/uplift_lab_pipeline.py` without passing user input to a shell.
5. The Python pipeline creates pre-treatment RFM features and evaluates S-Learner and T-Learner models. If experiment outcomes are missing, it runs a clearly labelled semi-synthetic simulation.
6. Rails stores run metrics and only the first 100 masked recommendations in PostgreSQL. The full prediction export remains a private Active Storage object.
7. `AnalysisRetentionJob` removes raw uploads after 24 hours and derived results after 30 days.

Shopify records and Data Lab records use separate models and authentication paths. A sandbox analysis cannot create an executable `Action` or trigger a Klaviyo campaign.

## Boundaries

- Controllers handle authentication, request validation, and response shape.
- Jobs own async orchestration and set RLS context before tenant-scoped reads/writes.
- Services own business operations: normalization, scoring, action creation, webhook deduplication, Klaviyo API calls.
- The Python boundary owns feature engineering, uplift training, ranking metrics, and prediction export for Data Lab.
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
- Python 3 with pinned pandas, NumPy, and scikit-learn dependencies for Data Lab
- Active Storage with local development storage and private S3-compatible production storage

## Main Risks

- RLS is powerful but unforgiving. Every background job must set and clear shop context.
- Approval links are GET requests by design. Tokens must remain short-lived, single-use, and hashed at rest.
- Klaviyo execution currently assumes merchants configure a matching flow for the `ChurnGuard Retention Triggered` event.
- Production config must stay on Sidekiq. Mixing Solid Queue defaults with Sidekiq jobs breaks retries and queue priority.
- API keys are currently plain columns; use Rails encryption before onboarding real merchants.
- Data Lab results based on semi-synthetic outcomes demonstrate the method, not production causal evidence. Production uplift claims require randomized holdout data.

## Next Architecture Improvements

1. Add `encrypts :klaviyo_api_key` and migrate existing data.
2. Add a recurring scheduler for `DailyScoringJob.enqueue_all` and `TokenExpiryJob`.
3. Split production deployment into web and worker roles.
4. Add a typed execution result table or use `execution_queue_items` in `KlaviyoExecutionJob`.
5. Add a shop onboarding state for insufficient data instead of an empty approval queue.
6. Add an integration health check for Klaviyo keys before saving settings.
7. Move inline dashboard CSS into component stylesheets once the UI stabilizes.
