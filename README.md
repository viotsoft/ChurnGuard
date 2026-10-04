# ChurnGuard

ChurnGuard is an action-first retention app for Shopify merchants. It ingests order/customer webhooks, scores customers with rule-based RFM logic, creates approval cards for at-risk customers, and executes approved retention actions through Klaviyo.

Read `DESIGN.md` before changing UI. The approval queue is the primary product surface and must stay chart-free.

## Stack

- Ruby 3.3.11
- Rails 8.1
- PostgreSQL 16+
- Redis + Sidekiq
- Shopify App OAuth/webhooks
- Postmark transactional email
- Klaviyo Events API

## Local Setup

1. Install Ruby 3.3.11 and make sure `ruby -v` reports that version in this folder.
2. Install PostgreSQL and Redis.
3. Copy `.env.example` to `.env` and fill in local values.
4. Install dependencies:

```sh
bundle install
```

5. Prepare the database:

```sh
bin/rails db:prepare
```

6. Seed a useful demo shop:

```sh
bin/rails runner db/seeds/synthetic_shop.rb
bin/rails runner "shop = Shop.find_by!(shopify_domain: 'warsawstyle.myshopify.com'); RlsContext.set!(shop.id); ScoringEngine.call(shop: shop); ActionCreator.call(shop: shop)"
```

7. Start the app and worker:

```sh
bin/dev
bundle exec sidekiq -C config/sidekiq.yml
```

In development, open:

```text
http://localhost:3000/dev/login?shop=warsawstyle.myshopify.com
```

## Local Demo Data

Prepare a showroom dataset with realistic customers, orders, pending approvals, and completed action history:

```sh
bin/rails runner script/demo_prepare.rb
```

Then start Rails and Sidekiq:

```sh
bin/dev
bundle exec sidekiq -C config/sidekiq.yml
```

Open:

```text
http://localhost:3000/dev/login?shop=warsawstyle.myshopify.com
```

## Tests

```sh
bundle exec rspec
```

## Architecture

See `docs/ARCHITECTURE.md`.

## Production Notes

Production needs a web process and a Sidekiq worker process. Required environment variables include `RAILS_MASTER_KEY`, `DATABASE_URL`, `REDIS_URL`, `SHOPIFY_API_KEY`, `SHOPIFY_API_SECRET`, `HOST`, `APP_HOST`, and `POSTMARK_API_TOKEN`.

## Data Lab

The public CSV uplift sandbox is available at `http://localhost:3000/lab` and does
not require a Shopify session. It supports an orders CSV plus an optional binary
treatment/control experiment CSV. Without experiment outcomes it runs a clearly
labelled semi-synthetic validation.

Install the pinned ML dependencies and point Rails at that Python executable:

```bash
python3 -m venv .venv-uplift
.venv-uplift/bin/pip install -r research/ml/requirements-uplift-lab.txt
export PYTHON_BIN="$PWD/.venv-uplift/bin/python3"
```

Prepare the new tables, then run the web and worker processes:

```bash
bin/rails db:prepare
bin/rails server -p 3000
bundle exec sidekiq -C config/sidekiq.yml
```

Open `http://localhost:3000/lab`. The **Use sample dataset** flow creates a
reproducible 10,000-customer experiment and runs through the same queue and
Python pipeline as an uploaded client dataset.

In development, the sign-in page displays the one-time magic link after the
email job is queued. Production uses the existing Postmark delivery setup.

Raw CSV files expire after 24 hours. Derived reports and private prediction
exports expire after 30 days via `AnalysisRetentionJob`. Schedule
`AnalysisRetentionJob.perform_later` once per day in production. Private object
storage uses `S3_BUCKET`, `S3_REGION`, `S3_ENDPOINT`, `AWS_ACCESS_KEY_ID`, and
`AWS_SECRET_ACCESS_KEY`; set `DATA_LAB_HASH_SECRET` to a dedicated secret used
for exported customer-key hashes.
