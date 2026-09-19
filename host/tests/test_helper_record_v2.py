import importlib.util
from pathlib import Path
import sys
import unittest

HOST = Path(__file__).parents[1]
ROOT = HOST.parent
sys.path.insert(0, str(ROOT / "scripts"))


def load_spec():
    spec = importlib.util.spec_from_file_location(
        "helper_record_spec", ROOT / "scripts" / "helper_record_spec.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


SPEC = load_spec()


class HelperRecordV2Test(unittest.TestCase):
    def test_v2_identity_constants(self):
        self.assertEqual(SPEC.RECORD_VERSION, 0x02)
        self.assertEqual(SPEC.PROTOCOL_VERSION, 0x01)
        self.assertEqual(SPEC.DEFAULT_MAPPING_LEN_BYTES, 33)
        self.assertEqual(SPEC.DEFAULT_MAPPING_LEN_BITS, 264)
        self.assertEqual(SPEC.DEFAULT_MAPPING_TAG, 0xD501)
        self.assertEqual(SPEC.OFF_MAPPING_LEN_BYTES, 8)
        self.assertEqual(SPEC.OFF_MAPPING_TAG, 9)

    def test_kat_record_wire_bytes_and_crc(self):
        record = SPEC.TEST_RECORD
        self.assertEqual(len(record), 76)
        self.assertEqual(record[4], 0x02)              # record_version
        self.assertEqual(record[5], 0x01)              # protocol_version
        self.assertEqual(record[8], 33)                # mapping_len_bytes
        self.assertEqual(record[9], 0x01)              # tag lo (LE)
        self.assertEqual(record[10], 0xD5)             # tag hi (LE)
        status, ctx, helper, kcv = SPEC.validate_record(record)
        self.assertEqual(status, SPEC.REC_OK)
        self.assertEqual(ctx, SPEC.TEST_CTX)
        crc_stored = int.from_bytes(record[74:76], "little")
        self.assertEqual(crc_stored, SPEC.crc16_ccitt_false(record[:74]))

    def test_kcv_context_golden_vector_56bit(self):
        # {generation, mapping_tag, fe_param, profile, proto, record_version}
        self.assertEqual(SPEC.TEST_CTX, 0x01D50101010102)
        self.assertEqual(SPEC.kcv_context(), 0x01D50101010102)
        self.assertEqual(SPEC.kcv_context(mapping_tag=0x0000), 0x0001000001010102)
        self.assertEqual(SPEC.kcv_context(record_version=0x01), 0x01D50101010101)

    def test_generated_headers_carry_v2(self):
        rtl = (ROOT / "rtl" / "top" / "helper_record_spec.vh").read_text()
        fw = (ROOT / "firmware" / "helper_record_spec.h").read_text()
        self.assertIn("HREC_RECORD_VERSION   = 8'h02", rtl)
        self.assertIn("HREC_OFF_MAPPING_LEN_BYTES", rtl)
        self.assertIn("#define HREC_RECORD_VERSION   0x02u", fw)
        self.assertIn("#define HREC_OFF_MAPPING_LEN_BYTES", fw)
        self.assertNotIn("HREC_OFF_MAPPING_LEN ", rtl)
        self.assertNotIn("HREC_OFF_MAPPING_LEN ", fw)

    def test_legacy_and_bad_lengths_rejected(self):
        legacy = bytearray(SPEC.TEST_RECORD)
        legacy[4] = 0x01
        crc = SPEC.crc16_ccitt_false(bytes(legacy[:SPEC.OFF_CRC]))
        legacy[74] = crc & 0xFF
        legacy[75] = (crc >> 8) & 0xFF
        self.assertEqual(SPEC.validate_record(bytes(legacy))[0],
                         SPEC.REC_ERR_RECORD_VERSION)
        for bad_len in (0, 32, 34, 255):
            record = SPEC.serialize_record(SPEC.TEST_HELPER, SPEC.TEST_KCV,
                                           mapping_len_bytes=bad_len)
            self.assertEqual(SPEC.validate_record(record)[0],
                             SPEC.REC_ERR_MAPPING)
        for bad_tag in (0x0000, 0x00D5, 0x01D5, 0xFFFF):
            record = SPEC.serialize_record(SPEC.TEST_HELPER, SPEC.TEST_KCV,
                                           mapping_tag=bad_tag)
            self.assertEqual(SPEC.validate_record(record)[0],
                             SPEC.REC_ERR_MAPPING)


if __name__ == "__main__":
    unittest.main()
