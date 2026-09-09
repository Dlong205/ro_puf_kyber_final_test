import importlib.util
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location("summary", Path(__file__).resolve().parents[2]
                                             / "experiments/fpga_split/summarize.py")
s = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(s)


class ResourceParserTests(unittest.TestCase):
    def test_fractional_bram(self):
        data = """| Slice LUTs* | 11100 | 0 | 20800 | 53.37 |
| Slice Registers | 10841 | 0 | 41600 | 26.06 |
| Block RAM Tile | 14.5 | 0 | 50 | 29.00 |
| DSPs | 2 | 0 | 90 | 2.22 |"""
        result = s.resources(data)
        self.assertEqual(result["bram36_tiles"]["used"], 14.5)
        self.assertEqual(result["lut"]["available"], 20800)

    def test_missing_metrics_fail(self):
        with self.assertRaises(ValueError): s.resources("incomplete report")


if __name__ == "__main__": unittest.main()
