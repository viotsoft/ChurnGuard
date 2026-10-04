# Golden Fixture Seed Data — ChurnGuard RFM Scoring Regression Tests
#
# These 10 fixed customer profiles map to known expected risk tiers.
# Used in spec/scoring/golden_fixtures_spec.rb to catch regressions when
# RFM threshold constants change. A rule change that moves a fixture tier
# MUST update the spec explicitly (shows in git diff — intentional friction).
#
# Thresholds (from config/scoring.yml):
#   Recency:   last_order_date > 90 days → Medium, > 180 days → High
#   Frequency: 1 order → High, 2–4 → Medium, 5+ → Low
#   Monetary:  below shop median LTV → bump tier up one level
#
# EXPECTED TIERS (DO NOT CHANGE without updating the spec):
#   1. Maria Kowalski      → HIGH   (207 days, 1 order, low LTV)
#   2. Jan Nowak           → HIGH   (195 days, 2 orders, below median)
#   3. Anna Wiśniewska     → HIGH   (182 days, 1 order, avg LTV)
#   4. Piotr Zielinski     → MEDIUM (95 days, 2 orders, avg LTV)
#   5. Karolina Dąbrowska  → MEDIUM (93 days, 4 orders, below median)
#   6. Tomasz Wójcik       → MEDIUM (88 days, 1 order, high LTV) ← monetary saves from HIGH
#   7. Zofia Lewandowska   → LOW    (30 days, 5 orders, high LTV)
#   8. Marek Kaminski       → LOW    (14 days, 8 orders, above median)
#   9. Ewa Kowalczyk       → LOW    (7 days, 12 orders, top LTV)
#  10. Bartosz Szymański    → LOW    (45 days, 6 orders, avg LTV)

GOLDEN_FIXTURES = [
  { name: "Maria Kowalski",     days_since_order: 207, order_count: 1,  total_spent: 89.0,   expected_tier: "high" },
  { name: "Jan Nowak",          days_since_order: 195, order_count: 2,  total_spent: 145.0,  expected_tier: "high" },
  { name: "Anna Wiśniewska",    days_since_order: 182, order_count: 1,  total_spent: 220.0,  expected_tier: "high" },
  { name: "Piotr Zielinski",    days_since_order: 95,  order_count: 2,  total_spent: 210.0,  expected_tier: "medium" },
  { name: "Karolina Dąbrowska", days_since_order: 93,  order_count: 4,  total_spent: 130.0,  expected_tier: "medium" },
  { name: "Tomasz Wójcik",      days_since_order: 88,  order_count: 1,  total_spent: 890.0,  expected_tier: "medium" },
  { name: "Zofia Lewandowska",  days_since_order: 30,  order_count: 5,  total_spent: 750.0,  expected_tier: "low" },
  { name: "Marek Kaminski",     days_since_order: 14,  order_count: 8,  total_spent: 480.0,  expected_tier: "low" },
  { name: "Ewa Kowalczyk",      days_since_order: 7,   order_count: 12, total_spent: 1840.0, expected_tier: "low" },
  { name: "Bartosz Szymański",  days_since_order: 45,  order_count: 6,  total_spent: 320.0,  expected_tier: "low" },
].freeze

# Median LTV across fixtures: ~275.0 (midpoint between 220 and 320)
FIXTURE_MEDIAN_LTV = 275.0
