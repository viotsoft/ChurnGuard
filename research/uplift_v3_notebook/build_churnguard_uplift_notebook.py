import csv
import json
import math
from datetime import datetime, timedelta
from pathlib import Path


ROOT = Path(__file__).resolve().parent
DATA_DIR = ROOT / "data"
EXPORT_DIR = ROOT / "exports"
NOTEBOOK_PATH = ROOT / "churnguard_uplift_v3_demo.ipynb"
README_PATH = ROOT / "README.md"

AS_OF_DATE = datetime(2026, 9, 28)
SHOPIFY_DOMAIN = "warsawstyle.myshopify.com"

CUSTOMER_PROFILES = [
    (365, 1, (45, 120)), (320, 1, (89, 89)), (290, 2, (120, 180)),
    (275, 1, (55, 55)), (260, 2, (90, 150)), (245, 1, (200, 200)),
    (230, 2, (130, 220)), (215, 1, (75, 75)), (207, 1, (89, 89)),
    (200, 2, (100, 200)), (195, 2, (145, 145)), (190, 1, (160, 250)),
    (182, 1, (220, 220)),
    (178, 3, (180, 350)), (165, 2, (220, 380)), (150, 3, (150, 300)),
    (140, 4, (200, 420)), (130, 2, (250, 380)), (120, 3, (180, 320)),
    (110, 2, (160, 290)), (105, 3, (200, 350)), (100, 4, (220, 400)),
    (97, 2, (190, 310)), (95, 2, (210, 210)), (93, 4, (130, 130)),
    (92, 3, (180, 320)), (91, 2, (240, 390)), (90, 3, (190, 350)),
    (88, 1, (890, 890)),
    (85, 4, (300, 520)), (80, 5, (380, 680)), (75, 3, (250, 450)),
    (70, 6, (420, 750)), (65, 4, (320, 560)), (60, 5, (390, 690)),
    (55, 7, (480, 850)), (50, 5, (350, 620)), (47, 4, (280, 490)),
    (45, 6, (320, 320)), (42, 5, (360, 640)), (40, 8, (550, 980)),
    (38, 6, (410, 730)), (35, 5, (340, 600)), (33, 7, (480, 860)),
    (30, 5, (750, 750)), (28, 6, (430, 760)), (25, 9, (620, 1100)),
    (22, 7, (490, 870)), (20, 6, (380, 680)), (18, 5, (310, 560)),
    (16, 8, (540, 960)), (14, 8, (480, 480)), (12, 10, (720, 1280)),
    (10, 9, (640, 1130)), (8, 11, (780, 1390)), (7, 12, (1840, 1840)),
    (6, 7, (490, 870)), (5, 8, (560, 990)), (4, 6, (420, 750)),
    (3, 9, (640, 1130)), (2, 14, (980, 1740)), (1, 11, (760, 1350)),
]

FIRST_NAMES = [
    "Maria", "Anna", "Katarzyna", "Malgorzata", "Agnieszka", "Barbara",
    "Ewa", "Krystyna", "Zofia", "Elzbieta", "Joanna", "Monika",
    "Magdalena", "Karolina", "Aleksandra", "Natalia", "Jan", "Piotr",
    "Krzysztof", "Andrzej", "Tomasz", "Marek", "Marcin", "Michal",
    "Robert", "Lukasz", "Grzegorz", "Adam", "Mateusz", "Jakub", "Kamil",
    "Bartosz", "Pawel", "Rafal", "Dariusz", "Wojciech",
]

LAST_NAMES = [
    "Kowalski", "Nowak", "Wisniewski", "Wojcik", "Kowalczyk", "Kaminski",
    "Lewandowski", "Zielinski", "Szymanski", "Wozniak", "Dabrowska",
    "Kozlowski", "Jankowski", "Mazur", "Kwiatkowski", "Krawczyk",
    "Piotrowska", "Grabowska", "Nowakowska", "Pawlak", "Michalska",
    "Adamczyk", "Dudek", "Zajac", "Wieczorek", "Kubiak", "Zawadzki",
    "Krol", "Majewski", "Olszewski", "Jaworska", "Pietrzak", "Wysocka",
]


