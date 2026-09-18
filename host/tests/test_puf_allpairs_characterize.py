import importlib.util
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest import mock

MODULE_PATH = Path(__file__).parents[1] / "puf_allpairs_characterize.py"
SPEC = importlib.util.spec_from_file_location("puf_allpairs_characterize", MODULE_PATH)
PUF = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PUF)
canonical_pairs = PUF.canonical_pairs
EXPECTED_PAIRS = canonical_pairs(32)
PAIR_COUNT = PUF.PAIR_COUNT
analyze = PUF.analyze
read_margin = PUF.read_margin


class FakePort:
    def __init__(self, payload):
        self.payload = bytearray(payload)
        self.writes = []

    def write(self, data):
        self.writes.append(data)

    def read(self, length):
        data = self.payload[:length]
        del self.payload[:length]
        return bytes(data)


def make_frame(sample=0, weak_pair=None, ro_count=32):
    frame = []
    for index, (a, b) in enumerate(canonical_pairs(ro_count)):
        count0 = 1000 + index
        margin = 2 if (a, b) == weak_pair else 64 + (index % 31)
        count1 = count0 + margin + sample % 2
        frame.append((a, b, 1, 0, count0, count1, count1 - count0))
    return frame


class AllPairsMetricsTest(unittest.TestCase):
    def test_schedule_is_complete_and_unique(self):
        self.assertEqual(len(EXPECTED_PAIRS), PAIR_COUNT)
        self.assertEqual(len(set(EXPECTED_PAIRS)), PAIR_COUNT)
        self.assertEqual(EXPECTED_PAIRS[0], (0, 1))
        self.assertEqual(EXPECTED_PAIRS[-1], (30, 31))

    def test_wire_parser_checks_pair_schedule(self):
        payload = bytearray([0xAA])
        for index, (a, b) in enumerate(EXPECTED_PAIRS):
            count0 = 100 + index
            count1 = count0 + 9
            flags = b | (1 << 5)
            payload.extend(struct.pack("<HBBIII", index, a, flags,
                                       count0, count1, 9))
        port = FakePort(payload)
        records = read_margin(port, 32, 496)
        self.assertEqual(len(records), PAIR_COUNT)
        self.assertEqual(records[0][:2], (0, 1))
        self.assertEqual(records[-1][:2], (30, 31))

    def test_wire_parser_rejects_noncanonical_pair(self):
        payload = bytearray([0xAA])
        for index, (a, b) in enumerate(EXPECTED_PAIRS):
            if index == 12:
                a, b = b, a
            payload.extend(struct.pack("<HBBIII", index, a, b | (1 << 5),
                                       100, 109, 9))
        with self.assertRaises(RuntimeError):
            read_margin(FakePort(payload), 32, 496)

    def test_balanced_preview_reaches_264(self):
        result = analyze(
            [make_frame(0), make_frame(1), make_frame(2)],
            thresholds=[4, 32, 128], max_minority_rate=1.0,
            selection_threshold=4, max_ro_degree=17,
        )
        preview = result["selection_preview"]
        self.assertTrue(preview["complete"])
        self.assertEqual(preview["selected_count"], 264)
        self.assertLessEqual(max(preview["ro_degree"]), 17)
        self.assertGreaterEqual(min(preview["ro_degree"]), 16)

    def test_threshold_rejects_weak_pair(self):
        result = analyze(
            [make_frame(weak_pair=(0, 1)) for _ in range(5)],
            thresholds=[0, 4], max_minority_rate=1.0,
        )
        self.assertEqual(result["threshold_sweep"][0]["accepted_pair_count"], 496)
        self.assertEqual(result["threshold_sweep"][1]["accepted_pair_count"], 495)

    def cli_args(self, *extra):
        with tempfile.NamedTemporaryFile() as bitstream:
            base = [
                "puf_allpairs_characterize.py",
                "--port", "/dev/fake",
                "--count", "1",
                "--bitstream", bitstream.name,
                "--report", "/tmp/report.json",
                "--board-id", "ZYNQ-A01",
                "--boot-index", "3",
                "--condition-id", "room-coldboot-003",
                "--fingerprint-file", "/tmp/no-such-fingerprint.tsv",
            ]
            return base + list(extra)

    def test_missing_boot_index_is_rejected(self):
        argv = self.cli_args()
        argv.remove("--boot-index")
        argv.remove("3")
        with self.assertRaises(SystemExit):
            with mock.patch.object(sys, "argv", argv):
                PUF.main()

    def test_zero_boot_index_is_rejected(self):
        argv = ["0" if arg == "3" else arg for arg in self.cli_args()]
        with self.assertRaises(SystemExit):
            with mock.patch.object(sys, "argv", argv):
                PUF.main()

    def test_missing_fingerprint_file_is_rejected(self):
        with self.assertRaises(SystemExit):
            with mock.patch.object(sys, "argv", self.cli_args()):
                PUF.main()

    def test_analyze_attaches_order_assessment(self):
        result = analyze(
            [make_frame(0), make_frame(1)], thresholds=[4], max_minority_rate=1.0,
        )
        assessment = result["assessment"]
        self.assertIn("order_cycle_rate_percent", assessment)
        self.assertIn("entropy_ceiling_bits", assessment)
        self.assertAlmostEqual(assessment["entropy_ceiling_bits"], 117.66, delta=0.01)
        self.assertFalse(assessment["above_128bit_target"])

    def test_consistent_ordering_has_zero_cycles(self):
        # rank[i] = i => higher index is faster.  winner bit = 1 whenever the
        # second RO of the pair is faster, giving one coherent total order.
        frames = []
        for _ in range(5):
            frame = []
            for index, (a, b) in enumerate(EXPECTED_PAIRS):
                winner = 1  # b faster (b > a)
                count0 = 1000 + index
                count1 = count0 + 100 + index % 31 + (1 if winner else 0)
                frame.append((a, b, winner, 0, count0, count1, abs(count0 - count1)))
            frames.append(frame)
        assessment = PUF.assess_order_structure(frames)
        self.assertEqual(
            assessment["order_cycle_rate_percent"]["mean"], 0.0
        )
        self.assertEqual(
            assessment["order_cycle_rate_percent"]["zero_cycle_sample_rate_percent"],
            100.0,
        )

    def test_cyclic_ordering_is_detected(self):
        # Build a tournament with one directed 3-cycle (0>1>2>0) on an
        # otherwise ordered pair field, then emit the canonical pair records.
        faster = [[0] * PUF.RO_COUNT for _ in range(PUF.RO_COUNT)]
        for a in range(PUF.RO_COUNT):
            for b in range(PUF.RO_COUNT):
                if a != b:
                    faster[a][b] = 1 if a > b else 0
        faster[0][1] = 1  # 0 > 1
        faster[1][2] = 1  # 1 > 2 (2 > 0 already true) => 0>1>2>0 cycle
        faster[1][0] = 0
        frame = []
        for index, (a, b) in enumerate(EXPECTED_PAIRS):
            winner = 0 if faster[a][b] else 1
            count0 = 1000 + index
            count1 = count0 + 100 + (1 if winner else 0)
            frame.append((a, b, winner, 0, count0, count1, abs(count0 - count1)))
        assessment = PUF.assess_order_structure([frame])
        self.assertGreater(assessment["order_cycle_rate_percent"]["mean"], 0.0)
        self.assertLess(
            assessment["order_cycle_rate_percent"]["zero_cycle_sample_rate_percent"],
            100.0,
        )

    def test_puf64_schedule_is_complete_and_unique(self):
        pairs = canonical_pairs(64)
        self.assertEqual(len(pairs), 2016)
        self.assertEqual(len(set(pairs)), 2016)
        self.assertEqual(pairs[0], (0, 1))
        self.assertEqual(pairs[-1], (62, 63))
        for a, b in pairs:
            self.assertLess(a, b)
            self.assertLess(b, 64)

    def test_puf64_pair_field_decode_includes_high_bit(self):
        self.assertEqual(PUF.decode_pair_fields(0x00, (1 << 7) | (1 << 5) | 31, 64),
                         (0, 63, 1, 0))
        self.assertEqual(PUF.decode_pair_fields(0x3F, (1 << 5) | 1, 64),
                         (63, 1, 1, 0))
        self.assertEqual(PUF.decode_pair_fields(0x1E, (1 << 5) | 5, 32),
                         (30, 5, 1, 0))
        with self.assertRaises(RuntimeError):
            PUF.decode_pair_fields(0x40, 0, 64)
        with self.assertRaises(RuntimeError):
            PUF.decode_pair_fields(0x20, 0, 32)

    def test_puf64_wire_parser_frame(self):
        payload = bytearray([0xAA])
        for index, (a, b) in enumerate(canonical_pairs(64)):
            margin = 11 + (index % 7)
            flags = ((b >> 5) & 1) << 7 | (1 << 5) | (b & 0x1F)
            payload.extend(struct.pack("<HBBIII", index, a, flags,
                                       2000 + index, 2000 + index + margin, margin))
        records = read_margin(FakePort(payload), 64, 2016)
        self.assertEqual(len(records), 2016)
        self.assertEqual(records[0][:2], (0, 1))
        self.assertEqual(records[-1][:2], (62, 63))

    def test_puf64_wire_parser_rejects_reserved_pair_a_bits(self):
        payload = bytearray([0xAA])
        for index, (a, b) in enumerate(canonical_pairs(64)):
            if index == 5:
                a |= 0x40
            payload.extend(struct.pack("<HBBIII", index, a, (1 << 5) | b,
                                       100, 109, 9))
        with self.assertRaises(RuntimeError):
            read_margin(FakePort(payload), 64, 2016)

    def test_expected_info_bytes_match_rtl(self):
        self.assertEqual(PUF.expected_info_bytes(32, 496),
                         b"PUF\x02\x00\x07")
        self.assertEqual(PUF.expected_info_bytes(64, 2016),
                         bytes([0x50, 0x55, 0x46, 0x03, 64, 0xE0, 0x07, 0x07]))

    def test_probe_image_detects_both_variants(self):
        legacy = FakePort(b"PUF\x02\x00\x07")
        self.assertEqual(PUF.probe_image(legacy)[:2], (32, 496))
        puf64 = FakePort(b"PUF\x03\x40\xE0\x07\x07")
        self.assertEqual(PUF.probe_image(puf64)[:2], (64, 2016))
        bad = FakePort(b"PUF\xFF\x00")
        with self.assertRaises(RuntimeError):
            PUF.probe_image(bad)

    def test_puf64_analysis_ceiling_passes_128_bit(self):
        result = analyze(
            [make_frame(0, ro_count=64), make_frame(1, ro_count=64)],
            thresholds=[4], max_minority_rate=1.0, ro_count=64, pair_count=2016,
        )
        self.assertEqual(result["ro_count"], 64)
        self.assertEqual(result["pair_count"], 2016)
        self.assertEqual(len(result["per_pair"]), 2016)
        self.assertGreater(result["assessment"]["entropy_ceiling_bits"], 128.0)
        self.assertTrue(result["assessment"]["above_128bit_target"])
        self.assertLessEqual(max(result["selection_preview"]["ro_degree"]), 17)


if __name__ == "__main__":
    unittest.main()
