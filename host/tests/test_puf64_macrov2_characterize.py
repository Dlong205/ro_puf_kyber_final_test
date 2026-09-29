import importlib.util
import json
import struct
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

HOST = Path(__file__).parents[1]
CHAR_PATH = HOST / "puf64_macrov2_characterize.py"
SPEC = importlib.util.spec_from_file_location("puf64_macrov2_characterize", CHAR_PATH)
PUF = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PUF)

BATCH_PATH = HOST / "puf64_macrov2_batch.py"
BSPEC = importlib.util.spec_from_file_location("puf64_macrov2_batch", BATCH_PATH)
BATCH = importlib.util.module_from_spec(BSPEC)
BSPEC.loader.exec_module(BATCH)

CTX = json.loads((Path(__file__).parents[2] / "reports/puf64_macrov2_campaign" /
                  "v2_context_manifest.json").read_text())
MACRO_BE = CTX["macro_dcp_sha256"]
FP_BE = CTX["fingerprint_sha256"]


class FakePort:
    def __init__(self, payload):
        self.payload = bytearray(payload)
        self.writes = []

    def write(self, data):
        self.writes.append(bytes(data))

    def read(self, length):
        data = self.payload[:length]
        del self.payload[:length]
        return bytes(data)

    def reset_input_buffer(self):
        pass

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False


def v2_info_payload(build=3, minor=2):
    payload = bytearray([
        64,
        0xE0, 0x07, 0x07,
        0x80, 0xF0, 0xFA, 0x02,
        0x00, 0xE1, 0xF5, 0x05,
        0xFF, 0x03,
        0x01,
        0xF6, 0x27,
        0x10,
        0xDE, 0xC0,
        0x01,
        build & 0xFF, (build >> 8) & 0xFF,
        0x03, minor, 0x14,
    ])
    assert len(payload) == 26
    return b"PUF\x03" + bytes(payload)


def info2_payload(macro_be=MACRO_BE, fp_be=FP_BE):
    return bytes.fromhex(macro_be)[::-1] + bytes.fromhex(fp_be)[::-1]


def margin_frame_64():
    out = bytearray(b"\xAA")
    for index, (a, b) in enumerate(PUF.canonical_pairs(64)):
        c0 = 1000 + 7 * a + b
        c1 = c0 + (1 if (a + b) % 2 == 0 else -1)
        winner = 0 if c0 > c1 else 1
        margin = abs(c0 - c1)
        flags = ((b >> 5) & 1) << 7 | (winner << 5) | (b & 0x1F)
        rec = struct.pack("<HBBIII", index, a & 0x3F, flags, c0, c1, margin)
        rec += bytes([0x41, 0x00])
        rec += struct.pack("<H", PUF.crc16_ccitt_false(rec))
        out += rec
    return bytes(out)


class MacroV2HostTest(unittest.TestCase):
    def test_probe_accepts_build3_protocol32(self):
        port = FakePort(v2_info_payload())
        ro, pairs, caps, info = PUF.probe_image(port)
        self.assertEqual((ro, pairs), (64, 2016))
        self.assertEqual(info["build_id"], 3)
        self.assertEqual(info["protocol"], "3.2")
        self.assertEqual(port.writes, [b"\x00"])

    def test_probe_rejects_golden_build2_protocol31(self):
        port = FakePort(v2_info_payload(build=2, minor=1))
        with self.assertRaises(RuntimeError):
            PUF.probe_image(port)

    def test_info2_binding_matches_frozen_manifest(self):
        port = FakePort(info2_payload())
        macro, fp = PUF.read_info2(port)
        self.assertEqual(macro, MACRO_BE)
        self.assertEqual(fp, FP_BE)
        self.assertEqual(port.writes, [b"\x01"])

    def test_info2_short_payload_rejected(self):
        with self.assertRaises(RuntimeError):
            PUF.read_info2(FakePort(b"\x00" * 63))

    def test_collect_end_to_end_two_frames(self):
        stream = v2_info_payload() + info2_payload() + margin_frame_64() + margin_frame_64()
        with mock.patch.object(PUF.serial, "Serial", return_value=FakePort(stream)):
            measurements, elapsed, info = PUF.collect(
                "/dev/fake", 2, 5.0, 64,
                macro_sha=MACRO_BE, fp_sha=FP_BE)
        self.assertEqual(len(measurements), 2)
        self.assertTrue(all(len(f) == 2016 for f in measurements))
        self.assertEqual(info["macro_dcp_sha256"], MACRO_BE)
        self.assertEqual(info["fingerprint_sha256"], FP_BE)
        self.assertEqual(info["build_id"], 3)

    def test_collect_rejects_wrong_macro_sha(self):
        bad = "00" * 31 + "01"
        stream = v2_info_payload() + info2_payload(macro_be=bad)
        with mock.patch.object(PUF.serial, "Serial", return_value=FakePort(stream)):
            with self.assertRaises(RuntimeError):
                PUF.collect("/dev/fake", 1, 5.0, 64,
                            macro_sha=MACRO_BE, fp_sha=FP_BE)

    def test_campaign_refuses_golden_manifest(self):
        camp_path = HOST / "puf64_macrov2_campaign.py"
        argv = ["prog", "--campaign", "train", "--board-id", "ZYNQ-A01",
                "--boot-index", "301", "--port", "/dev/fake",
                "--bitstream", __file__,
                "--context-manifest",
                str(HOST.parent / "constraints/puf_allpairs64_golden_manifest.json"),
                "--frames", "1", "--outdir", "/tmp",
                "--operator-power-cycle"]
        with mock.patch.object(sys, "argv", argv):
            with self.assertRaises(SystemExit):
                import runpy
                runpy.run_path(str(camp_path), run_name="__main__")

    def test_batch_identity_snapshot(self):
        bitstream = (HOST.parent / "build/puf64_macrov2_characterization" /
                     "puf64_macrov2_char_zynq7020.runs/impl_1" /
                     "Puf64_MacroV2_Characterization_Top.bit")
        ctx = str(HOST.parent / "reports/puf64_macrov2_campaign/v2_context_manifest.json")
        snap = BATCH.identity_snapshot(ctx, str(bitstream), "/dev/fake",
                                       "ZYNQ-A01", "train", 3)
        self.assertEqual(snap["macro_dcp_sha256"], MACRO_BE)
        with self.assertRaises(BATCH.BatchError):
            BATCH.identity_snapshot(ctx, str(bitstream), "/dev/fake",
                                    "ZYNQ-A01", "holdout", 3)
        with self.assertRaises(BATCH.BatchError):
            BATCH.identity_snapshot(ctx, __file__, "/dev/fake",
                                    "ZYNQ-A01", "train", 3)

    def test_v2_files_reference_no_golden_bitstream(self):
        for name in ("puf64_macrov2_characterize.py", "puf64_macrov2_campaign.py",
                     "puf64_macrov2_batch.py"):
            text = (HOST / name).read_text(encoding="utf-8")
            self.assertNotIn("e920b4a9", text)
            self.assertNotIn("Puf_AllPairs64_Characterization_Top.bit", text)


if __name__ == "__main__":
    unittest.main()
