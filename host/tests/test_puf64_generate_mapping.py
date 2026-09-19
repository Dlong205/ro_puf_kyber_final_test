import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

HOST = Path(__file__).parents[1]
ROOT = HOST.parent


def load(name):
    spec = importlib.util.spec_from_file_location(name, HOST / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


GEN = load("puf64_generate_mapping")
GEN_HOST = load("puf64_mapping_generated")
MANIFEST = ROOT / "constraints" / "puf64_final_mapping_manifest.json"


class GenerateMappingTest(unittest.TestCase):
    def test_generated_artifacts_in_sync(self):
        self.assertEqual(GEN.check(str(MANIFEST), str(ROOT)), 0)

    def test_order_and_degree_match_manifest(self):
        manifest = json.loads(MANIFEST.read_text())
        self.assertEqual(list(GEN_HOST.ORDERED_PAIRS),
                         [tuple(pair) for pair in manifest["pairs"]])
        degree = [0] * 64
        for a, b in GEN_HOST.ORDERED_PAIRS:
            degree[a] += 1
            degree[b] += 1
        self.assertEqual(degree, manifest["ro_degree"])
        self.assertEqual(GEN_HOST.MAPPING_TAG, 0xD501)
        self.assertEqual(GEN_HOST.MAPPING_LEN_BITS, 264)
        self.assertEqual(GEN_HOST.MAPPING_LEN_BYTES, 33)

    def test_sorted_lookup_table(self):
        manifest = json.loads(MANIFEST.read_text())
        lookup = GEN.sorted_lookup(manifest)
        self.assertEqual(lookup, [list(entry) for entry in GEN_HOST.SORTED_LOOKUP])
        self.assertEqual(len(lookup), 264)
        self.assertEqual(lookup, sorted(lookup))
        fulls = [full for full, _ in lookup]
        dests = [dest for _, dest in lookup]
        self.assertEqual(len(set(fulls)), 264)
        self.assertEqual(sorted(dests), list(range(264)))
        self.assertTrue(all(0 <= full < 2016 for full in fulls))
        self.assertEqual(GEN.lookup_hash(lookup), GEN_HOST.SORTED_LOOKUP_SHA256)
        self.assertEqual(GEN_HOST.SORTED_LOOKUP_SHA256,
                         "beb1e395bdee5d6a8e87071644aa15f0f5396c3280bfe0334f1a3ce4ef187a09")
        for dest, pair in enumerate(manifest["pairs"]):
            self.assertEqual(GEN.canonical_index(pair),
                             next(f for f, d in lookup if d == dest))
        self.assertEqual(GEN_HOST.ORDERED_PAIRS[-1],
                         tuple(manifest["pairs"][-1]))

    def test_mapping_bit_truth_table(self):
        self.assertEqual(GEN.mapping_bit(10, 11), 1)
        self.assertEqual(GEN.mapping_bit(11, 10), 0)
        self.assertIsNone(GEN.mapping_bit(10, 10))
        self.assertEqual(GEN_HOST.mapping_bit(10, 11), 1)
        self.assertIsNone(GEN_HOST.mapping_bit(7, 7))

    def test_golden_vector_pack(self):
        vector = GEN.golden_vector()
        self.assertEqual(vector["pair_count"], 264)
        self.assertEqual(vector["first_pair"], [0, 1])
        self.assertEqual(vector["last_pair"], [4, 22])
        self.assertEqual(len(vector["packed_hex"]) // 2, 33)
        self.assertEqual(vector["packed_hex"][:2], "55")
        self.assertEqual(vector["packed_hex"][-2:], "55")
        self.assertEqual(
            hashlib.sha256(bytes.fromhex(vector["packed_hex"])).hexdigest(),
            "a9c2ff11008b72cfadcc9ff93d0a86d1e7b0551644c3f0e0b3010975ffc84a99")
        # host generated packer must agree with the generator
        bits = vector["bits"]
        self.assertEqual(GEN_HOST.pack_mapping_bits(bits),
                         bytes.fromhex(vector["packed_hex"]))

    def test_manifest_rejects_tampered_tag(self):
        manifest = json.loads(MANIFEST.read_text())
        manifest["mapping_tag"] = 0x1234
        with tempfile.NamedTemporaryFile("w", suffix=".json") as handle:
            json.dump(manifest, handle)
            handle.flush()
            self.assertIsNone(GEN.load_manifest(handle.name))


if __name__ == "__main__":
    unittest.main()
