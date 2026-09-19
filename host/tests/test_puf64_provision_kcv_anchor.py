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


PROV = load("puf64_provision_kcv_anchor")
VALID_KCV = "01" * 28


class ProvisionKcvAnchorTest(unittest.TestCase):
    def test_emit_and_check(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "edge_kcv_anchor_rom.vh"
            self.assertEqual(PROV.emit(VALID_KCV, out), 0)
            text = out.read_text()
            self.assertIn("EDGE_KCV_ROM_VALID = 1'b1", text)
            self.assertIn("224'h" + VALID_KCV, text)
            self.assertEqual(PROV.check(out), 0)

    def test_rejects_bad_length_and_chars(self):
        for bad in ("00", "", "zz" * 28, "01" * 27, "01" * 29):
            with self.assertRaises(ValueError):
                PROV.parse_kcv(bad)

    def test_template_is_fail_closed(self):
        self.assertIn("EDGE_KCV_ROM_VALID = 1'b0", PROV.TEMPLATE)
        self.assertIn("EDGE_KCV_ROM_REF   = 224'h0", PROV.TEMPLATE)


if __name__ == "__main__":
    unittest.main()
