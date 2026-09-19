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


FREEZE = load("puf64_freeze_train_input")
SELECT = load("puf64_train_select")

BOARD = "ZYNQ-A01"
NUM_RO = 4
PAIR_COUNT = NUM_RO * (NUM_RO - 1) // 2
GOLDEN = {
    "board_id": BOARD, "build_id": 2, "protocol": "3.1",
    "image_mode_code": 1, "topology_id": 0xC0DE, "record_bytes": 20,
    "width": 16, "ref_cycles": 1023, "num_ro": NUM_RO,
    "pair_count": PAIR_COUNT, "clock_system_hz": 100000000,
    "clock_input_hz": 50000000, "bitstream_sha256": "a" * 64,
    "route_fingerprint_sha256": "b" * 64, "train_eligible": True,
    "holdout_eligible": False,
}


def canonical_pairs():
    return [(a, b) for a in range(NUM_RO) for b in range(a + 1, NUM_RO)]


def build_env(tmp, boots, frames=2):
    root = Path(tmp)
    bitstream = root / "golden.bit"
    bitstream.write_bytes(b"golden")
    golden = dict(GOLDEN)
    golden["bitstream_sha256"] = FREEZE.sha256_file(bitstream)
    golden_path = root / "golden.json"
    golden_path.write_text(json.dumps(golden))
    for boot in boots:
        write_session(root, boot, frames, golden)
    return root, bitstream, golden_path, golden


def write_session(root, boot, frames, golden):
    base = root / f"train_{BOARD}_{boot}"
    dataset = Path(str(base) + ".dataset.json")
    dataset.write_text(json.dumps({
        "per_pair": [
            {"index": i, "pair": list(pair), "consensus_winner": 0,
             "minority_count": 0, "minority_rate_percent": 0.0,
             "tie_count": 0, "margin": {"p01": 64.0, "p05": 70.0, "p50": 72.0}}
            for i, pair in enumerate(canonical_pairs())
        ]
    }))
    raw = Path(str(base) + ".raw.json")
    raw.write_text(json.dumps({"frames_winners_hex": ["00"] * frames}))
    device = {
        "protocol": "3.1", "build_id": 2, "topology_id": 0xC0DE,
        "record_bytes": 20, "width": 16, "ref_cycles": 1023,
        "num_ro": NUM_RO, "pair_count": PAIR_COUNT,
        "system_clock_hz": 100000000, "input_clock_hz": 50000000,
        "mmcm_locked": 1, "image_mode_code": 1,
    }
    manifest = {
        "campaign": "train", "board_id": BOARD, "build_id": 2,
        "status": "VALID", "boot_index": boot,
        "session_uuid": f"uuid-{boot}", "frames_received": frames,
        "local_bitstream_sha256": golden["bitstream_sha256"],
        "parsed_dataset_sha256": FREEZE.sha256_file(dataset),
        "device_info": device, "dataset_path": str(dataset),
    }
    Path(str(base) + ".session.json").write_text(json.dumps(manifest))


class FreezeTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)

    def freeze(self, root, golden_path, out, start=1, end=3):
        return FREEZE.freeze(str(root), "train", BOARD, 2, start, end, 2,
                             str(golden_path), str(out))

    def test_freeze_writes_deterministic_aggregate(self):
        root, _, golden_path, _ = build_env(self._tmp.name, [1, 2, 3])
        out1 = Path(self._tmp.name) / "a" / "train_input.json"
        out2 = Path(self._tmp.name) / "b" / "train_input.json"
        self.assertEqual(self.freeze(root, golden_path, out1), 0)
        self.assertEqual(self.freeze(root, golden_path, out2), 0)
        m1 = json.loads(out1.read_text())
        m2 = json.loads(out2.read_text())
        self.assertEqual(m1["aggregate_sha256"], m2["aggregate_sha256"])
        self.assertEqual([e["boot_index"] for e in m1["boots"]], [1, 2, 3])
        self.assertEqual(m1["schema"], "puf64-train-input-v1")

    def test_freeze_rejects_missing_boot(self):
        root, _, golden_path, _ = build_env(self._tmp.name, [1, 3])
        out = Path(self._tmp.name) / "train_input.json"
        self.assertEqual(self.freeze(root, golden_path, out), 2)
        self.assertFalse(out.exists())

    def test_freeze_rejects_bitstream_mismatch(self):
        root, _, golden_path, _ = build_env(self._tmp.name, [1, 2, 3])
        manifest_path = root / f"train_{BOARD}_2.session.json"
        manifest = json.loads(manifest_path.read_text())
        manifest["local_bitstream_sha256"] = "0" * 64
        manifest_path.write_text(json.dumps(manifest))
        out = Path(self._tmp.name) / "train_input.json"
        self.assertEqual(self.freeze(root, golden_path, out), 2)

    def test_freeze_rejects_tampered_dataset(self):
        root, _, golden_path, _ = build_env(self._tmp.name, [1, 2, 3])
        dataset = root / f"train_{BOARD}_1.dataset.json"
        dataset.write_text(dataset.read_text().replace('"p01": 64.0', '"p01": 1.0'))
        out = Path(self._tmp.name) / "train_input.json"
        self.assertEqual(self.freeze(root, golden_path, out), 2)

    def test_freeze_rejects_holdout_eligible(self):
        root, bitstream, golden_path, _ = build_env(self._tmp.name, [1, 2, 3])
        golden = json.loads(golden_path.read_text())
        golden["holdout_eligible"] = True
        golden_path.write_text(json.dumps(golden))
        out = Path(self._tmp.name) / "train_input.json"
        self.assertEqual(self.freeze(root, golden_path, out), 2)


class FrozenLoaderTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)

    def make_frozen(self):
        root, _, golden_path, golden = build_env(self._tmp.name, [1, 2, 3])
        out = Path(self._tmp.name) / "train_input.json"
        self.assertEqual(FREEZE.freeze(str(root), "train", BOARD, 2, 1, 3, 2,
                                       str(golden_path), str(out)), 0)
        return root, golden, golden_path, out

    def test_loader_returns_sessions_and_aggregate(self):
        root, golden, golden_path, out = self.make_frozen()
        sessions, aggregate = SELECT.load_frozen_sessions(
            str(out), golden, str(golden_path))
        self.assertEqual(len(sessions), 3)
        self.assertEqual(aggregate, json.loads(out.read_text())["aggregate_sha256"])
        self.assertEqual(sessions[0]["manifest"]["boot_index"], 1)

    def test_loader_rejects_tampered_dataset(self):
        root, golden, golden_path, out = self.make_frozen()
        dataset = root / f"train_{BOARD}_2.dataset.json"
        dataset.write_text(dataset.read_text() + "\n")
        with self.assertRaises(ValueError):
            SELECT.load_frozen_sessions(str(out), golden, str(golden_path))

    def test_loader_rejects_wrong_aggregate(self):
        root, golden, golden_path, out = self.make_frozen()
        manifest = json.loads(out.read_text())
        manifest["aggregate_sha256"] = "0" * 64
        out.write_text(json.dumps(manifest))
        with self.assertRaises(ValueError):
            SELECT.load_frozen_sessions(str(out), golden, str(golden_path))

    def test_loader_rejects_golden_mismatch(self):
        root, golden, golden_path, out = self.make_frozen()
        golden2 = dict(golden)
        golden2["bitstream_sha256"] = "c" * 64
        with self.assertRaises(ValueError):
            SELECT.load_frozen_sessions(str(out), golden2, str(golden_path))


if __name__ == "__main__":
    unittest.main()
