"""ChurnGuard ML v2 pipeline for UCI Online Retail II.

The notebook imports this module so the research flow stays readable while the
data cleaning, feature engineering, and export logic remain reusable.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Iterable
import json

import numpy as np
import pandas as pd


MODEL_VERSION = "online-retail-ii-churn-v2"
CHURN_HORIZON_DAYS = 90
HIGH_RISK_QUANTILE = 0.90
MEDIUM_RISK_QUANTILE = 0.75
FEATURE_COLUMNS = [
    "recency_days",
    "frequency",
    "lifetime_value",
    "average_order_value",
    "orders_30d",
    "orders_90d",
    "orders_180d",
    "customer_age_days",
    "avg_days_between_orders",
    "distinct_skus",
    "cancelled_invoice_count",
    "cancellation_ratio",
]


@dataclass(frozen=True)
class TrainingResult:
    model: object
    logistic_model: object
    metrics: dict
    risk_thresholds: dict


def load_online_retail_workbook(path: str | Path) -> pd.DataFrame:
    """Load both Online Retail II sheets into one dataframe."""
    path = Path(path).expanduser()
    frames = []
    workbook = pd.ExcelFile(path)

    for sheet_name in workbook.sheet_names:
        sheet = pd.read_excel(path, sheet_name=sheet_name)
        sheet["source_sheet"] = sheet_name
        frames.append(sheet)

    return pd.concat(frames, ignore_index=True)


def audit_raw_data(raw: pd.DataFrame) -> dict:
    invoice = raw["Invoice"].astype(str)
    return {
        "rows": int(len(raw)),
        "date_min": str(raw["InvoiceDate"].min()),
        "date_max": str(raw["InvoiceDate"].max()),
        "unique_customers": int(raw["Customer ID"].dropna().nunique()),
        "unique_invoices": int(raw["Invoice"].nunique()),
        "missing_customer_rows_pct": round(float(raw["Customer ID"].isna().mean() * 100), 2),
        "cancelled_invoice_rows": int(invoice.str.startswith("C", na=False).sum()),
        "negative_quantity_rows": int((raw["Quantity"] < 0).sum()),
        "nonpositive_price_rows": int((raw["Price"] <= 0).sum()),
    }


def clean_order_lines(raw: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Return paid line items and customer-level cancellation counts."""
    data = raw.copy()
    data["invoice_id"] = data["Invoice"].astype(str)
    data["shopify_customer_id"] = data["Customer ID"].astype("Int64").astype(str)
    data.loc[data["Customer ID"].isna(), "shopify_customer_id"] = pd.NA
    data["line_amount"] = data["Quantity"] * data["Price"]
    data["is_cancelled"] = data["invoice_id"].str.startswith("C", na=False) | (data["Quantity"] < 0)

    cancellations = (
        data[data["shopify_customer_id"].notna() & data["is_cancelled"]]
        .groupby("shopify_customer_id")["invoice_id"]
        .nunique()
        .reset_index(name="cancelled_invoice_count")
    )

    paid_lines = data[
        data["shopify_customer_id"].notna()
        & ~data["is_cancelled"]
        & (data["Quantity"] > 0)
        & (data["Price"] > 0)
    ].copy()

    paid_lines["ordered_at"] = pd.to_datetime(paid_lines["InvoiceDate"])
    return paid_lines, cancellations


def aggregate_orders(paid_lines: pd.DataFrame) -> pd.DataFrame:
    """Convert invoice line items into app-shaped paid orders."""
    orders = (
        paid_lines.groupby(["shopify_customer_id", "invoice_id"], as_index=False)
        .agg(
            ordered_at=("ordered_at", "min"),
            amount=("line_amount", "sum"),
            distinct_skus=("StockCode", "nunique"),
            line_count=("StockCode", "count"),
            country=("Country", lambda values: values.mode().iat[0] if not values.mode().empty else values.iloc[0]),
        )
        .query("amount > 0")
        .sort_values(["ordered_at", "shopify_customer_id"])
        .reset_index(drop=True)
    )
    orders["shopify_order_id"] = "ori-" + orders["invoice_id"].astype(str)
    orders["currency"] = "EUR"
    orders["status"] = "paid"
    return orders


