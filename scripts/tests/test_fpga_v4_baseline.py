"""Lightweight verifier tests: synthetic public payloads, no Vivado needed."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "baseline", Path(__file__).resolve().parents[1] / "check_fpga_v4_baseline.py")
b = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(b)


class BaselineTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.dest = self.root / "snapshot"
        self.payloads = {"artifacts/test.bit": b"not a real bitstream", "source.tar": b"test archive"}
        self.manifest = {
            "schema_version": 1, "baseline_id": "test",
            "source_commit": "a" * 40, "evidence_commit": "b" * 40,
            "artifacts": [{"path": "artifacts/test.bit", "origin": "build",
                           "source_path": "test.bit", "size": 20,
                           "sha256": b.sha256(self.payloads["artifacts/test.bit"])}],
            "source_archive": {"paths": ["rtl"], "size": 12,
                               "sha256": b.sha256(self.payloads["source.tar"])}}
        self.raw = json.dumps(self.manifest).encode()
        with patch.object(b, "verify_inputs", return_value=self.payloads.copy()):
            b.create_snapshot(self.root, self.dest, self.manifest, self.raw)

    def check(self):
        return b.check_snapshot(self.dest, self.manifest, self.raw)

    def test_valid_without_original_build(self):
        self.assertEqual(self.check(), 3)

    def test_corrupt_byte(self):
        (self.dest / "artifacts/test.bit").write_bytes(b"Not a real bitstream")
        with self.assertRaises(b.BaselineError): self.check()

    def test_missing_file(self):
        (self.dest / "source.tar").unlink()
        with self.assertRaises(b.BaselineError): self.check()

    def test_no_overwrite(self):
        with self.assertRaises(b.BaselineError):
            b.create_snapshot(self.root, self.dest, self.manifest, self.raw)

    def test_extra_file_rejected(self):
        (self.dest / "unlisted.txt").write_text("extra")
        with self.assertRaises(b.BaselineError): self.check()

    def test_symlink_rejected(self):
        target = self.dest / "source.tar"
        target.unlink()
        original = self.root / "outside.tar"
        original.write_bytes(self.payloads["source.tar"])
        target.symlink_to(original)
        with self.assertRaises(b.BaselineError): self.check()

    def test_forged_manifest_not_trusted(self):
        index = self.dest / "snapshot.json"
        obj = json.loads(index.read_text())
        obj["files"][0]["sha256"] = "0" * 64
        index.write_text(json.dumps(obj))
        with self.assertRaises(b.BaselineError): self.check()

    def test_path_traversal(self):
        for name in ("../outside", "/absolute", "a/../b", ""):
            with self.assertRaises(b.BaselineError): b.relative_path(name)


if __name__ == "__main__":
    unittest.main()