def amount_for(profile_index, order_index, spend_range):
    low, high = spend_range
    if low == high:
        return float(low)
    span = high - low
    # Deterministic pseudo-random-like amount without importing random state.
    raw = (profile_index * 37 + order_index * 19 + 11) % 101
    return round(low + (span * raw / 100.0), 2)


def risk_tier(days_since_last, frequency, lifetime_value, median_ltv):
    recency = "high" if days_since_last > 180 else "medium" if days_since_last > 90 else "low"
    frequency_tier = "high" if frequency <= 1 else "medium" if frequency <= 4 else "low"
    rank = {"low": 0, "medium": 1, "high": 2}
    tier = max([recency, frequency_tier], key=lambda t: rank[t])
    if median_ltv <= 0:
        return tier
    below_median = lifetime_value < median_ltv
    if tier == "high":
        return "high" if below_median else "medium"
    if tier == "low":
        return "medium" if below_median else "low"
    return "medium"


def risk_score_for(tier, days_since_last, frequency):
    base = {"high": 0.82, "medium": 0.58, "low": 0.25}[tier]
    recency_adj = min(days_since_last / 365.0, 1.0) * 0.08
    freq_adj = -min(frequency, 12) * 0.006
    return round(max(0.02, min(0.98, base + recency_adj + freq_adj)), 4)


def treatment_for(row, median_ltv):
    if row["lifetime_value"] >= median_ltv * 1.4 and row["frequency"] >= 3:
        return "vip_personal_offer"
    if row["days_since_last_order"] >= 150 or row["risk_tier"] == "high":
        return "winback_15"
    return "nudge_10"


def current_app_uplift(row, treatment_key, median_ltv):
    recency_component = min(max(row["days_since_last_order"] / 240.0, 0.0), 1.0) * 0.08
    frequency_component = 0.045 if row["frequency"] <= 1 else 0.025
    risk_component = row["risk_score"] * 0.075
    value_component = 0.025 if row["lifetime_value"] >= median_ltv else 0.01
    treatment_component = {
        "winback_15": 0.035,
        "vip_personal_offer": 0.03,
        "nudge_10": 0.02,
    }[treatment_key]
    return round(min(max(recency_component + frequency_component + risk_component + value_component + treatment_component, 0.02), 0.32), 4)