def _feature_frame_for_snapshot(
    orders: pd.DataFrame,
    cancellations: pd.DataFrame,
    snapshot_date: pd.Timestamp,
    horizon_days: int,
    include_label: bool,
) -> pd.DataFrame:
    past = orders[orders["ordered_at"] <= snapshot_date].copy()
    if past.empty:
        return pd.DataFrame()

    grouped = past.groupby("shopify_customer_id")
    features = grouped.agg(
        first_order_at=("ordered_at", "min"),
        last_order_at=("ordered_at", "max"),
        frequency=("shopify_order_id", "nunique"),
        lifetime_value=("amount", "sum"),
        average_order_value=("amount", "mean"),
        distinct_skus=("distinct_skus", "sum"),
    ).reset_index()

    features["snapshot_date"] = snapshot_date
    features["recency_days"] = (snapshot_date - features["last_order_at"]).dt.days.clip(lower=0)
    features["customer_age_days"] = (snapshot_date - features["first_order_at"]).dt.days.clip(lower=0)
    features["avg_days_between_orders"] = np.where(
        features["frequency"] > 1,
        features["customer_age_days"] / (features["frequency"] - 1),
        features["customer_age_days"],
    )

    for days in (30, 90, 180):
        window_start = snapshot_date - pd.Timedelta(days=days)
        counts = (
            past[past["ordered_at"] > window_start]
            .groupby("shopify_customer_id")["shopify_order_id"]
            .nunique()
            .reset_index(name=f"orders_{days}d")
        )
        features = features.merge(counts, on="shopify_customer_id", how="left")
        features[f"orders_{days}d"] = features[f"orders_{days}d"].fillna(0)

    features = features.merge(cancellations, on="shopify_customer_id", how="left")
    features["cancelled_invoice_count"] = features["cancelled_invoice_count"].fillna(0)
    features["cancellation_ratio"] = features["cancelled_invoice_count"] / (
        features["frequency"] + features["cancelled_invoice_count"]
    ).replace(0, np.nan)
    features["cancellation_ratio"] = features["cancellation_ratio"].fillna(0)

    if include_label:
        horizon_end = snapshot_date + pd.Timedelta(days=horizon_days)
        future = orders[(orders["ordered_at"] > snapshot_date) & (orders["ordered_at"] <= horizon_end)]
        repeat_customers = set(future["shopify_customer_id"])
        features["churned"] = ~features["shopify_customer_id"].isin(repeat_customers)
        features["churned"] = features["churned"].astype(int)

    return features


def build_training_snapshots(
    orders: pd.DataFrame,
    cancellations: pd.DataFrame,
    horizon_days: int = CHURN_HORIZON_DAYS,
    min_history_days: int = 180,
    frequency: str = "MS",
) -> pd.DataFrame:
    first_snapshot = orders["ordered_at"].min() + pd.Timedelta(days=min_history_days)
    last_snapshot = orders["ordered_at"].max() - pd.Timedelta(days=horizon_days)
    snapshots = pd.date_range(first_snapshot, last_snapshot, freq=frequency)

    frames = [
        _feature_frame_for_snapshot(orders, cancellations, snapshot, horizon_days, include_label=True)
        for snapshot in snapshots
    ]
    frames = [frame for frame in frames if not frame.empty]
    if not frames:
        raise ValueError("No training snapshots were created. Check date range and horizon settings.")

    return pd.concat(frames, ignore_index=True)


def build_current_features(orders: pd.DataFrame, cancellations: pd.DataFrame) -> pd.DataFrame:
    snapshot_date = orders["ordered_at"].max()
    return _feature_frame_for_snapshot(
        orders,
        cancellations,
        snapshot_date=snapshot_date,
        horizon_days=CHURN_HORIZON_DAYS,
        include_label=False,
    )


def time_split_snapshots(snapshots: pd.DataFrame, test_fraction: float = 0.25) -> tuple[pd.DataFrame, pd.DataFrame]:
    unique_dates = sorted(snapshots["snapshot_date"].unique())
    split_index = max(1, int(len(unique_dates) * (1 - test_fraction)))
    split_date = unique_dates[split_index]
    train = snapshots[snapshots["snapshot_date"] < split_date].copy()
    test = snapshots[snapshots["snapshot_date"] >= split_date].copy()
    return train, test


