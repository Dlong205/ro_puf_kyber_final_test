import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


MODULE_PATH = Path(__file__).parents[1] / "puf_mapping_train.py"
SPEC = importlib.util.spec_from_file_location("puf_mapping_train", MODULE_PATH)
PUF = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PUF)


def campaign(board_id, condition_id="room", weak_indices=None,
             bitstream_hash="a" * 64, winner_offset=0, boot_index=None):
    weak_indices = set(weak_indices or [])
    entries = []
    for index, pair in enumerate(PUF.EXPECTED_PAIRS):
        weak = index in weak_indices
        entries.append({
            "index": index,
            "pair": list(pair),
            "consensus_winner": (index + winner_offset) & 1,
            "minority_rate_percent": 2.0 if weak else 0.0,
            "tie_count": 1 if weak else 0,
            "margin": {"p01": 2 if weak else 64 + index % 31,
                       "p05": 3 if weak else 72 + index % 31},
        })
    metadata = {
        "board_id": board_id,
        "condition_id": condition_id,
        "local_bitstream_sha256": bitstream_hash,
    }
    if boot_index is not None:
        metadata["boot_index"] = boot_index
    return {
        "ro_count": PUF.RO_COUNT,
        "pair_count": PUF.PAIR_COUNT,
        "sample_count": 100,
        "per_pair": entries,
        "campaign": metadata,
    }


def loaded(report, name):
    temp = tempfile.NamedTemporaryFile(mode="w", suffix=f"-{name}.json", delete=False)
    json.dump(report, temp)
    temp.close()
    result = PUF.load_campaign(temp.name)
    Path(temp.name).unlink()
    # Paths only participate in duplicate-input checks.  Give each synthetic
    # campaign a stable unique path after its temporary file is removed.
    result["path"] = Path(f"/{name}.json")
    return result


