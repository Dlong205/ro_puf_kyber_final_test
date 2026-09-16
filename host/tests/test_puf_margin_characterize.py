import importlib.util
from pathlib import Path
import struct
import unittest


MODULE_PATH = Path(__file__).parents[1] / "puf_margin_characterize.py"
SPEC = importlib.util.spec_from_file_location("puf_margin_characterize", MODULE_PATH)
PUF = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PUF)


class FakePort:
    def __init__(self, data):
        self.data = bytearray(data)
        self.writes = []

    def write(self, data):
        self.writes.append(bytes(data))

    def read(self, length):
        result = self.data[:length]
        del self.data[:length]
        return bytes(result)


def frame_payload(corrupt_margin=False):
    payload = bytearray([PUF.STATUS_SUCCESS])
    for index in range(PUF.RECORD_COUNT):
        count0 = 100 + index
        count1 = 200 + index
        margin = abs(count0 - count1)
        if corrupt_margin and index == 7:
            margin += 1
        payload.extend(
            struct.pack(
                "<HBBIII", index, index % 255, 1, count0, count1, margin
            )
        )
    return payload


def measurement(flipped=None, low_margin=None):
    flipped = set(flipped or [])
    low_margin = set(low_margin or [])
    result = []
    for index in range(PUF.RECORD_COUNT):
        winner = int(index in flipped)
        margin = 1 if index in low_margin else 20
        count0 = 100
        count1 = count0 - margin if winner == 0 else count0 + margin
        result.append((index % 255, winner, 0, count0, count1, margin))
    return result


class MarginMetricsTest(unittest.TestCase):
    def test_wire_records_are_checked(self):
        port = FakePort(frame_payload())
        records = PUF.read_margin(port)
        self.assertEqual(port.writes, [bytes([PUF.CMD_MARGIN])])
        self.assertEqual(len(records), PUF.RECORD_COUNT)
        self.assertEqual(records[7][5], 100)

    def test_corrupt_redundant_margin_is_rejected(self):
        with self.assertRaises(RuntimeError):
            PUF.read_margin(FakePort(frame_payload(corrupt_margin=True)))

    def test_threshold_sweep_and_duplicate_challenges(self):
        frames = [
            measurement(),
            measurement(flipped={3}, low_margin={5}),
            measurement(low_margin={5}),
        ]
        result = PUF.analyze(frames, thresholds=[0, 10], max_minority_rate=40.0)
        self.assertEqual(result["unique_challenge_count"], 255)
        self.assertEqual(len(result["duplicate_challenge_groups"]), 9)
        by_index = result["per_index"]
        self.assertEqual(by_index[3]["minority_count"], 1)
        self.assertEqual(by_index[5]["margin"]["min"], 1)
        self.assertEqual(
            result["threshold_sweep"][1]["accepted_position_count"], 263
        )
        self.assertFalse(result["threshold_sweep"][1]["fe_n264_capacity_met"])


if __name__ == "__main__":
    unittest.main()