def rfm_baseline_score(frame: pd.DataFrame) -> pd.Series:
    recency = frame["recency_days"].rank(pct=True)
    frequency = 1 - frame["frequency"].rank(pct=True)
    value = frame["lifetime_value"].rank(pct=True)
    return (0.5 * recency + 0.3 * frequency + 0.2 * value).clip(0, 1)


def _classification_metrics(y_true: Iterable[int], scores: Iterable[float], revenue: Iterable[float]) -> dict:
    from sklearn.metrics import average_precision_score, precision_score, recall_score, roc_auc_score

    y_true = np.asarray(list(y_true))
    scores = np.asarray(list(scores))
    revenue = np.asarray(list(revenue))
    threshold = np.quantile(scores, HIGH_RISK_QUANTILE)
    predicted_top = scores >= threshold
    top_revenue = float(revenue[predicted_top].sum())
    churn_revenue = float(revenue[y_true == 1].sum())

    return {
        "roc_auc": round(float(roc_auc_score(y_true, scores)), 4),
        "pr_auc": round(float(average_precision_score(y_true, scores)), 4),
        "precision_top_10pct": round(float(precision_score(y_true, predicted_top, zero_division=0)), 4),
        "recall_top_10pct": round(float(recall_score(y_true, predicted_top, zero_division=0)), 4),
        "revenue_at_risk_top_10pct": round(top_revenue, 2),
        "revenue_capture_top_10pct": round(top_revenue / churn_revenue, 4) if churn_revenue else 0,
    }


def train_models(snapshots: pd.DataFrame) -> TrainingResult:
    """Train RFM, logistic, and gradient boosting models."""
    from sklearn.ensemble import HistGradientBoostingClassifier
    from sklearn.impute import SimpleImputer
    from sklearn.linear_model import LogisticRegression
    from sklearn.pipeline import make_pipeline
    from sklearn.preprocessing import StandardScaler

    train, test = time_split_snapshots(snapshots)
    x_train = train[FEATURE_COLUMNS]
    y_train = train["churned"]
    x_test = test[FEATURE_COLUMNS]
    y_test = test["churned"]

    logistic = make_pipeline(
        SimpleImputer(strategy="median"),
        StandardScaler(),
        LogisticRegression(max_iter=1000, class_weight="balanced", random_state=42),
    )
    gradient_boosting = make_pipeline(
        SimpleImputer(strategy="median"),
        HistGradientBoostingClassifier(max_iter=250, learning_rate=0.06, random_state=42),
    )

    logistic.fit(x_train, y_train)
    gradient_boosting.fit(x_train, y_train)

    logistic_scores = logistic.predict_proba(x_test)[:, 1]
    ml_scores = gradient_boosting.predict_proba(x_test)[:, 1]
    rfm_scores = rfm_baseline_score(test)

    metrics = {
        "train_rows": int(len(train)),
        "test_rows": int(len(test)),
        "train_snapshot_min": str(train["snapshot_date"].min()),
        "train_snapshot_max": str(train["snapshot_date"].max()),
        "test_snapshot_min": str(test["snapshot_date"].min()),
        "test_snapshot_max": str(test["snapshot_date"].max()),
        "rfm_baseline": _classification_metrics(y_test, rfm_scores, test["lifetime_value"]),
        "logistic_regression": _classification_metrics(y_test, logistic_scores, test["lifetime_value"]),
        "gradient_boosting": _classification_metrics(y_test, ml_scores, test["lifetime_value"]),
    }

    thresholds = {
        "high": float(np.quantile(ml_scores, HIGH_RISK_QUANTILE)),
        "medium": float(np.quantile(ml_scores, MEDIUM_RISK_QUANTILE)),
    }
    return TrainingResult(
        model=gradient_boosting,
        logistic_model=logistic,
        metrics=metrics,
        risk_thresholds=thresholds,
    )


