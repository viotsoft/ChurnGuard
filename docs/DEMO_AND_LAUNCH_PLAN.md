# ChurnGuard Demo And Launch Plan

This plan is for getting ChurnGuard from current MVP to something credible for investors and first B2B Shopify customer conversations.

## Current State

Already working:

- Shopify-style shop, customer, order, event, and action data model
- Postgres row-level security for tenant isolation
- Webhook ingestion and deduplication
- RFM churn scoring baseline
- Pending approval queue
- One-tap email token approval flow
- Dashboard approve/skip actions
- Klaviyo execution job path
- History and insights screens
- RSpec coverage for services, requests, jobs, RLS, and end-to-end flow

The app is demoable, but it is not production-ready yet.

## Investor Demo Goal

Show that ChurnGuard is not another analytics dashboard. The demo should make this obvious in under two minutes:

1. A merchant opens the app.
2. They see pending approval cards, not charts.
3. Revenue at risk appears before the customer's name.
4. The merchant approves one action.
5. The action moves through the execution path.
6. History and insights prove the closed loop.

## Customer Demo Goal

Show a Shopify merchant a practical workflow:

1. ChurnGuard identifies customers who are likely to drift away.
2. Each card explains why the customer matters.
3. The owner can approve or skip without learning a new analytics tool.
4. Approved actions trigger existing Klaviyo flows.
5. The merchant can see recovered revenue and failed integrations.

## Local Demo Setup

Use the showroom script:

```sh
bin/rails db:prepare
bin/rails runner script/demo_prepare.rb
bin/dev
bundle exec sidekiq -C config/sidekiq.yml
```

Then open:

```text
http://localhost:3000/dev/login?shop=warsawstyle.myshopify.com
```

If port 3000 is unavailable, run Rails on another port and replace the URL:

```sh
SHOPIFY_API_KEY=dev_key SHOPIFY_API_SECRET=dev_secret HOST=localhost:3001 APP_HOST=localhost:3001 bin/rails server -p 3001 -P tmp/pids/server-3001.pid
```

```text
http://localhost:3001/dev/login?shop=warsawstyle.myshopify.com
```

## Demo Script

Use this narration:

> ChurnGuard is an approval queue for retention. It predicts which customers are likely to stop buying, estimates the revenue at risk, recommends an action, and executes it through Klaviyo after owner approval.

Walkthrough:

1. Open the approval queue.
2. Point out revenue at risk in the top-right of the card.
3. Explain the risk reason in plain business language.
4. Click approve on one card.
5. Open History.
6. Open Insights.
7. Explain that charts are intentionally secondary because the product is action-first.

## Product Completion Plan

### Phase 1: Demo Hardening

Goal: make the product reliable enough for mentor, investor, and merchant walkthroughs.

- Create repeatable demo data with pending and completed actions.
- Keep the approval queue visually polished and mobile-safe.
- Add a visible onboarding state for shops with insufficient data.
- Add a Klaviyo connection status card to Settings.
- Make failed execution states easy to explain.
- Add a short product walkthrough note for the founder.

Done when:

- A fresh checkout can run one command and show a real-looking queue.
- Dashboard, History, Insights, and Settings all have meaningful demo data.
- Tests pass.

### Phase 2: Real Shopify Pilot

Goal: connect one real development Shopify store.

- Create Shopify Partner app.
- Configure OAuth callback URLs.
- Register mandatory GDPR webhooks.
- Register order/customer webhooks.
- Use ngrok or Cloudflare Tunnel for local pilot testing.
- Import historical orders, not only future webhooks.
- Verify app install and uninstall lifecycle.

Done when:

- A real Shopify dev store installs the app.
- Historical data imports into customers/orders.
- New Shopify orders create normalized events.
- Scoring creates pending actions.

### Phase 3: Klaviyo Execution

Goal: prove the full retention loop.

- Validate Klaviyo API keys before saving.
- Document the required Klaviyo flow listening for `ChurnGuard Retention Triggered`.
- Send a test event from Settings.
- Add execution result logging.
- Surface missing API key and failed-send states in UI.

Done when:

- Approving a card triggers a real Klaviyo event.
- A test customer receives or qualifies for the configured flow.
- Failures are visible and recoverable.

### Phase 4: ML Readiness

Goal: move from RFM baseline to defensible churn prediction.

- Export customer-order snapshots.
- Build a Jupyter notebook on UCI Online Retail II or merchant data.
- Compare RFM vs logistic regression vs gradient boosting.
- Evaluate Precision@TopK, PR-AUC, and revenue-at-risk captured.
- Store `risk_score`, `risk_tier`, `model_version`, and explanation.
- Keep RFM fallback when shop data is too sparse.

Done when:

- You can explain when ML beats RFM.
- Investor demo includes a credible ML roadmap and one notebook result.
- The product still creates approval cards, not ML dashboards.

### Phase 5: Production Readiness

Goal: safely onboard first B2B merchants.

- Encrypt `klaviyo_api_key`.
- Move all secrets to environment/credentials.
- Configure production Postgres and Redis.
- Run Sidekiq as a separate worker process.
- Add daily scoring and token expiry scheduler.
- Add Sentry alerts.
- Add privacy policy, DPA, and deletion workflow.
- Configure domain, SSL, Shopify app listing requirements.

Done when:

- One pilot merchant can use ChurnGuard without local developer intervention.
- Data deletion and uninstall paths are tested.
- Worker, email, webhook, and execution failures are observable.

## Must-Have Before Investors

- Working local demo with real-looking queue.
- 10-slide pitch deck.
- Product screenshots or short screen recording.
- One-page technical architecture.
- One-page ML research plan.
- Clear first pilot acquisition plan.

## Must-Have Before First Paying Shopify Customer

- Real Shopify OAuth install.
- Historical order import.
- Encrypted integration credentials.
- Klaviyo test-send flow.
- Privacy policy and DPA.
- Production monitoring.
- Manual support path for failed actions.

## Recommended Next Work Order

1. Finish demo hardening.
2. Record a two-minute product demo.
3. Connect a Shopify development store.
4. Add historical order import.
5. Validate Klaviyo test execution.
6. Recruit five pilot merchants.
7. Run a manual-retention trial in parallel with the product.
8. Add ML only after baseline RFM has real comparison data.
