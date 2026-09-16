import importlib.util
from pathlib import Path
import struct
import unittest

MODULE_PATH = Path(__file__).parents[1] / "puf_allpairs_characterize.py"
SPEC = importlib.util.spec_from_file_location("puf_allpairs_characterize", MODULE_PATH)
PUF = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PUF)
EXPECTED_PAIRS = PUF.EXPECTED_PAIRS
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


def make_frame(sample=0, weak_pair=None):
    frame = []
    for index, (a, b) in enumerate(EXPECTED_PAIRS):
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
        records = read_margin(port)
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
            read_margin(FakePort(payload))

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


if __name__ == "__main__":
    unittest.main()