def build_dataset():
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    EXPORT_DIR.mkdir(parents=True, exist_ok=True)
    customers = []
    orders = []

    for idx, (days_since_last, order_count, spend_range) in enumerate(CUSTOMER_PROFILES):
        customer_id = str(10001 + idx)
        name = f"{FIRST_NAMES[idx % len(FIRST_NAMES)]} {LAST_NAMES[(idx * 3) % len(LAST_NAMES)]}"
        email = f"{name.lower().replace(' ', '.')}{idx + 11}@example.com"
        amounts = [amount_for(idx, j, spend_range) for j in range(order_count)]
        ltv = round(sum(amounts), 2)
        last_order_date = AS_OF_DATE - timedelta(days=days_since_last)
        for j, amount in enumerate(amounts):
            ordered_at = last_order_date - timedelta(days=(order_count - 1 - j) * (28 + (idx + j) % 35))
            orders.append({
                "shopify_order_id": f"{customer_id}_{j + 1}",
                "shopify_customer_id": customer_id,
                "amount": amount,
                "currency": "EUR",
                "status": "paid",
                "ordered_at": ordered_at.strftime("%Y-%m-%d"),
            })
        customers.append({
            "shopify_customer_id": customer_id,
            "name": name,
            "email": email,
            "lifetime_value": ltv,
            "days_since_last_order": days_since_last,
            "frequency": order_count,
            "aov": round(ltv / order_count, 2),
        })

    sorted_ltv = sorted(c["lifetime_value"] for c in customers)
    n = len(sorted_ltv)
    median_ltv = (sorted_ltv[n // 2 - 1] + sorted_ltv[n // 2]) / 2 if n % 2 == 0 else sorted_ltv[n // 2]

    actions = []
    for c in customers:
        c["risk_tier"] = risk_tier(c["days_since_last_order"], c["frequency"], c["lifetime_value"], median_ltv)
        c["risk_score"] = risk_score_for(c["risk_tier"], c["days_since_last_order"], c["frequency"])
        if c["risk_tier"] not in ("high", "medium"):
            continue
        treatment_key = treatment_for(c, median_ltv)
        uplift = current_app_uplift(c, treatment_key, median_ltv)
        cost_rate = {"winback_15": 0.15, "nudge_10": 0.10, "vip_personal_offer": 0.12}[treatment_key]
        expected = round(uplift * c["aov"] * (1 - cost_rate), 2)
        if expected < 10:
            continue
        actions.append({
            "shopify_customer_id": c["shopify_customer_id"],
            "treatment_key": treatment_key,
            "risk_tier": c["risk_tier"],
            "uplift_score": uplift,
            "expected_incremental_revenue": expected,
            "revenue_at_risk": round(max(expected, c["lifetime_value"] * 0.25), 2),
            "proposed_discount": {"winback_15": "15%", "nudge_10": "10%", "vip_personal_offer": "12%"}[treatment_key],
            "model_version": "uplift-v3-demo-baseline",
            "holdout": False,
            "outcome_window_days": 30,
        })

    write_csv(DATA_DIR / "churnguard_synthetic_customers.csv", customers)
    write_csv(DATA_DIR / "churnguard_synthetic_orders.csv", orders)
    write_csv(DATA_DIR / "churnguard_uplift_v3_demo_actions.csv", actions)
    return customers, orders, actions, median_ltv


def write_csv(path, rows):
    if not rows:
        return
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def markdown(source):
    return {"cell_type": "markdown", "metadata": {}, "source": source.strip().splitlines(True)}


def code(source):
    return {
        "cell_type": "code",
        "execution_count": None,
        "metadata": {},
        "outputs": [],
        "source": source.strip().splitlines(True),
    }


def build_notebook(customers, orders, actions, median_ltv):
    current_customers_path = DATA_DIR / "current_app_customers.csv"
    current_orders_path = DATA_DIR / "current_app_orders.csv"
    current_actions_path = DATA_DIR / "current_app_actions.csv"
    if current_customers_path.exists() and current_orders_path.exists() and current_actions_path.exists():
        shown_customers = sum(1 for _ in current_customers_path.open(encoding="utf-8")) - 1
        shown_orders = sum(1 for _ in current_orders_path.open(encoding="utf-8")) - 1
        shown_actions = sum(1 for _ in current_actions_path.open(encoding="utf-8")) - 1
        dataset_note = "The notebook loads live-exported `current_app_*.csv` files by default."
    else:
        shown_customers = len(customers)
        shown_orders = len(orders)
        shown_actions = len(actions)
        dataset_note = "The notebook loads reproducible synthetic fallback CSV files by default."

    cells = [
        markdown(f"""
# ChurnGuard Uplift V3 — Jupyter Notebook

Semi-synthetic uplift modeling experiment on the current ChurnGuard application dataset.

**Current application dataset:** `script/demo_prepare.rb` loads `db/seeds/synthetic_shop.rb` for the default shop `{SHOPIFY_DOMAIN}` and then runs `ScoringEngine` + `UpliftDecisionEngine`.

This notebook uses the same dataset shape:

- `{shown_customers}` Shopify-style customers
- `{shown_orders}` paid orders in EUR
- `{shown_actions}` current application actions / exported demo actions
- customer-level RFM/churn features: recency, frequency, lifetime value, AOV, risk tier, risk score
- action-level fields: `treatment_key`, `uplift_score`, `expected_incremental_revenue`, `revenue_at_risk`, `outcome_window_days`

Important: the app currently has a **demo-ready uplift decision layer**, not a production-trained uplift model. Real production uplift needs randomized treatment/control assignment and observed outcomes. This notebook creates a **semi-synthetic treatment/control experiment** so the methodology can be shown and tested.

{dataset_note}
"""),
        code("""
from pathlib import Path
import math
import numpy as np
import pandas as pd

DATA_DIR = Path("data")
EXPORT_DIR = Path("exports")
EXPORT_DIR.mkdir(exist_ok=True)

current_customers_path = DATA_DIR / "current_app_customers.csv"
current_orders_path = DATA_DIR / "current_app_orders.csv"
current_actions_path = DATA_DIR / "current_app_actions.csv"

if current_customers_path.exists() and current_orders_path.exists() and current_actions_path.exists():
    dataset_source = "current Rails app export"
    customers = pd.read_csv(current_customers_path)
    orders = pd.read_csv(current_orders_path)
    app_actions = pd.read_csv(current_actions_path)
else:
    dataset_source = "reproducible synthetic fallback"
    customers = pd.read_csv(DATA_DIR / "churnguard_synthetic_customers.csv")
    orders = pd.read_csv(DATA_DIR / "churnguard_synthetic_orders.csv")
    app_actions = pd.read_csv(DATA_DIR / "churnguard_uplift_v3_demo_actions.csv")

fallback_scores = {"high": 0.82, "medium": 0.58, "low": 0.25}
customers["risk_score"] = customers.apply(
    lambda r: fallback_scores.get(str(r.get("risk_tier", "low")), 0.25)
    if pd.isna(r.get("risk_score")) else float(r.get("risk_score")),
    axis=1,
)

print("dataset_source:", dataset_source)
print(customers.shape, orders.shape, app_actions.shape)
display(customers.head())
display(app_actions.head())
"""),
        markdown("""
## 1. What dataset is this?

The Rails application demo uses `script/demo_prepare.rb`.

That script:

1. loads `db/seeds/synthetic_shop.rb` for `warsawstyle.myshopify.com`;
2. creates a realistic Polish Shopify-style fashion store;
3. creates customers and paid orders;
4. runs `ScoringEngine` to assign RFM risk tiers;
5. runs `UpliftDecisionEngine` to create pending retention actions.

The dataset is not a production customer dataset. It is a deterministic synthetic showroom dataset for demos, tests and diploma explanation.
"""),
        code("""
summary = pd.DataFrame({
    "metric": [
        "customers",
        "orders",
        "demo uplift actions",
        "total LTV",
        "median LTV",
        "avg orders/customer",
    ],
    "value": [
        len(customers),
        len(orders),
        len(app_actions),
        round(customers["lifetime_value"].sum(), 2),
        round(customers["lifetime_value"].median(), 2),
        round(customers["frequency"].mean(), 2),
    ],
})
display(summary)
display(customers["risk_tier"].value_counts().rename_axis("risk_tier").reset_index(name="customers"))
display(app_actions["treatment_key"].value_counts().rename_axis("treatment").reset_index(name="actions"))
"""),
        markdown("""
## 2. Recreate the current app decision layer

The current application uses `UpliftDecisionEngine` as a deterministic demo decision layer. It estimates:

- best treatment;
- uplift score;
- expected incremental revenue;
- approval-card fields.

This is useful for product demo and diploma defense, but it is not yet trained from randomized experimental data.
"""),
        code("""
def app_treatment_for(row, median_ltv):
    if row["lifetime_value"] >= median_ltv * 1.4 and row["frequency"] >= 3:
        return "vip_personal_offer"
    if row["days_since_last_order"] >= 150 or row["risk_tier"] == "high":
        return "winback_15"
    return "nudge_10"

def app_uplift_score(row, treatment_key, median_ltv):
    recency_component = min(max(row["days_since_last_order"] / 240.0, 0.0), 1.0) * 0.08
    frequency_component = 0.045 if row["frequency"] <= 1 else 0.025
    risk_component = row["risk_score"] * 0.075
    value_component = 0.025 if row["lifetime_value"] >= median_ltv else 0.01
    treatment_component = {
        "winback_15": 0.035,
        "vip_personal_offer": 0.03,
        "nudge_10": 0.02,
    }[treatment_key]
    return round(min(max(recency_component + frequency_component + risk_component + value_component + treatment_component, 0.02), 0.32), 4)

def expected_incremental_revenue(row, uplift, treatment_key):
    cost_rate = {"winback_15": 0.15, "nudge_10": 0.10, "vip_personal_offer": 0.12}[treatment_key]
    return round(uplift * row["aov"] * (1 - cost_rate), 2)

median_ltv = customers["lifetime_value"].median()
eligible = customers[customers["risk_tier"].isin(["high", "medium"])].copy()
eligible["app_treatment_key"] = eligible.apply(lambda r: app_treatment_for(r, median_ltv), axis=1)
eligible["app_uplift_score"] = eligible.apply(lambda r: app_uplift_score(r, r["app_treatment_key"], median_ltv), axis=1)
eligible["app_expected_incremental_revenue"] = eligible.apply(
    lambda r: expected_incremental_revenue(r, r["app_uplift_score"], r["app_treatment_key"]),
    axis=1,
)
eligible = eligible[eligible["app_expected_incremental_revenue"] >= 10].copy()

display(eligible[[
    "shopify_customer_id", "name", "risk_tier", "days_since_last_order", "frequency",
    "lifetime_value", "app_treatment_key", "app_uplift_score", "app_expected_incremental_revenue"
]].head(10))
print("Eligible demo approval actions:", len(eligible))
"""),
        markdown("""
## 3. Build a semi-synthetic treatment/control experiment

Because the current app dataset has no real randomized treatment/control outcomes, we simulate an experiment:

- `treatment = 1`: customer receives the app-recommended retention action;
- `treatment = 0`: customer is held out;
- `outcome = 1`: customer makes a repeat purchase in the next 30 days.

The simulation intentionally uses the app features, but adds randomness. This lets us train and evaluate uplift models while keeping the honest limitation clear.
"""),
        code("""
rng = np.random.default_rng(20260928)
df = customers.copy()
df["recommended_treatment"] = df.apply(lambda r: app_treatment_for(r, median_ltv), axis=1)
df["true_uplift"] = df.apply(lambda r: app_uplift_score(r, r["recommended_treatment"], median_ltv), axis=1)

# Baseline purchase probability without treatment.
df["base_purchase_prob"] = (
    0.36
    - 0.0009 * df["days_since_last_order"]
    + 0.018 * np.log1p(df["frequency"])
    + 0.000025 * df["lifetime_value"]
    - 0.10 * (df["risk_tier"] == "high").astype(float)
)
df["base_purchase_prob"] = df["base_purchase_prob"].clip(0.03, 0.65)

# Randomized holdout. In production this must be assigned and logged by the app.
df["treatment"] = rng.binomial(1, 0.55, size=len(df))
df["outcome_prob"] = (df["base_purchase_prob"] + df["treatment"] * df["true_uplift"]).clip(0.01, 0.95)
df["repeat_purchase_30d"] = rng.binomial(1, df["outcome_prob"])
df["simulated_revenue_30d"] = np.where(
    df["repeat_purchase_30d"] == 1,
    np.maximum(df["aov"], 25),
    0.0,
)

display(df[[
    "shopify_customer_id", "risk_tier", "recommended_treatment", "treatment",
    "base_purchase_prob", "true_uplift", "outcome_prob", "repeat_purchase_30d"
]].head(12))
display(pd.crosstab(df["treatment"], df["repeat_purchase_30d"], margins=True))
"""),
        markdown("""
## 4. Prepare model features

For an uplift model, the same customer features are used in both treatment and control groups.

We include:

- recency;
- frequency;
- lifetime value;
- AOV;
- risk score;
- risk tier one-hot flags.
"""),
        code("""
feature_cols = [
    "days_since_last_order",
    "frequency",
    "lifetime_value",
    "aov",
    "risk_score",
]
X_base = df[feature_cols].astype(float).copy()
for tier in ["high", "medium", "low"]:
    X_base[f"risk_{tier}"] = (df["risk_tier"] == tier).astype(float)

def standardize(frame):
    mu = frame.mean()
    sigma = frame.std(ddof=0).replace(0, 1)
    return (frame - mu) / sigma, mu, sigma

X_std, X_mu, X_sigma = standardize(X_base)
y = df["repeat_purchase_30d"].astype(float).values
t = df["treatment"].astype(float).values

print(X_std.shape)
display(X_std.head())
"""),
        markdown("""
## 5. Minimal logistic regression in NumPy

This notebook avoids hidden library magic. The logistic regression below is enough for a small teaching/demo dataset.
"""),
        code("""
def sigmoid(z):
    return 1 / (1 + np.exp(-np.clip(z, -40, 40)))

def fit_logistic(X, y, lr=0.08, epochs=4000, l2=0.01):
    X = np.asarray(X, dtype=float)
    y = np.asarray(y, dtype=float)
    X_design = np.c_[np.ones(len(X)), X]
    w = np.zeros(X_design.shape[1])
    for _ in range(epochs):
        p = sigmoid(X_design @ w)
        grad = (X_design.T @ (p - y)) / len(y)
        grad[1:] += l2 * w[1:]
        w -= lr * grad
    return w

def predict_logistic(w, X):
    X = np.asarray(X, dtype=float)
    X_design = np.c_[np.ones(len(X)), X]
    return sigmoid(X_design @ w)
"""),
        markdown("""
## 6. S-Learner

S-Learner trains one outcome model with treatment included as a feature.

To estimate uplift:

1. predict outcome if `treatment=1`;
2. predict outcome if `treatment=0`;
3. subtract the two predictions.
"""),
        code("""
X_s = X_std.copy()
X_s["treatment"] = t
for col in X_std.columns:
    X_s[f"{col}_x_treatment"] = X_std[col] * t

w_s = fit_logistic(X_s.values, y, lr=0.06, epochs=5000, l2=0.02)

X_s_t1 = X_std.copy()
X_s_t1["treatment"] = 1.0
for col in X_std.columns:
    X_s_t1[f"{col}_x_treatment"] = X_std[col] * 1.0

X_s_t0 = X_std.copy()
X_s_t0["treatment"] = 0.0
for col in X_std.columns:
    X_s_t0[f"{col}_x_treatment"] = 0.0

df["s_learner_p_treat"] = predict_logistic(w_s, X_s_t1.values)
df["s_learner_p_control"] = predict_logistic(w_s, X_s_t0.values)
df["s_learner_uplift"] = df["s_learner_p_treat"] - df["s_learner_p_control"]
display(df[["shopify_customer_id", "risk_tier", "true_uplift", "s_learner_uplift"]].head())
"""),
        markdown("""
## 7. T-Learner

T-Learner trains two separate outcome models:

- one model on treated customers;
- one model on control customers.

Uplift is the difference between both predictions.
"""),
        code("""
treated_mask = t == 1
control_mask = t == 0

w_treat = fit_logistic(X_std.loc[treated_mask].values, y[treated_mask], lr=0.06, epochs=5000, l2=0.02)
w_control = fit_logistic(X_std.loc[control_mask].values, y[control_mask], lr=0.06, epochs=5000, l2=0.02)

df["t_learner_p_treat"] = predict_logistic(w_treat, X_std.values)
df["t_learner_p_control"] = predict_logistic(w_control, X_std.values)
df["t_learner_uplift"] = df["t_learner_p_treat"] - df["t_learner_p_control"]

display(df[["shopify_customer_id", "risk_tier", "true_uplift", "t_learner_uplift"]].head())
"""),
        markdown("""
## 8. Uplift evaluation: Qini, AUUC, Lift@K

For production, the most important metric is real incremental revenue in treatment vs holdout. Offline, uplift models are commonly evaluated with uplift curves, Qini-style cumulative gain and Lift@K.
"""),
        code("""
def uplift_curve(frame, score_col, outcome_col="repeat_purchase_30d", treatment_col="treatment"):
    ranked = frame.sort_values(score_col, ascending=False).reset_index(drop=True).copy()
    ranked["treated"] = ranked[treatment_col] == 1
    ranked["control"] = ranked[treatment_col] == 0
    ranked["treated_outcome"] = ranked[outcome_col] * ranked["treated"]
    ranked["control_outcome"] = ranked[outcome_col] * ranked["control"]
    ranked["cum_treated"] = ranked["treated"].cumsum().replace(0, np.nan)
    ranked["cum_control"] = ranked["control"].cumsum().replace(0, np.nan)
    ranked["cum_treated_outcome"] = ranked["treated_outcome"].cumsum()
    ranked["cum_control_outcome"] = ranked["control_outcome"].cumsum()
    ranked["uplift_gain"] = (
        ranked["cum_treated_outcome"]
        - ranked["cum_treated"] * ranked["cum_control_outcome"] / ranked["cum_control"]
    ).fillna(0)
    ranked["population_fraction"] = (np.arange(len(ranked)) + 1) / len(ranked)
    return ranked

def auuc(curve):
    return float(np.trapz(curve["uplift_gain"], curve["population_fraction"]))

def lift_at_k(frame, score_col, k=0.3):
    n = max(1, int(len(frame) * k))
    top = frame.sort_values(score_col, ascending=False).head(n)
    treat = top[top["treatment"] == 1]
    control = top[top["treatment"] == 0]
    if len(treat) == 0 or len(control) == 0:
        return np.nan
    return treat["repeat_purchase_30d"].mean() - control["repeat_purchase_30d"].mean()

metrics = []
for name, col in [
    ("Current app demo score", "true_uplift"),
    ("S-Learner", "s_learner_uplift"),
    ("T-Learner", "t_learner_uplift"),
]:
    curve = uplift_curve(df, col)
    metrics.append({
        "model": name,
        "AUUC": round(auuc(curve), 4),
        "Qini_final_gain": round(float(curve["uplift_gain"].iloc[-1]), 4),
        "Lift@30%": round(float(lift_at_k(df, col, 0.30)), 4),
    })

metrics_df = pd.DataFrame(metrics)
display(metrics_df)
"""),
        markdown("""
## 9. Export predictions for ChurnGuard approval queue

The app does not need to show every model detail. It needs fields that map to approval cards:

- customer;
- best action;
- uplift score;
- expected incremental revenue;
- holdout flag;
- outcome window.
"""),
        code("""
pred = df.copy()
pred["model_uplift_score"] = pred["t_learner_uplift"].clip(0, 1)
pred["treatment_key"] = pred["recommended_treatment"]
pred["expected_incremental_revenue"] = pred.apply(
    lambda r: expected_incremental_revenue(
        {
            "aov": r["aov"],
        },
        r["model_uplift_score"],
        r["treatment_key"],
    ),
    axis=1,
)
pred["holdout"] = pred["treatment"] == 0
pred["outcome_window_days"] = 30

export_cols = [
    "shopify_customer_id",
    "name",
    "risk_tier",
    "risk_score",
    "treatment_key",
    "model_uplift_score",
    "expected_incremental_revenue",
    "holdout",
    "outcome_window_days",
]
export = pred[export_cols].sort_values("expected_incremental_revenue", ascending=False)
export_path = EXPORT_DIR / "uplift_v3_predictions_for_churnguard.csv"
export.to_csv(export_path, index=False)
print(export_path)
display(export.head(12))
"""),
        markdown("""
## 10. What to say on defense

Use this wording:

> The current application dataset is a deterministic synthetic Shopify-style dataset generated by `db/seeds/synthetic_shop.rb` and prepared by `script/demo_prepare.rb`. It contains customers, orders, RFM risk tiers and Uplift V3 demo actions. It is enough to demonstrate the product workflow and decision layer.

> For a production uplift model, this dataset is not enough because it does not contain randomized treatment/control outcomes. Therefore, the notebook creates a semi-synthetic uplift experiment on top of the current dataset and shows how S-Learner/T-Learner, AUUC, Qini and Lift@K would work. The production roadmap is to collect real holdout/outcome data from Shopify/Klaviyo pilots.
"""),
    ]

    notebook = {
        "cells": cells,
        "metadata": {
            "kernelspec": {
                "display_name": "Python 3",
                "language": "python",
                "name": "python3",
            },
            "language_info": {
                "name": "python",
                "pygments_lexer": "ipython3",
            },
        },
        "nbformat": 4,
        "nbformat_minor": 5,
    }
    NOTEBOOK_PATH.write_text(json.dumps(notebook, ensure_ascii=False, indent=2), encoding="utf-8")


def build_readme(customers, orders, actions):
    live_note = ""
    current_customers_path = DATA_DIR / "current_app_customers.csv"
    current_orders_path = DATA_DIR / "current_app_orders.csv"
    current_actions_path = DATA_DIR / "current_app_actions.csv"
    if current_customers_path.exists() and current_orders_path.exists() and current_actions_path.exists():
        live_customers = sum(1 for _ in current_customers_path.open(encoding="utf-8")) - 1
        live_orders = sum(1 for _ in current_orders_path.open(encoding="utf-8")) - 1
        live_actions = sum(1 for _ in current_actions_path.open(encoding="utf-8")) - 1
        live_note = f"""

Live Rails export currently present:

- `data/current_app_customers.csv` — {live_customers} customers
- `data/current_app_orders.csv` — {live_orders} orders
- `data/current_app_actions.csv` — {live_actions} actions

The notebook loads these live-export files first. If they are absent, it falls back to the reproducible synthetic CSV files.
"""

    README_PATH.write_text(f"""# ChurnGuard Uplift V3 Notebook

This folder contains a complete Jupyter notebook for explaining and testing the ChurnGuard Uplift V3 approach.

## What dataset is used by the app now?

The current local application demo uses:

- `script/demo_prepare.rb`
- default shop: `{SHOPIFY_DOMAIN}`
- underlying seed: `db/seeds/synthetic_shop.rb`
- scoring: `ScoringEngine`
- uplift decision layer: `UpliftDecisionEngine`

The generated dataset is a synthetic Shopify-style fashion store:

- customers: {len(customers)}
- paid orders: {len(orders)}
- current Uplift V3 demo actions: {len(actions)}
- currency: EUR
- fields: customer id, name, email, LTV, recency, frequency, AOV, risk tier, risk score, treatment key, uplift score, expected incremental revenue.
{live_note}

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
""", encoding="utf-8")


def main():
    customers, orders, actions, median_ltv = build_dataset()
    build_notebook(customers, orders, actions, median_ltv)
    build_readme(customers, orders, actions)
    print(NOTEBOOK_PATH)
    print(README_PATH)
    print(DATA_DIR / "churnguard_synthetic_customers.csv")
    print(DATA_DIR / "churnguard_synthetic_orders.csv")
    print(DATA_DIR / "churnguard_uplift_v3_demo_actions.csv")


if __name__ == "__main__":
    main()
