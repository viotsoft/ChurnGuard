#!/usr/bin/env python3
"""Offline CSV uplift pipeline used by ChurnGuard Data Lab.

The process accepts only filesystem paths supplied by the Rails worker, writes a
summary JSON plus a private prediction CSV, and performs no network requests.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import hmac
import json
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import train_test_split
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler


MODEL_VERSION = "uplift-lab-v1"
FEATURE_COLUMNS = [
    "recency_days",
    "frequency",
    "monetary_value",
    "average_order_value",
    "customer_tenure_days",
    "average_days_between_orders",
    "orders_30d",
    "orders_90d",
    "orders_180d",
]
MIN_CUSTOMERS = 500
MIN_GROUP_SIZE = 100
MIN_POSITIVES_PER_GROUP = 20


def detect_delimiter(path: Path) -> str:
    with path.open("r", encoding="utf-8-sig", errors="replace") as handle:
        first_line = handle.readline()
    return ";" if first_line.count(";") > first_line.count(",") else ","


def load_mapped_csv(path: Path, mapping: dict[str, str], required: list[str]) -> pd.DataFrame:
    missing_mapping = [field for field in required if not mapping.get(field)]
    if missing_mapping:
        raise ValueError(f"Missing column mapping: {', '.join(missing_mapping)}")

    source_columns = list(dict.fromkeys(mapping.values()))
    frame = pd.read_csv(
        path,
        sep=detect_delimiter(path),
        encoding="utf-8-sig",
        usecols=source_columns,
        low_memory=False,
    )
    reverse_mapping = {source: canonical for canonical, source in mapping.items() if source}
    return frame.rename(columns=reverse_mapping)


def parse_binary(series: pd.Series, field: str) -> pd.Series:
    aliases = {
        "1": 1,
        "true": 1,
        "yes": 1,
        "treatment": 1,
        "treated": 1,
        "test": 1,
        "exposed": 1,
        "0": 0,
        "false": 0,
        "no": 0,
        "control": 0,
        "untreated": 0,
        "holdout": 0,
    }
    parsed = series.astype(str).str.strip().str.lower().map(aliases)
    if parsed.isna().any():
        examples = series[parsed.isna()].astype(str).drop_duplicates().head(5).tolist()
        rows = csv_rows(series.index[parsed.isna()])
        raise ValueError(f"{field} must be binary at CSV rows {rows}. Unsupported values: {examples}")
    return parsed.astype(int)


def csv_rows(indices: pd.Index, limit: int = 10) -> str:
    rows = [str(int(index) + 2) for index in indices[:limit]]
    suffix = ", ..." if len(indices) > limit else ""
    return ", ".join(rows) + suffix


def prepare_orders(path: Path, mapping: dict[str, str]) -> tuple[pd.DataFrame, dict]:
    orders = load_mapped_csv(
        path,
        mapping,
        required=["customer_id", "order_id", "ordered_at", "amount"],
    )
    raw_rows = len(orders)
    orders["customer_id"] = orders["customer_id"].fillna("").astype(str).str.strip()
    orders["order_id"] = orders["order_id"].fillna("").astype(str).str.strip()
    orders["ordered_at"] = pd.to_datetime(orders["ordered_at"], errors="coerce", utc=True)
    orders["amount"] = pd.to_numeric(orders["amount"], errors="coerce")

    invalid_required = (
        orders["customer_id"].eq("")
        | orders["order_id"].eq("")
        | orders["ordered_at"].isna()
        | orders["amount"].isna()
    )
    if invalid_required.any():
        raise ValueError(
            "Orders CSV has blank IDs, invalid dates, or non-numeric amounts at CSV rows "
            f"{csv_rows(orders.index[invalid_required])}."
        )

    if "status" in orders:
        excluded = {"cancelled", "canceled", "refunded", "void", "failed"}
        orders = orders[~orders["status"].astype(str).str.strip().str.lower().isin(excluded)]

    orders = orders.dropna(subset=["customer_id", "order_id", "ordered_at", "amount"])
    orders = orders[(orders["customer_id"] != "") & (orders["order_id"] != "")]
    orders = orders[orders["amount"] > 0]
    before_dedup = len(orders)
    orders = orders.sort_values("ordered_at").drop_duplicates("order_id", keep="last")
    orders = orders.sort_values(["customer_id", "ordered_at"]).reset_index(drop=True)
    if orders.empty:
        raise ValueError("No valid positive orders remain after cleaning.")

    audit = {
        "raw_order_rows": int(raw_rows),
        "valid_orders": int(len(orders)),
        "duplicate_orders_removed": int(before_dedup - len(orders)),
        "unique_customers_in_orders": int(orders["customer_id"].nunique()),
        "order_date_min": orders["ordered_at"].min().isoformat(),
        "order_date_max": orders["ordered_at"].max().isoformat(),
    }
    return orders, audit


def prepare_experiment(
    path: Path,
    mapping: dict[str, str],
    global_campaign_date: str | None,
) -> pd.DataFrame:
    experiment = load_mapped_csv(
        path,
        mapping,
        required=["customer_id", "treatment", "outcome"],
    )
    experiment["customer_id"] = experiment["customer_id"].fillna("").astype(str).str.strip()
    if experiment["customer_id"].eq("").any():
        raise ValueError(
            "Experiment CSV has blank customer IDs at CSV rows "
            f"{csv_rows(experiment.index[experiment['customer_id'].eq('')])}."
        )
    if experiment["customer_id"].duplicated().any():
        duplicate_rows = experiment.index[experiment["customer_id"].duplicated(keep=False)]
        raise ValueError(
            "Experiment CSV must contain one row per customer. Duplicates appear at CSV rows "
            f"{csv_rows(duplicate_rows)}."
        )
    experiment["treatment"] = parse_binary(experiment["treatment"], "treatment")
    experiment["outcome"] = parse_binary(experiment["outcome"], "outcome")

    if "assigned_at" in experiment:
        experiment["assigned_at"] = pd.to_datetime(experiment["assigned_at"], errors="coerce", utc=True)
    elif global_campaign_date:
        experiment["assigned_at"] = pd.Timestamp(global_campaign_date, tz="UTC")
    else:
        raise ValueError("Campaign date is required when assigned_at is not mapped.")
    if experiment["assigned_at"].isna().any():
        invalid_rows = experiment.index[experiment["assigned_at"].isna()]
        raise ValueError(f"Experiment assignment dates are invalid at CSV rows {csv_rows(invalid_rows)}.")
    return experiment


def build_features(orders: pd.DataFrame, assignments: pd.DataFrame) -> tuple[pd.DataFrame, int]:
    joined = orders.merge(assignments[["customer_id", "assigned_at"]], on="customer_id", how="inner")
    joined = joined[joined["ordered_at"] < joined["assigned_at"]].copy()
    if joined.empty:
        raise ValueError("No pre-treatment orders remain. Check campaign dates and mappings.")

    joined["days_before"] = (joined["assigned_at"] - joined["ordered_at"]).dt.total_seconds() / 86_400
    joined["orders_30d"] = (joined["days_before"] <= 30).astype(int)
    joined["orders_90d"] = (joined["days_before"] <= 90).astype(int)
    joined["orders_180d"] = (joined["days_before"] <= 180).astype(int)
    joined = joined.sort_values(["customer_id", "ordered_at"])
    joined["order_gap"] = joined.groupby("customer_id")["ordered_at"].diff().dt.total_seconds() / 86_400

    features = joined.groupby("customer_id", as_index=False).agg(
        assigned_at=("assigned_at", "first"),
        first_order_at=("ordered_at", "min"),
        last_order_at=("ordered_at", "max"),
        frequency=("order_id", "nunique"),
        monetary_value=("amount", "sum"),
        average_order_value=("amount", "mean"),
        average_days_between_orders=("order_gap", "mean"),
        orders_30d=("orders_30d", "sum"),
        orders_90d=("orders_90d", "sum"),
        orders_180d=("orders_180d", "sum"),
    )
    features["recency_days"] = (
        features["assigned_at"] - features["last_order_at"]
    ).dt.total_seconds() / 86_400
    features["customer_tenure_days"] = (
        features["assigned_at"] - features["first_order_at"]
    ).dt.total_seconds() / 86_400
    features["average_days_between_orders"] = features["average_days_between_orders"].fillna(
        features["recency_days"]
    )
    features[FEATURE_COLUMNS] = features[FEATURE_COLUMNS].replace([np.inf, -np.inf], np.nan).fillna(0)
    dropped = assignments["customer_id"].nunique() - features["customer_id"].nunique()
    return features[["customer_id", *FEATURE_COLUMNS]], int(max(dropped, 0))


def create_semi_synthetic_experiment(
    orders: pd.DataFrame,
    outcome_window_days: int,
    seed: int,
) -> tuple[pd.DataFrame, pd.DataFrame, np.ndarray]:
    cutoff = orders["ordered_at"].max() - pd.Timedelta(days=outcome_window_days)
    customer_ids = orders.loc[orders["ordered_at"] < cutoff, "customer_id"].drop_duplicates()
    assignments = pd.DataFrame({"customer_id": customer_ids, "assigned_at": cutoff})
    features, _ = build_features(orders, assignments)
    if len(features) < MIN_CUSTOMERS:
        raise ValueError(f"Simulation requires at least {MIN_CUSTOMERS} customers with pre-cutoff orders.")

    post_customers = set(
        orders.loc[
            (orders["ordered_at"] >= cutoff)
            & (orders["ordered_at"] < cutoff + pd.Timedelta(days=outcome_window_days)),
            "customer_id",
        ]
    )
    natural_outcome = features["customer_id"].isin(post_customers).astype(int).to_numpy()
    x = np.log1p(features[FEATURE_COLUMNS].to_numpy(dtype=float))
    if natural_outcome.min() != natural_outcome.max():
        baseline_model = make_pipeline(StandardScaler(), LogisticRegression(max_iter=1_000, random_state=seed))
        baseline_model.fit(x, natural_outcome)
        p_control = baseline_model.predict_proba(x)[:, 1]
    else:
        p_control = np.full(len(features), max(float(natural_outcome.mean()), 0.08))

    rng = np.random.default_rng(seed)
    recency = np.clip(features["recency_days"].to_numpy() / 365.0, 0, 1)
    frequency = features["frequency"].to_numpy()
    recent_loyal = (frequency >= 6) & (features["recency_days"].to_numpy() < 90)
    true_effect = 0.01 + 0.17 * recency + 0.055 * ((frequency >= 2) & (frequency <= 5))
    true_effect -= 0.22 * recent_loyal
    true_effect = np.clip(true_effect, -0.14, 0.30)

    treatment = rng.binomial(1, 0.5, len(features))
    p_treatment = np.clip(p_control + true_effect, 0.005, 0.95)
    observed_probability = np.where(treatment == 1, p_treatment, p_control)
    outcome = rng.binomial(1, observed_probability)
    experiment = features[["customer_id"]].copy()
    experiment["treatment"] = treatment
    experiment["outcome"] = outcome
    experiment["assigned_at"] = cutoff
    return features, experiment, true_effect


def validate_experiment(frame: pd.DataFrame) -> None:
    if len(frame) < MIN_CUSTOMERS:
        raise ValueError(f"Real uplift training requires at least {MIN_CUSTOMERS} eligible customers.")
    group_sizes = frame.groupby("treatment").size().to_dict()
    positives = frame.groupby("treatment")["outcome"].sum().to_dict()
    for group in (0, 1):
        if group_sizes.get(group, 0) < MIN_GROUP_SIZE:
            raise ValueError(f"Treatment group {group} needs at least {MIN_GROUP_SIZE} customers.")
        if positives.get(group, 0) < MIN_POSITIVES_PER_GROUP:
            raise ValueError(f"Treatment group {group} needs at least {MIN_POSITIVES_PER_GROUP} positive outcomes.")


def fit_s_learner(x: np.ndarray, treatment: np.ndarray, outcome: np.ndarray, seed: int):
    model = make_pipeline(StandardScaler(), LogisticRegression(max_iter=1_000, random_state=seed))
    model.fit(np.column_stack([x, treatment]), outcome)
    return model


def predict_s_learner(model, x: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    p_treatment = model.predict_proba(np.column_stack([x, np.ones(len(x))]))[:, 1]
    p_control = model.predict_proba(np.column_stack([x, np.zeros(len(x))]))[:, 1]
    return p_treatment, p_control


def fit_t_learner(x: np.ndarray, treatment: np.ndarray, outcome: np.ndarray, seed: int):
    params = dict(max_iter=160, learning_rate=0.06, max_leaf_nodes=15, l2_regularization=1.0, random_state=seed)
    treated_model = HistGradientBoostingClassifier(**params).fit(x[treatment == 1], outcome[treatment == 1])
    control_model = HistGradientBoostingClassifier(**params).fit(x[treatment == 0], outcome[treatment == 0])
    return treated_model, control_model


def predict_t_learner(models, x: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    treated_model, control_model = models
    return treated_model.predict_proba(x)[:, 1], control_model.predict_proba(x)[:, 1]


def uplift_metrics(outcome: np.ndarray, treatment: np.ndarray, score: np.ndarray) -> dict:
    order = np.argsort(-score)
    y = outcome[order].astype(float)
    t = treatment[order].astype(int)
    count_t = np.cumsum(t)
    count_c = np.cumsum(1 - t)
    response_t = np.cumsum(y * t)
    response_c = np.cumsum(y * (1 - t))
    rate_t = np.divide(response_t, count_t, out=np.zeros_like(response_t), where=count_t > 0)
    rate_c = np.divide(response_c, count_c, out=np.zeros_like(response_c), where=count_c > 0)
    gain = (rate_t - rate_c) * np.arange(1, len(y) + 1)
    normalized_gain = gain / max(len(y), 1)
    x_axis = np.linspace(1 / len(y), 1, len(y))
    auuc = float(np.trapezoid(normalized_gain, x=x_axis))
    qini = float(auuc - normalized_gain[-1] / 2)
    top_n = max(int(len(y) * 0.30), 1)
    top_t = t[:top_n] == 1
    top_c = ~top_t
    lift_at_30 = float(y[:top_n][top_t].mean() - y[:top_n][top_c].mean()) if top_t.any() and top_c.any() else 0.0
    observed = float(outcome[treatment == 1].mean() - outcome[treatment == 0].mean())
    return {"auuc": auuc, "qini": qini, "lift_at_30": lift_at_30, "observed_uplift": observed}


def observed_deciles(outcome: np.ndarray, treatment: np.ndarray, score: np.ndarray) -> list[dict]:
    order = np.argsort(-score)
    groups = np.array_split(order, 10)
    rows = []
    for index, indices in enumerate(groups, start=1):
        y = outcome[indices]
        t = treatment[indices]
        treated = y[t == 1]
        control = y[t == 0]
        observed = float(treated.mean() - control.mean()) if len(treated) and len(control) else 0.0
        rows.append({
            "decile": index,
            "customers": int(len(indices)),
            "observed_uplift": observed,
            "average_predicted_uplift": float(score[indices].mean()),
        })
    return rows


def segment_for(p_control: float, p_treatment: float) -> tuple[str, str]:
    uplift = p_treatment - p_control
    if uplift <= -0.01:
        return "do_not_disturb", "Hold out: predicted negative effect"
    if p_control >= 0.45 and p_treatment >= 0.45:
        return "sure_thing", "Avoid discount: likely to purchase anyway"
    if p_control <= 0.08 and p_treatment <= 0.08:
        return "lost_cause", "Do not target: low response in both scenarios"
    if uplift >= 0.02:
        return "persuadable", "Target with retention treatment"
    return "uncertain", "Keep in measurement holdout"


def mask_customer(customer_id: str) -> str:
    suffix = customer_id[-4:] if len(customer_id) >= 4 else customer_id
    return f"Customer ...{suffix}"


def main(config: dict) -> None:
    orders, audit = prepare_orders(Path(config["orders_path"]), config["mapping"]["orders"])
    warnings: list[str] = []
    true_effect = None

    if config.get("experiment_path"):
        experiment = prepare_experiment(
            Path(config["experiment_path"]),
            config["mapping"]["experiment"],
            config.get("campaign_date"),
        )
        features, dropped = build_features(orders, experiment)
        data = experiment.merge(features, on="customer_id", how="inner")
        validate_experiment(data)
        if config.get("sample_dataset"):
            evidence_type = "semi_synthetic"
            evidence_note = (
                "Treatment and outcomes come from the reproducible ChurnGuard sample. "
                "This validates the pipeline, not a merchant campaign."
            )
        else:
            evidence_type = "experimental" if config.get("randomized_treatment") else "observational"
            evidence_note = (
                "Treatment and control outcomes were evaluated on a declared randomized holdout."
                if evidence_type == "experimental"
                else "Treatment assignment was not confirmed as random, so uplift is an observational estimate."
            )
        if dropped:
            warnings.append(f"{dropped} experiment customers had no valid pre-treatment orders and were excluded.")
        audit["experiment_rows"] = int(len(experiment))
    else:
        features, experiment, true_effect = create_semi_synthetic_experiment(
            orders,
            int(config["outcome_window_days"]),
            int(config["seed"]),
        )
        data = experiment.merge(features, on="customer_id", how="inner")
        validate_experiment(data)
        evidence_type = "semi_synthetic"
        evidence_note = "Treatment and outcomes were generated from real order patterns with a known heterogeneous effect."
        warnings.append("Simulation metrics demonstrate pipeline recovery, not the merchant's real campaign impact.")

    x = np.log1p(data[FEATURE_COLUMNS].to_numpy(dtype=float))
    treatment = data["treatment"].to_numpy(dtype=int)
    outcome = data["outcome"].to_numpy(dtype=int)
    strata = treatment.astype(str) + "_" + outcome.astype(str)
    indices = np.arange(len(data))
    train_idx, test_idx = train_test_split(
        indices,
        test_size=0.30,
        random_state=int(config["seed"]),
        stratify=strata,
    )

    s_model = fit_s_learner(x[train_idx], treatment[train_idx], outcome[train_idx], int(config["seed"]))
    s_pt, s_pc = predict_s_learner(s_model, x[test_idx])
    s_metrics = uplift_metrics(outcome[test_idx], treatment[test_idx], s_pt - s_pc)

    t_models = fit_t_learner(x[train_idx], treatment[train_idx], outcome[train_idx], int(config["seed"]))
    t_pt, t_pc = predict_t_learner(t_models, x[test_idx])
    t_metrics = uplift_metrics(outcome[test_idx], treatment[test_idx], t_pt - t_pc)

    if t_metrics["auuc"] >= s_metrics["auuc"]:
        selected_name = "t_learner_hist_gradient_boosting"
        final_models = fit_t_learner(x, treatment, outcome, int(config["seed"]))
        p_treatment, p_control = predict_t_learner(final_models, x)
        selected_test_score = t_pt - t_pc
        selected_metrics = t_metrics
    else:
        selected_name = "s_learner_logistic_regression"
        final_model = fit_s_learner(x, treatment, outcome, int(config["seed"]))
        p_treatment, p_control = predict_s_learner(final_model, x)
        selected_test_score = s_pt - s_pc
        selected_metrics = s_metrics

    uplift = np.clip(p_treatment - p_control, -1, 1)
    data = data.copy()
    data["probability_treatment"] = p_treatment
    data["probability_control"] = p_control
    data["uplift_score"] = uplift
    data["expected_incremental_revenue"] = uplift * data["average_order_value"]
    data["expected_incremental_profit"] = (
        uplift * data["average_order_value"] * float(config["gross_margin_rate"])
        - p_treatment * data["average_order_value"] * float(config["discount_rate"])
        - float(config["contact_cost"])
    )
    segments = [segment_for(pc, pt) for pc, pt in zip(p_control, p_treatment)]
    data["segment"] = [item[0] for item in segments]
    data["recommended_action"] = [item[1] for item in segments]
    data = data.sort_values("uplift_score", ascending=False).reset_index(drop=True)
    data["rank"] = np.arange(1, len(data) + 1)
    secret = config["hash_secret"].encode("utf-8")
    data["customer_key_hash"] = data["customer_id"].map(
        lambda value: hmac.new(secret, str(value).encode("utf-8"), hashlib.sha256).hexdigest()
    )
    data["customer_label"] = data["customer_id"].astype(str).map(mask_customer)

    output_dir = Path(config["output_dir"])
    output_dir.mkdir(parents=True, exist_ok=True)
    export_columns = [
        "rank", "customer_id", "customer_key_hash", "customer_label", "segment",
        "recommended_action", "uplift_score", "probability_treatment", "probability_control",
        "average_order_value", "expected_incremental_revenue", "expected_incremental_profit",
        *FEATURE_COLUMNS,
    ]
    data[export_columns].to_csv(output_dir / "predictions.csv", index=False, quoting=csv.QUOTE_MINIMAL)

    selected_metrics = dict(selected_metrics)
    selected_metrics.update({
        "customers": int(len(data)),
        "model_selected": selected_name,
        "s_learner_auuc": float(s_metrics["auuc"]),
        "t_learner_auuc": float(t_metrics["auuc"]),
        "treated_customers": int((treatment == 1).sum()),
        "control_customers": int((treatment == 0).sum()),
        "treated_conversion_rate": float(outcome[treatment == 1].mean()),
        "control_conversion_rate": float(outcome[treatment == 0].mean()),
        "evidence_note": evidence_note,
    })
    if true_effect is not None:
        selected_metrics["ground_truth_rank_correlation"] = float(
            pd.Series(uplift).corr(pd.Series(true_effect), method="spearman")
        )
        selected_metrics["negative_uplift_customers"] = int((uplift < 0).sum())
        selected_metrics["ground_truth_negative_customers"] = int((true_effect < 0).sum())

    summary = {
        "evidence_type": evidence_type,
        "model_version": f"{MODEL_VERSION}-{selected_name}",
        "metrics": selected_metrics,
        "deciles": observed_deciles(outcome[test_idx], treatment[test_idx], selected_test_score),
        "warnings": warnings,
        "data_audit": audit,
    }
    (output_dir / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True)
    arguments = parser.parse_args()
    main(json.loads(Path(arguments.config).read_text(encoding="utf-8")))
