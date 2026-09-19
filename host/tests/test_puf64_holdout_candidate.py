import importlib.util
import io
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


FREEZE = load("puf64_freeze_holdout_candidate")
HOLD = load("puf64_holdout_eval")

BOARD = "ZYNQ-A01"
RO = 64
PAIRS = 2016
BITSTREAM = "e" * 64


def canonical(index):
    a = 0
    while index >= RO - 1 - a:
        index -= RO - 1 - a
        a += 1
    return a, a + 1 + index


def base_golden():
    return {
        "board_id": BOARD, "protocol": "3.1", "build_id": 2,
        "image_mode_code": 1, "topology_id": 0xC0DE, "record_bytes": 20,
        "width": 16, "ref_cycles": 1023, "num_ro": RO, "pair_count": PAIRS,
        "bitstream_sha256": BITSTREAM, "route_fingerprint_sha256": "f" * 64,
        "train_eligible": True, "holdout_eligible": True,
        "holdout_candidate_selection_sha256": "s" * 64,
        "holdout_candidate_mapping_file_sha256": "m" * 64,
    }


def base_mapping():
    return {
        "status": "TRAIN_SELECTED_NOT_HOLDOUT_QUALIFIED", "mapping_tag": 0,
        "selection_sha256": "s" * 64, "train_input_sha256": "t" * 64,
        "pairs": [list(canonical(i)) for i in range(264)],
        "source_pair_indices": list(range(264)),
        "ro_degree": [8] * RO,
        "algorithm": "puf64-train-select-v1",
        "config": {"min_boots": 20, "select_count": 264},
        "limitations": ["single device"],
        "train_boots": list(range(101, 121)),
    }


class FreezeHoldoutCandidateTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name)
        self.golden = self.root / "golden.json"
        golden = base_golden()
        golden["holdout_eligible"] = False  # freeze happens before closure
        self.golden.write_text(json.dumps(golden))
        self.mapping = self.root / "mapping.json"
        self.mapping.write_text(json.dumps(base_mapping()))
        self.reference = self.root / "reference.json"
        self.reference.write_text(json.dumps({"selection_sha256": "s" * 64}))
        self.report = self.root / "report.json"
        self.report.write_text(json.dumps({"selection_sha256": "s" * 64}))
        self.train_input = self.root / "train_input.json"
        self.train_input.write_text(json.dumps({
            "aggregate_sha256": "t" * 64, "bitstream_sha256": BITSTREAM}))
        self.out = self.root / "holdout_candidate_private.json"
        self.argv = [
            "--mapping", str(self.mapping), "--reference", str(self.reference),
            "--selection-report", str(self.report),
            "--train-input", str(self.train_input),
            "--golden-manifest", str(self.golden), "--out", str(self.out),
        ]

    def test_freeze_then_verify_is_immutable(self):
        self.assertEqual(FREEZE.main(self.argv), 0)
        payload = json.loads(self.out.read_text())
        self.assertEqual(payload["selection_sha256"], "s" * 64)
        self.assertEqual(len(payload["ordered_pairs"]), 264)
        original = self.out.read_text()
        self.assertEqual(FREEZE.main(self.argv), 0)  # verify pass
        self.assertEqual(self.out.read_text(), original)

    def test_freeze_refuses_changed_mapping(self):
        self.assertEqual(FREEZE.main(self.argv), 0)
        original = self.out.read_text()
        changed = base_mapping()
        changed["selection_sha256"] = "x" * 64
        self.mapping.write_text(json.dumps(changed))
        self.reference.write_text(json.dumps({"selection_sha256": "x" * 64}))
        self.report.write_text(json.dumps({"selection_sha256": "x" * 64}))
        self.assertEqual(FREEZE.main(self.argv), 2)
        self.assertEqual(self.out.read_text(), original)  # not overwritten

    def test_freeze_rejects_holdout_already_open(self):
        golden = base_golden()
        golden["holdout_eligible"] = True
        self.golden.write_text(json.dumps(golden))
        self.assertEqual(FREEZE.main(self.argv), 2)

    def test_verify_after_closure_is_immutable(self):
        self.assertEqual(FREEZE.main(self.argv), 0)
        original = self.out.read_text()
        golden = json.loads(self.golden.read_text())
        golden["holdout_eligible"] = True
        self.golden.write_text(json.dumps(golden))
        self.assertEqual(FREEZE.main(self.argv), 0)
        self.assertEqual(self.out.read_text(), original)


class CandidateBindingTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name)
        self.mapping = self.root / "mapping.json"
        self.mapping.write_text(json.dumps(base_mapping()))
        self.reference = self.root / "reference.json"
        self.reference.write_text(json.dumps({"selection_sha256": "s" * 64}))
        golden = base_golden()
        golden["holdout_candidate_mapping_file_sha256"] = HOLD.sha256_file(
            self.mapping)
        self.golden = golden
        self.candidate = {
            "schema": "puf64-holdout-candidate-v1",
            "status": "TRAIN_SELECTED_NOT_HOLDOUT_QUALIFIED", "mapping_tag": 0,
            "selection_sha256": "s" * 64,
            "mapping_file_sha256": HOLD.sha256_file(self.mapping),
            "reference_file_sha256": HOLD.sha256_file(self.reference),
            "train_input_aggregate_sha256": "t" * 64,
            "ordered_pairs": base_mapping()["pairs"],
            "ro_degree": base_mapping()["ro_degree"],
            "board_id": BOARD, "protocol": "3.1", "build_id": 2,
            "topology_id": 0xC0DE, "record_bytes": 20, "width": 16,
            "ref_cycles": 1023, "num_ro": RO, "pair_count": PAIRS,
            "bitstream_sha256": BITSTREAM,
        }

    def verify(self, candidate):
        return HOLD.verify_candidate_binding(
            base_mapping(), {"selection_sha256": "s" * 64}, candidate,
            self.golden, str(self.mapping), str(self.reference))

    def test_valid_candidate_accepted(self):
        self.assertEqual(self.verify(self.candidate), [])

    def test_tampered_reference_hash_rejected(self):
        candidate = dict(self.candidate)
        candidate["reference_file_sha256"] = "0" * 64
        self.assertTrue(self.verify(candidate))

    def test_tampered_train_input_rejected(self):
        candidate = dict(self.candidate)
        candidate["train_input_aggregate_sha256"] = "0" * 64
        self.assertTrue(self.verify(candidate))

    def test_golden_selection_mirror_rejected(self):
        self.golden["holdout_candidate_selection_sha256"] = "0" * 64
        self.assertTrue(self.verify(self.candidate))


class EvaluatorNoAutoTagTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name)

    def build(self):
        golden = base_golden()
        mapping = base_mapping()
        mapping.pop("train_boots", None)
        mapping_file = self.root / "mapping.json"
        mapping_file.write_text(json.dumps(mapping))
        reference_file = self.root / "reference.json"
        reference_file.write_text(json.dumps({
            "selection_sha256": "s" * 64,
            "reference_bit": {str(i): 0 for i in range(264)}}))
        golden["holdout_candidate_mapping_file_sha256"] = HOLD.sha256_file(
            mapping_file)
        golden_file = self.root / "golden.json"
        golden_file.write_text(json.dumps(golden))
        candidate_file = self.root / "candidate.json"
        candidate_file.write_text(json.dumps({
            "schema": "puf64-holdout-candidate-v1",
            "status": "TRAIN_SELECTED_NOT_HOLDOUT_QUALIFIED", "mapping_tag": 0,
            "selection_sha256": "s" * 64,
            "mapping_file_sha256": HOLD.sha256_file(mapping_file),
            "reference_file_sha256": HOLD.sha256_file(reference_file),
            "train_input_aggregate_sha256": "t" * 64,
            "ordered_pairs": mapping["pairs"],
            "ro_degree": mapping["ro_degree"],
            "board_id": BOARD, "protocol": "3.1", "build_id": 2,
            "topology_id": 0xC0DE, "record_bytes": 20, "width": 16,
            "ref_cycles": 1023, "num_ro": RO, "pair_count": PAIRS,
            "bitstream_sha256": BITSTREAM,
        }))
        device = {
            "protocol": "3.1", "build_id": 2, "topology_id": 0xC0DE,
            "record_bytes": 20, "width": 16, "ref_cycles": 1023,
            "num_ro": RO, "pair_count": PAIRS,
            "system_clock_hz": 100000000, "input_clock_hz": 50000000,
            "mmcm_locked": 1, "image_mode_code": 1,
        }
        per_pair = [
            {"index": i, "pair": list(canonical(i)), "consensus_winner": 0,
             "minority_count": 0, "minority_rate_percent": 0.0,
             "tie_count": 0, "margin": {"p01": 64.0, "p05": 70.0, "p50": 72.0},
             "count0": {"p50": 1000}, "count1": {"p50": 1000}}
            for i in range(PAIRS)
        ]
        for boot in range(201, 211):
            dataset = self.root / f"holdout_{BOARD}_{boot}.dataset.json"
            dataset.write_text(json.dumps({"per_pair": per_pair}))
            raw = self.root / f"holdout_{BOARD}_{boot}.raw.json"
            raw.write_text(json.dumps({"frames_winners_hex": ["00"] * 50}))
            manifest = {
                "campaign": "holdout", "board_id": BOARD, "build_id": 2,
                "status": "VALID", "boot_index": boot,
                "frames_requested": 50,
                "local_bitstream_sha256": BITSTREAM,
                "device_info": device, "dataset_path": str(dataset),
            }
            (self.root / f"holdout_{BOARD}_{boot}.session.json").write_text(
                json.dumps(manifest))
        return golden_file, mapping_file, reference_file, candidate_file

    def test_pass_reports_without_mapping_tag(self):
        golden_file, mapping_file, reference_file, candidate_file = self.build()
        report = self.root / "holdout_report.json"
        frozen = self.root / "frozen_mapping.json"
        rc = HOLD.main([
            "--mapping", str(mapping_file), "--reference", str(reference_file),
            "--holdout-dir", str(self.root), "--golden-manifest",
            str(golden_file), "--holdout-candidate", str(candidate_file),
            "--report-out", str(report), "--frozen-out", str(frozen)])
        self.assertEqual(rc, 0)
        data = json.loads(report.read_text())
        self.assertTrue(data["passed"])
        self.assertEqual(data["mapping_tag"], 0)
        self.assertEqual(data["frames_observed"], 500)
        self.assertEqual(data["independent_boots"], 10)
        self.assertFalse(frozen.exists())  # no automatic tag

    def test_tampered_reference_fails_closed(self):
        golden_file, mapping_file, reference_file, candidate_file = self.build()
        reference = json.loads(reference_file.read_text())
        reference["reference_bit"]["0"] = 1
        reference_file.write_text(json.dumps(reference))
        rc = HOLD.main([
            "--mapping", str(mapping_file), "--reference", str(reference_file),
            "--holdout-dir", str(self.root), "--golden-manifest",
            str(golden_file), "--holdout-candidate", str(candidate_file),
            "--report-out", str(self.root / "r.json")])
        self.assertEqual(rc, 2)


if __name__ == "__main__":
    unittest.main()
