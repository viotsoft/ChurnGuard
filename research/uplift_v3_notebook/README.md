# ChurnGuard Uplift V3 Notebook

This folder contains a complete Jupyter notebook for explaining and testing the ChurnGuard Uplift V3 approach.

## What dataset is used by the app now?

The current local application demo uses:

- `script/demo_prepare.rb`
- default shop: `warsawstyle.myshopify.com`
- underlying seed: `db/seeds/synthetic_shop.rb`
- scoring: `ScoringEngine`
- uplift decision layer: `UpliftDecisionEngine`

The generated dataset is a synthetic Shopify-style fashion store:

- customers: 62
- paid orders: 292
- current Uplift V3 demo actions: 33
- currency: EUR
- fields: customer id, name, email, LTV, recency, frequency, AOV, risk tier, risk score, treatment key, uplift score, expected incremental revenue.


Live Rails export currently present:

- `data/current_app_customers.csv` — 62 customers
- `data/current_app_orders.csv` — 292 orders
- `data/current_app_actions.csv` — 43 actions

The notebook loads these live-export files first. If they are absent, it falls back to the reproducible synthetic CSV files.


## Files

- `churnguard_uplift_v3_demo.ipynb` — full notebook.
- `data/churnguard_synthetic_customers.csv` — customer-level application dataset.
- `data/churnguard_synthetic_orders.csv` — order-level application dataset.
- `data/churnguard_uplift_v3_demo_actions.csv` — current app-like Uplift V3 action export.
- `data/current_app_customers.csv` — optional live Rails export from the current app DB.
- `data/current_app_orders.csv` — optional live Rails export from the current app DB.
- `data/current_app_actions.csv` — optional live Rails export from the current app DB.
- `exports/uplift_v3_predictions_for_churnguard.csv` — created when the notebook is run.

## Honest limitation

This is not production uplift training data. The current app data has no real randomized treatment/control outcomes. The notebook therefore creates a semi-synthetic treatment/control experiment to demonstrate the uplift methodology.
