# ChurnGuard ML v2: Online Retail II

This folder contains the first machine-learning churn pipeline for the ChurnGuard
investor demo.

## Run the notebook

1. Open `research/notebooks/churn_ml_v2_online_retail.ipynb` in Jupyter.
2. Keep the dataset at `/Users/serhii.kravchenko/Downloads/online_retail_II.xlsx`.
3. Run every notebook cell from top to bottom.

The notebook exports:

- `research/exports/online_retail_customers_v2.csv`
- `research/exports/online_retail_orders_v2.csv`
- `research/exports/churnguard_predictions_v2.csv`
- `research/models/churn_model_v2.joblib`
- `research/models/feature_schema_v2.json`

## Import into Rails

After the notebook finishes, run this from the project root:

```bash
bin/rails runner script/import_online_retail_ml_demo.rb
```

The importer creates or updates the demo shop
`online-retail-ii.myshopify.com`, imports customers and paid orders, updates ML
risk scores, and creates pending approval actions for high and medium risk
customers.

The approval queue UI is unchanged. ChurnGuard still opens on the action-first
card flow defined in `DESIGN.md`.
