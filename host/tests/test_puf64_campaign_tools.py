import importlib.util
import json
from pathlib import Path
import unittest

HOST = Path(__file__).parents[1]


def load(name):
    spec = importlib.util.spec_from_file_location(name, HOST / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


CAMP = load("puf64_campaign")
SELECT = load("puf64_train_select")
HOLD = load("puf64_holdout_eval")

RO = 64
PAIRS = RO * (RO - 1) // 2
GOLDEN = {
    "board_id": "ZYNQ-A01", "protocol": "3.1", "image_mode": "PUF_CHARACTERIZATION", "image_mode_code": 1,
    "topology_id": 0xC0DE, "build_id": 2, "num_ro": RO, "width": 16,
    "pair_count": PAIRS, "ref_cycles": 1023,
    "system_clock_hz": 100000000, "input_clock_hz": 50000000,
    "bitstream_sha256": "a" * 64, "route_fingerprint_sha256": "b" * 64,
}


def canonical(index):
    a = 0
    while index >= RO - 1 - a:
        index -= RO - 1 - a
        a += 1
    return a, a + 1 + index


def make_frame(margin=64, zero_at=None, dup_at=None, wrap_at=None):
    frame = []
    for index in range(PAIRS):
        a, b = canonical(index)
        c0 = 1000 + index
        c1 = c0 + margin
        if index == zero_at:
            c0 = 0
            c1 = 5
        if index == dup_at and index > 0:
            a, b = canonical(index - 1)
        if index == wrap_at:
            c0 = 60000
            c1 = c0 + margin
        frame.append((a, b, 1, 0, c0, c1, abs(c1 - c0)))
    return frame


def pair_entry(index, winner=0, minority=0.0, tie=0, p01=64.0):
    return {
        "index": index, "pair": list(canonical(index)),
        "consensus_winner": winner, "minority_rate_percent": minority,
        "tie_count": tie,
        "margin": {"p01": p01, "p05": p01 + 8, "p50": p01 + 10},
        "min_margin_p01": p01, "worst_minority_rate": minority,
        "median_margin_p01": p01,
        "count0": {"p50": 1000 + index}, "count1": {"p50": 1000 + index + p01},
    }


def session(boot, entries=None, device=None, frames=50):
    entries = entries if entries is not None else [pair_entry(i) for i in range(PAIRS)]
    dev = dict(GOLDEN)
    dev["mmcm_locked"] = 1
    dev["measurement_window_ns"] = 10230
    if device:
        dev.update(device)
    return {
        "manifest": {"campaign": "train", "board_id": "ZYNQ-A01", "boot_index": boot,
                     "status": "VALID", "dataset_path": "", "frames_requested": frames,
                     "device_info": dev, "parsed_dataset_sha256": f"{boot:064d}",
                     "session_uuid": f"uuid-{boot}"},
        "dataset": {"per_pair": entries},
    }


class CampaignValidationTest(unittest.TestCase):
    def test_valid_frame_passes(self):
        self.assertEqual(CAMP.validate_measurements([make_frame()], 1, GOLDEN), [])

    def test_zero_count_rejected(self):
        errors = CAMP.validate_measurements([make_frame(zero_at=5)], 1, GOLDEN)
        self.assertTrue(any("zero count" in e for e in errors))

    def test_duplicate_pair_rejected(self):
        errors = CAMP.validate_measurements([make_frame(dup_at=5)], 1, GOLDEN)
        self.assertTrue(any("duplicate pair" in e for e in errors))

    def test_wrap_count_rejected(self):
        errors = CAMP.validate_measurements([make_frame(wrap_at=3)], 1, GOLDEN)
        self.assertTrue(any("wrap" in e for e in errors))

    def test_missing_frame_rejected(self):
        errors = CAMP.validate_measurements([], 50, GOLDEN)
        self.assertTrue(any("frames" in e for e in errors))

    def test_device_tuple_mismatch(self):
        dev = dict(GOLDEN)
        dev["mmcm_locked"] = 1
        dev["topology_id"] = 1
        self.assertTrue(CAMP.verify_device_info(dev, GOLDEN))
        dev2 = dict(GOLDEN)
        dev2["mmcm_locked"] = 0
        self.assertTrue(any("MMCM" in e for e in CAMP.verify_device_info(dev2, GOLDEN)))

    def test_wrong_board_id(self):
        self.assertTrue(CAMP.verify_board_id("ZYNQ-A02", GOLDEN))
        self.assertEqual(CAMP.verify_board_id("ZYNQ-A01", GOLDEN), [])

    def test_freshness_duplicate_and_hash(self):
        sessions = [("/tmp/a.session.json", {
            "board_id": "ZYNQ-A01", "campaign": "pilot_build2", "build_id": 2,
            "boot_index": 1, "session_uuid": "u1", "raw_payload_sha256": "deadbeef"})]
        errors, warnings = CAMP.freshness_check(
            sessions, "pilot_build2", "ZYNQ-A01", 2, 1, "u1", "deadbeef")
        self.assertTrue(any("duplicate session key" in e for e in errors))
        self.assertTrue(any("duplicate session UUID" in e for e in errors))
        self.assertTrue(any("raw payload hash" in w for w in warnings))


class TrainSelectTest(unittest.TestCase):
    def metrics(self, sessions):
        return SELECT.build_pair_metrics(sessions, RO, PAIRS)

    def test_eligibility_margin_boundary(self):
        s = [session(b) for b in range(101, 121)]
        m = self.metrics(s)[0]
        self.assertEqual(SELECT.eligibility(m, 20, 10.0, 4.0), [])
        m3 = dict(m); m3["min_margin_p01"] = 3.0
        self.assertIn("margin", SELECT.eligibility(m3, 20, 10.0, 4.0))

    def test_eligibility_minority_and_tie_and_change(self):
        s = [session(b) for b in range(101, 121)]
        m = self.metrics(s)[0]
        bad = dict(m); bad["worst_minority_rate"] = 11.0
        self.assertIn("minority_rate", SELECT.eligibility(bad, 20, 10.0, 4.0))
        tie = dict(m); tie["tie_events"] = 1
        self.assertIn("tie_event", SELECT.eligibility(tie, 20, 10.0, 4.0))
        changed = dict(m); changed["changed_boot_count"] = 1
        self.assertIn("majority_changed", SELECT.eligibility(changed, 20, 10.0, 4.0))
        ind = dict(m); ind["indeterminate"] = True
        self.assertIn("indeterminate_reference", SELECT.eligibility(ind, 20, 10.0, 4.0))

    def test_per_boot_weighting(self):
        entries = []
        for i in range(PAIRS):
            entries.append(pair_entry(i))
        # 19 boots winner 0, 1 boot winner 1 -> majority across boot = 0, changed=1
        sessions = [session(b) for b in range(101, 120)]
        last = [pair_entry(i, winner=1) for i in range(PAIRS)]
        sessions.append(session(120, entries=last))
        m = self.metrics(sessions)[0]
        self.assertEqual(m["reference_bit"], 0)
        self.assertEqual(m["changed_boot_count"], 1)

    def test_selection_degree_and_determinism(self):
        candidates = [pair_entry(i) for i in range(PAIRS)]
        for c in candidates:
            c["min_margin_p01"] = 64.0 - (c["index"] % 7)
        sel1, deg1 = SELECT.select_balanced(candidates, RO, 264, 9)
        sel2, deg2 = SELECT.select_balanced(candidates, RO, 264, 9)
        self.assertEqual([m["index"] for m in sel1], [m["index"] for m in sel2])
        self.assertEqual(len(sel1), 264)
        self.assertEqual(min(deg1), 8)
        self.assertEqual(max(deg1), 9)
        self.assertEqual(sum(1 for d in deg1 if d == 8), 48)
        self.assertEqual(sum(1 for d in deg1 if d == 9), 16)

    def test_selector_ignores_holdout_sessions(self):
        train = session(101)
        hold = session(201)
        hold["manifest"]["campaign"] = "holdout"
        import tempfile, os
        with tempfile.TemporaryDirectory() as tmp:
            for name, sess in (("train_ZYNQ-A01_101", train),
                               ("holdout_ZYNQ-A01_201", hold)):
                p = Path(tmp) / f"{name}.session.json"
                ds = Path(tmp) / f"{name}.dataset.json"
                ds.write_text(json.dumps(sess["dataset"]))
                m = dict(sess["manifest"]); m["dataset_path"] = str(ds)
                p.write_text(json.dumps(m))
            loaded = SELECT.load_train_sessions(tmp)
            self.assertEqual(len(loaded), 1)
            self.assertEqual(loaded[0]["manifest"]["boot_index"], 101)

    def test_selection_ignores_response_sign(self):
        c0 = [pair_entry(i) for i in range(PAIRS)]
        c1 = [pair_entry(i, winner=1) for i in range(PAIRS)]
        s0, _ = SELECT.select_balanced(c0, RO, 264, 9)
        s1, _ = SELECT.select_balanced(c1, RO, 264, 9)
        self.assertEqual([m["index"] for m in s0], [m["index"] for m in s1])


class HoldoutEvalTest(unittest.TestCase):
    def build(self, frame_errors):
        indices = list(range(264))
        ref = [0] * 264
        mapping = {"status": "TRAIN_SELECTED_NOT_HOLDOUT_QUALIFIED",
                   "mapping_tag": 0, "source_pair_indices": indices, "pairs": [],
                   "algorithm": "v1", "selection_sha256": "x",
                   "limitations": []}
        reference = {"reference_bit": {str(i): 0 for i in indices}}
        sessions = []
        for boot, err in enumerate(frame_errors):
            value = 0
            for j in range(err):
                value |= (1 << indices[j])
            frames = [value.to_bytes((PAIRS + 7) // 8, "big").hex()] * 50
            entries = [pair_entry(i) for i in range(PAIRS)]
            raw = {"frames_winners_hex": frames}
            manifest = {"boot_index": 200 + boot, "status": "VALID",
                        "frames_requested": 50, "device_info": dict(GOLDEN),
                        "dataset_path": ""}
            sessions.append((manifest, {"per_pair": entries}, raw))
        return mapping, reference, sessions

    def test_zero_and_within_bch(self):
        mapping, ref, sessions = self.build([0] * 10)
        result = HOLD.evaluate(mapping, ref, sessions, GOLDEN)
        self.assertEqual(result["failing_frames"], 0)
        self.assertEqual(result["boot_majority_errors"], [0] * 10)

    def test_nine_errors_fails_gate(self):
        mapping, ref, sessions = self.build([9] * 10)
        result = HOLD.evaluate(mapping, ref, sessions, GOLDEN)
        self.assertEqual(result["failing_frames"], 500)
        self.assertEqual(result["boot_majority_errors"], [9] * 10)

    def test_four_errors_allowed(self):
        mapping, ref, sessions = self.build([4] * 10)
        result = HOLD.evaluate(mapping, ref, sessions, GOLDEN)
        self.assertEqual(result["failing_frames"], 0)
        self.assertEqual(result["boot_majority_errors"], [4] * 10)

    def test_eight_errors_allowed(self):
        mapping, ref, sessions = self.build([8] * 10)
        result = HOLD.evaluate(mapping, ref, sessions, GOLDEN)
        self.assertEqual(result["failing_frames"], 0)
        self.assertEqual(result["boot_majority_errors"], [8] * 10)

    def test_p95_gate_boundary(self):
        mapping, ref, sessions = self.build([4] * 10)
        result = HOLD.evaluate(mapping, ref, sessions, GOLDEN)
        errs = sorted(result["frame_errors"])
        p95 = errs[max(0, __import__("math").ceil(0.95 * len(errs)) - 1)]
        self.assertEqual(p95, 4)
        self.assertTrue(result["failing_frames"] == 0)
        bad = HOLD.evaluate(*self.build([9] * 10), GOLDEN)
        errs_bad = sorted(bad["frame_errors"])
        p95_bad = errs_bad[max(0, __import__("math").ceil(0.95 * len(errs_bad)) - 1)]
        self.assertGreater(p95_bad, 4)


if __name__ == "__main__":
    unittest.main()