def score_current_customers(model: object, current_features: pd.DataFrame, thresholds: dict) -> pd.DataFrame:
    scored = current_features.copy()
    scored["risk_score"] = model.predict_proba(scored[FEATURE_COLUMNS])[:, 1]
    scored["risk_tier"] = np.select(
        [
            scored["risk_score"] >= thresholds["high"],
            scored["risk_score"] >= thresholds["medium"],
        ],
        ["high", "medium"],
        default="low",
    )
    scored["proposed_discount"] = np.select(
        [scored["risk_tier"].eq("high"), scored["risk_tier"].eq("medium")],
        ["15%", "10%"],
        default="",
    )
    scored["revenue_at_risk"] = (scored["lifetime_value"] * scored["risk_score"]).round(2)
    scored["reason"] = scored.apply(prediction_reason, axis=1)
    scored["model_version"] = MODEL_VERSION
    scored["scored_on"] = pd.to_datetime(scored["snapshot_date"]).dt.date.astype(str)
    return scored


def prediction_reason(row: pd.Series) -> str:
    recency = int(round(row["recency_days"]))
    frequency = int(round(row["frequency"]))
    score = round(float(row.get("risk_score", 0)) * 100)

    if row["risk_tier"] == "high":
        return f"ML v2 predicts {score}% churn risk: no order for {recency} days after {frequency} purchases."
    if row["risk_tier"] == "medium":
        return f"ML v2 flags early churn risk: {recency} days since last order and {frequency} lifetime purchases."
    return f"ML v2 sees low immediate churn risk: last order was {recency} days ago."


def build_customer_export(scored: pd.DataFrame) -> pd.DataFrame:
    customers = scored[
        [
            "shopify_customer_id",
            "lifetime_value",
            "risk_score",
            "risk_tier",
            "scored_on",
        ]
    ].copy()
    customers["name"] = "Customer " + customers["shopify_customer_id"].astype(str)
    customers["email"] = "customer_" + customers["shopify_customer_id"].astype(str) + "@example.invalid"
    return customers[
        [
            "shopify_customer_id",
            "name",
            "email",
            "lifetime_value",
            "risk_score",
            "risk_tier",
            "scored_on",
        ]
    ]


def build_order_export(orders: pd.DataFrame) -> pd.DataFrame:
    return orders[
        [
            "shopify_customer_id",
            "shopify_order_id",
            "amount",
            "currency",
            "status",
            "ordered_at",
        ]
    ].copy()


def build_prediction_export(scored: pd.DataFrame) -> pd.DataFrame:
    return scored[
        [
            "shopify_customer_id",
            "risk_score",
            "risk_tier",
            "lifetime_value",
            "revenue_at_risk",
            "proposed_discount",
            "reason",
            "model_version",
            "scored_on",
        ]
    ].copy()


def export_app_files(
    orders: pd.DataFrame,
    scored: pd.DataFrame,
    export_dir: str | Path = "research/exports",
) -> dict:
    export_dir = Path(export_dir)
    export_dir.mkdir(parents=True, exist_ok=True)

    outputs = {
        "customers": export_dir / "online_retail_customers_v2.csv",
        "orders": export_dir / "online_retail_orders_v2.csv",
        "predictions": export_dir / "churnguard_predictions_v2.csv",
    }
    build_customer_export(scored).to_csv(outputs["customers"], index=False)
    build_order_export(orders).to_csv(outputs["orders"], index=False)
    build_prediction_export(scored).to_csv(outputs["predictions"], index=False)
    return {key: str(path) for key, path in outputs.items()}


def save_model_artifacts(
    training_result: TrainingResult,
    model_dir: str | Path = "research/models",
) -> dict:
    import joblib

    model_dir = Path(model_dir)
    model_dir.mkdir(parents=True, exist_ok=True)
    model_path = model_dir / "churn_model_v2.joblib"
    schema_path = model_dir / "feature_schema_v2.json"

    joblib.dump(training_result.model, model_path)
    schema = {
        "model_version": MODEL_VERSION,
        "churn_horizon_days": CHURN_HORIZON_DAYS,
        "feature_columns": FEATURE_COLUMNS,
        "risk_thresholds": training_result.risk_thresholds,
        "metrics": training_result.metrics,
    }
    schema_path.write_text(json.dumps(schema, indent=2), encoding="utf-8")
    return {"model": str(model_path), "schema": str(schema_path)}
