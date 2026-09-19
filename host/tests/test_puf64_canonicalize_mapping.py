import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

HOST = Path(__file__).parents[1]


def load(name):
    spec = importlib.util.spec_from_file_location(name, HOST / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


CANON = load("puf64_canonicalize_mapping")


def canonical_pair(index):
    a = 0
    while index >= 64 - 1 - a:
        index -= 64 - 1 - a
        a += 1
    return [a, a + 1 + index]


def fixtures(tmp):
    golden = {
        "board_id": "ZYNQ-A01", "part": "xc7z020clg400-2", "protocol": "3.1",
        "build_id": 2, "topology_id": 49374,
        "topology_id_semantics": "family only",
        "measurement_architecture_tuple": ["protocol=3.1", "build_id=2"],
        "num_ro": 64, "pair_count": 2016, "width": 16,
        "ripple_stages_per_ro": 17, "clock_input_hz": 50000000,
        "clock_system_hz": 100000000, "ref_cycles": 1023,
        "measurement_window_ns": 10230, "bitstream_sha256": "e" * 64,
        "route_fingerprint_sha256": "f" * 64,
        "lock_level": "placement+LOCK_PINS+route-fingerprint-fail-closed",
        "fixed_route": False, "holdout_eligible": True, "mapping_tag": 0,
    }
    pairs = [canonical_pair(i) for i in range(264)]
    mapping = {
        "pairs": pairs, "source_pair_indices": list(range(264)),
        "ro_degree": [8] * 48 + [9] * 16,
        "selection_sha256": "a" * 64, "train_input_sha256": "t" * 64,
        "config": {"min_boots": 20, "select_count": 264, "degree_high": 9},
        "train_boots": list(range(101, 121)),
    }
    train_input = {"aggregate_sha256": "t" * 64,
                   "boots": [{"boot_index": b} for b in range(101, 121)]}
    holdout_input = {
        "aggregate_sha256": "b" * 64,
        "candidate_selection_sha256": "a" * 64,
        "candidate_mapping_file_sha256": "m" * 64,
        "train_input_aggregate_sha256": "t" * 64,
        "boots": [{"boot_index": b} for b in range(201, 211)],
    }
    report = {
        "passed": True,
        "gate": {"holdout_boots_valid": True, "no_selected_pair_invalid": True,
                 "no_frame_over_bch": True, "no_boot_majority_over_bch": True,
                 "observed_frr_zero": True, "p95_le_4": True},
        "frames_observed": 500, "independent_boots": 10,
        "p50": 0, "p95": 0, "p99": 0, "max": 0,
        "frame_error_histogram": {"errors_0": 500, "errors_1_4": 0,
                                  "errors_5_8": 0, "errors_over_8": 0},
        "frames_over_bch": 0, "boots_majority_over_bch": 0, "observed_frr": 0.0,
        "selected_pair_error_frequency": {"pairs_with_any_error": 0},
        "selected_pairs_with_tie": 0, "selected_pairs_with_minority": 0,
        "selected_margin_p01": {"worst": 5.0, "median": 83.5},
        "selected_margin_p50_median": 84.5,
        "selected_response_balance": {"ones": 152, "zeros": 112,
                                      "selection_criterion": False},
    }
    report_path = Path(tmp) / "holdout_report.json"
    report_path.write_text(json.dumps(report))
    report_sha = hashlib.sha256(report_path.read_bytes()).hexdigest()
    mapping_sha = "m" * 64
    return golden, mapping, train_input, holdout_input, report, mapping_sha, \
        report_sha, report_path


class GoldenVectorTest(unittest.TestCase):
    def test_canonical_serialization_golden_vector(self):
        payload = {"schema": "x", "a": 1, "b": "0x10",
                   "pairs": [[0, 1], [2, 3]], "nested": {"z": 2, "a": [3, 2, 1]}}
        canonical = CANON.canonical_bytes(payload)
        self.assertEqual(
            canonical,
            b'{"a":1,"b":"0x10","nested":{"a":[3,2,1],"z":2},'
            b'"pairs":[[0,1],[2,3]],"schema":"x"}')
        digest, tag = CANON.digest_and_tag(canonical)
        self.assertEqual(
            digest,
            "7aedbead15972d06ee329ccbd33313c31694e610e322e479f41961d642b5dd85")
        self.assertEqual(tag, 0xED7A)
        self.assertNotEqual(tag, 0)


class CanonicalizeTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.tmp = self._tmp.name

    def test_payload_is_reproducible_and_secret_free(self):
        golden, mapping, train_input, holdout_input, report, mapping_sha, \
            report_sha, _ = fixtures(self.tmp)
        p1 = CANON.assemble_payload(golden, mapping, train_input,
                                    holdout_input, report, mapping_sha,
                                    report_sha)
        p2 = CANON.assemble_payload(golden, mapping, train_input,
                                    holdout_input, report, mapping_sha,
                                    report_sha)
        self.assertEqual(CANON.canonical_bytes(p1), CANON.canonical_bytes(p2))
        self.assertEqual(p1["mapping_length"], 264)
        blob = json.dumps(p1)
        for secret in ("reference_bit", "frames_winners_hex", "raw_payload",
                       "helper_secret", "kcv"):
            self.assertNotIn(secret, blob)
        digest, tag = CANON.digest_and_tag(CANON.canonical_bytes(p1))
        self.assertEqual(len(digest), 64)
        self.assertNotEqual(tag, 0)

    def test_public_marks_wire_mapping_len_blocked(self):
        golden, mapping, train_input, holdout_input, report, mapping_sha, \
            report_sha, _ = fixtures(self.tmp)
        payload = CANON.assemble_payload(golden, mapping, train_input,
                                         holdout_input, report, mapping_sha,
                                         report_sha)
        canonical = CANON.canonical_bytes(payload)
        digest, tag = CANON.digest_and_tag(canonical)
        public = CANON.derive_public(canonical, digest, tag)
        self.assertEqual(public["mapping_tag_width_bits"], 16)
        self.assertEqual(public["mapping_tag_byte_order"], "little")
        self.assertEqual(public["wire_encoding"]["mapping_len"]["status"],
                         "BLOCKED")
        self.assertNotEqual(public["mapping_tag"], 0)

    def test_verify_inputs_accepts_and_rejects(self):
        golden, mapping, train_input, holdout_input, report, mapping_sha, \
            report_sha, report_path = fixtures(self.tmp)
        self.assertEqual(CANON.verify_inputs(
            golden, mapping, train_input, holdout_input, report, mapping_sha,
            report_sha, "mapping.json", str(report_path)), [])
        bad = dict(report)
        bad["passed"] = False
        self.assertTrue(CANON.verify_inputs(
            golden, mapping, train_input, holdout_input, bad, mapping_sha,
            report_sha, "mapping.json", str(report_path)))
        bad_golden = dict(golden)
        bad_golden["holdout_eligible"] = False
        self.assertTrue(CANON.verify_inputs(
            bad_golden, mapping, train_input, holdout_input, report, mapping_sha,
            report_sha, "mapping.json", str(report_path)))
        bad_input = dict(holdout_input)
        bad_input["candidate_selection_sha256"] = "0" * 64
        self.assertTrue(CANON.verify_inputs(
            golden, mapping, train_input, bad_input, report, mapping_sha,
            report_sha, "mapping.json", str(report_path)))


if __name__ == "__main__":
    unittest.main()
