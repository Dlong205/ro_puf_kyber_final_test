import importlib.util
from pathlib import Path
import unittest


MODULE_PATH = Path(__file__).parents[1] / "puf_raw_characterize.py"
SPEC = importlib.util.spec_from_file_location("puf_raw_characterize", MODULE_PATH)
PUF = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PUF)


class RawMetricsTest(unittest.TestCase):
    def test_bitwise_consensus_can_be_unobserved(self):
        result = PUF.analyze(0, [0b001, 0b010, 0b100])
        self.assertFalse(result["bitwise_consensus_is_observed_response"])
        self.assertEqual(result["unique_raw_responses"], 3)
        self.assertAlmostEqual(result["whole_response_mode_rate_percent"], 100 / 3)

    def test_fixed_enrollment_radius_is_not_posthoc_consensus_radius(self):
        nine_errors = (1 << 9) - 1
        result = PUF.analyze(0, [nine_errors, nine_errors])
        self.assertEqual(
            result["samples_over_bch_t8_vs_enrollment_reference"], 2
        )
        self.assertEqual(
            result["samples_over_bch_t8_vs_bitwise_consensus"], 0
        )

    def test_repeated_challenge_pair_mismatches(self):
        response = 1 << 255
        result = PUF.analyze(0, [response, 0])
        repeated = result["repeated_challenge_pairs"]
        self.assertEqual(repeated["mismatch_counts"][0], 1)
        self.assertEqual(repeated["total_mismatches"], 1)

    def test_stuck_capture_counts(self):
        all_ones = (1 << PUF.RAW_BITS) - 1
        result = PUF.analyze(0, [0, all_ones, 0])
        self.assertEqual(result["all_zero_response_count"], 2)
        self.assertEqual(result["all_one_response_count"], 1)

    def test_empty_sample_set_is_rejected(self):
        with self.assertRaises(ValueError):
            PUF.analyze(0, [])


if __name__ == "__main__":
    unittest.main()
