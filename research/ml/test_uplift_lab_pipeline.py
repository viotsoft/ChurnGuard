from __future__ import annotations

import unittest
from pathlib import Path
import sys
from tempfile import TemporaryDirectory

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))
from uplift_lab_pipeline import build_features, prepare_orders, segment_for, uplift_metrics


class UpliftLabPipelineTest(unittest.TestCase):
    def test_feature_builder_excludes_post_treatment_orders(self):
        orders = pd.DataFrame(
            {
                "customer_id": ["c1", "c1"],
                "order_id": ["before", "after"],
                "ordered_at": pd.to_datetime(["2025-01-01", "2025-03-01"], utc=True),
                "amount": [40.0, 9_999.0],
            }
        )
        assignments = pd.DataFrame(
            {"customer_id": ["c1"], "assigned_at": pd.to_datetime(["2025-02-01"], utc=True)}
        )

        features, dropped = build_features(orders, assignments)

        self.assertEqual(dropped, 0)
        self.assertEqual(features.loc[0, "frequency"], 1)
        self.assertEqual(features.loc[0, "monetary_value"], 40.0)

    def test_uplift_metric_rewards_correct_ranking(self):
        treatment = np.tile([1, 0], 100)
        outcome = np.concatenate([np.tile([1, 0], 50), np.tile([0, 0], 50)])
        score = np.concatenate([np.ones(100), np.zeros(100)])

        metrics = uplift_metrics(outcome, treatment, score)

        self.assertGreater(metrics["qini"], 0)
        self.assertGreater(metrics["lift_at_30"], 0)

    def test_negative_effect_becomes_do_not_disturb(self):
        segment, action = segment_for(0.55, 0.30)

        self.assertEqual(segment, "do_not_disturb")
        self.assertIn("negative", action)

    def test_invalid_order_error_names_the_csv_row(self):
        with TemporaryDirectory() as directory:
            path = Path(directory) / "orders.csv"
            path.write_text(
                "customer_id,order_id,ordered_at,amount\n"
                "c1,o1,2025-01-01,40\n"
                "c2,o2,not-a-date,75\n",
                encoding="utf-8",
            )

            with self.assertRaisesRegex(ValueError, "CSV rows 3"):
                prepare_orders(
                    path,
                    {
                        "customer_id": "customer_id",
                        "order_id": "order_id",
                        "ordered_at": "ordered_at",
                        "amount": "amount",
                    },
                )


if __name__ == "__main__":
    unittest.main()