class MappingTrainingTest(unittest.TestCase):
    def test_release_candidate_requires_disjoint_training_and_holdout(self):
        training = [
            loaded(campaign("train-a", winner_offset=0), "train-a"),
            loaded(campaign("train-b", winner_offset=1), "train-b"),
            loaded(campaign("train-c", winner_offset=0), "train-c"),
        ]
        holdout = [
            loaded(campaign("hold-a", winner_offset=1), "hold-a"),
            loaded(campaign("hold-b", winner_offset=0), "hold-b"),
        ]
        manifest, audit = PUF.build_manifest(training, holdout, "map-1")
        self.assertTrue(manifest["reliability_qualified"])
        self.assertFalse(manifest["puf_freeze_eligible"])
        self.assertEqual(manifest["status"], "reliability-qualified-candidate")
        self.assertEqual(manifest["selected_count"], 264)
        self.assertLessEqual(max(manifest["ro_degree"]), 17)
        self.assertGreaterEqual(min(manifest["ro_degree"]), 16)
        self.assertEqual(audit["holdout_failures"], [])
        self.assertEqual(len(manifest["manifest_sha256"]), 64)

    def test_one_board_output_is_explicitly_provisional(self):
        training = [loaded(campaign("board-only"), "one")]
        manifest, _ = PUF.build_manifest(training, [], "preview")
        self.assertFalse(manifest["reliability_qualified"])
        self.assertEqual(manifest["status"], "provisional")
        self.assertEqual(manifest["evidence"]["training_board_count"], 1)

    def test_holdout_failure_does_not_change_selected_mapping(self):
        training = [
            loaded(campaign("train-a"), "ta"),
            loaded(campaign("train-b", winner_offset=1), "tb"),
            loaded(campaign("train-c"), "tc"),
        ]
        baseline, _ = PUF.build_manifest(
            training,
            [loaded(campaign("hold-good"), "hg")],
            "baseline", min_holdout_boards=1,
        )
        weak = baseline["source_pair_indices"][0]
        failing, audit = PUF.build_manifest(
            training,
            [loaded(campaign("hold-bad", weak_indices={weak}), "hb")],
            "failing", min_holdout_boards=1,
        )
        self.assertEqual(baseline["pairs"], failing["pairs"])
        self.assertFalse(failing["reliability_qualified"])
        self.assertEqual(audit["holdout_failures"][0]["failed_pair_count"], 1)

    def test_rejects_same_board_in_training_and_holdout(self):
        training = [loaded(campaign("same"), "train")]
        holdout = [loaded(campaign("same", condition_id="hot"), "hold")]
        with self.assertRaises(ValueError):
            PUF.build_manifest(training, holdout, "bad")

    def test_rejects_mixed_bitstreams(self):
        training = [loaded(campaign("a"), "a")]
        holdout = [loaded(campaign("b", bitstream_hash="b" * 64), "b")]
        with self.assertRaises(ValueError):
            PUF.build_manifest(training, holdout, "bad")

    def test_manifest_hash_is_deterministic_and_covers_version(self):
        training = [loaded(campaign("only"), "only")]
        first, _ = PUF.build_manifest(training, [], "v1")
        second, _ = PUF.build_manifest(training, [], "v1")
        changed, _ = PUF.build_manifest(training, [], "v2")
        self.assertEqual(first["manifest_sha256"], second["manifest_sha256"])
        self.assertNotEqual(first["manifest_sha256"], changed["manifest_sha256"])

    def make_sessions(self, board, boot_indexes, winner_offset=0):
        return [
            loaded(campaign(board, condition_id=f"boot-{boot}",
                            winner_offset=winner_offset, boot_index=boot),
                   f"{board}-boot-{boot}.json")
            for boot in boot_indexes
        ]

    def test_session_split_single_board_qualifies(self):
        training = self.make_sessions("ZYNQ-A01", range(1, 18))
        holdout = self.make_sessions("ZYNQ-A01", range(18, 27), winner_offset=1)
        manifest, audit = PUF.build_manifest(
            training, holdout, "zq-map-v1",
            session_split=True, min_training_sessions=15,
            min_holdout_sessions=8,
        )
        self.assertEqual(manifest["split_policy"], "session")
        self.assertTrue(manifest["reliability_qualified"])
        self.assertEqual(manifest["status"], "reliability-qualified-candidate")
        self.assertEqual(manifest["evidence"]["training_board_count"], 1)
        self.assertEqual(manifest["evidence"]["training_session_count"], 17)
        self.assertEqual(manifest["evidence"]["holdout_session_count"], 9)
        self.assertEqual(audit["shared_sessions"], [])
        self.assertIn("Single-device session split", manifest["limitations"][-1])

    def test_session_split_rejects_shared_boot_index(self):
        training = self.make_sessions("ZYNQ-A01", [1, 2, 3])
        holdout = self.make_sessions("ZYNQ-A01", [3, 4, 5])
        with self.assertRaises(ValueError):
            PUF.build_manifest(
                training, holdout, "bad",
                session_split=True, min_training_sessions=1,
                min_holdout_sessions=1,
            )

    def test_session_split_requires_numbered_sessions(self):
        training = self.make_sessions("ZYNQ-A01", [1, 2, 3])
        unnamed = loaded(campaign("ZYNQ-A01", boot_index=None), "unnamed")
        with self.assertRaises(ValueError):
            PUF.build_manifest(
                training, [unnamed], "bad",
                session_split=True, min_training_sessions=1,
                min_holdout_sessions=1,
            )

    def test_session_split_requires_identified_board(self):
        training = self.make_sessions("UNSPECIFIED", [1, 2, 3])
        holdout = self.make_sessions("UNSPECIFIED", [4, 5])
        with self.assertRaises(ValueError):
            PUF.build_manifest(
                training, holdout, "bad",
                session_split=True, min_training_sessions=1,
                min_holdout_sessions=1,
            )

    def test_board_split_still_rejects_same_board_even_numbered(self):
        training = self.make_sessions("ZYNQ-A01", [1, 2, 3])
        holdout = self.make_sessions("ZYNQ-A01", [4, 5])
        with self.assertRaises(ValueError):
            PUF.build_manifest(training, holdout, "bad")

    def test_entropy_screening_from_campaign_assessments(self):
        training = self.make_sessions("ZYNQ-A01", [1, 2, 3])
        holdout = self.make_sessions("ZYNQ-A01", [4, 5, 6])
        for campaign in training + holdout:
            campaign["assessment"] = {
                "order_cycle_rate_percent": {"mean": 0.5},
                "entropy_ceiling_bits": 117.66,
            }
        manifest, _ = PUF.build_manifest(
            training, holdout, "map-entropy",
            session_split=True, min_training_sessions=1, min_holdout_sessions=1,
        )
        evidence = manifest["evidence"]
        self.assertTrue(evidence["entropy_screened"])
        self.assertTrue(evidence["order_structure_screened"])
        self.assertEqual(evidence["order_cycle_rate_mean_max_percent"], 0.5)
        self.assertAlmostEqual(evidence["entropy_ceiling_bits"], 117.66)
        self.assertIn("117.7", manifest["limitations"][1])
        self.assertIn("128-bit ML-KEM-512", manifest["limitations"][1])


if __name__ == "__main__":
    unittest.main()
