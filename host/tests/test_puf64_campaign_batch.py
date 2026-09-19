import importlib.util
import io
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


BATCH = load("puf64_campaign_batch")
BOARD = "ZYNQ-A01"
CAMPAIGN = "train"


class Clock:
    def __init__(self):
        self.t = 0.0

    def monotonic(self):
        return self.t

    def sleep(self, seconds):
        self.t += seconds


class ScriptedInput:
    def __init__(self, clock, steps):
        self.clock = clock
        self.steps = list(steps)
        self.calls = 0

    def __call__(self):
        self.calls += 1
        step = self.steps.pop(0) if self.steps else 999.0
        self.clock.t += step


def write_valid_session(outdir, boot):
    dataset = Path(outdir) / f"{CAMPAIGN}_{BOARD}_{boot}.dataset.json"
    dataset.write_text(json.dumps({
        "per_pair": [{
            "consensus_winner": boot % 2,
            "tie_count": 0,
            "minority_rate_percent": 0.0,
            "count0": {"p50": 1000},
        }]
    }))
    manifest = {
        "campaign": CAMPAIGN, "board_id": BOARD, "build_id": 2,
        "status": "VALID", "frames_requested": 50, "frames_received": 50,
        "distinct_frame_count": 50, "duplicate_frame_count": 0,
        "count_summary": {"count0": {"min": 900, "p50": 1000, "max": 1100},
                          "count1": {"min": 900, "p50": 1000, "max": 1100}},
        "dataset_path": str(dataset), "warnings": [], "errors": [],
        "session_uuid": f"uuid-{boot}",
    }
    Path(outdir, f"{CAMPAIGN}_{BOARD}_{boot}.session.json").write_text(
        json.dumps(manifest))


class FakeEnv:
    def __init__(self, tmp, start, end, *, resume=False, resume_from=101):
        self.tmp = Path(tmp)
        self.outdir = self.tmp / "campaign"
        self.outdir.mkdir()
        self.bitstream = self.tmp / "golden.bit"
        self.bitstream.write_bytes(b"golden-bitstream")
        self.golden = self.tmp / "golden.json"
        self.write_golden()
        self.config = {
            "board_id": BOARD, "campaign": CAMPAIGN, "build_id": 2,
            "start_boot": start, "end_boot": end, "frames": 50,
            "golden_manifest": str(self.golden), "bitstream": str(self.bitstream),
            "device": "/dev/serial/by-id/fake",
            "outdir": str(self.outdir),
            "power_off_min_seconds": 10.0, "warmup_seconds": 1.0,
            "device_timeout_seconds": 30.0, "resume": resume,
            "resume_from": resume_from, "vivado": "vivado",
            "program_script": "program.tcl",
        }

    def write_golden(self):
        golden = {
            "board_id": BOARD, "build_id": 2, "protocol": "3.1",
            "bitstream_sha256": BATCH.sha256_file(self.bitstream),
            "train_eligible": True, "holdout_eligible": False,
        }
        self.golden.write_text(json.dumps(golden))

    def session(self, boot):
        return Path(self.outdir) / f"{CAMPAIGN}_{BOARD}_{boot}.session.json"


def run(env, *, clock=None, steps=None, exists=None, program=None, acquire=None,
        out=None, **overrides):
    clock = clock or Clock()
    input_fn = ScriptedInput(clock, steps if steps is not None else [11.0] * 40)
    config = dict(env.config)
    config.update(overrides)
    if out is None:
        out = io.StringIO()
    rc = BATCH.run_batch(
        config, input_fn=input_fn, monotonic=clock.monotonic, sleep=clock.sleep,
        exists=(lambda p: True) if exists is None else exists,
        program_fn=program, acquire_fn=acquire, out=out)
    return rc, out, input_fn


def make_program(record, raise_error=False):
    def program(config, snapshot, out):
        record.append(snapshot["build_id"])
        if raise_error:
            raise BATCH.BatchError("program failed")
    return program


def make_acquire(env, record, fail_boots=(), on_boot=None):
    def acquire(config, boot, out):
        record.append(boot)
        if on_boot is not None:
            on_boot(boot)
        if boot in fail_boots:
            path = env.session(boot)
            path.write_text(json.dumps({
                "campaign": CAMPAIGN, "board_id": BOARD, "build_id": 2,
                "status": "INVALID", "errors": ["CRC mismatch"], "dataset_path": ""}))
            return {"status": "INVALID", "boot_index": boot,
                    "manifest": json.loads(path.read_text())}
        write_valid_session(env.outdir, boot)
        return {"status": "VALID", "boot_index": boot,
                "manifest": json.loads(env.session(boot).read_text())}
    return acquire


class BatchRunnerTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)

    def test_resume_starts_at_first_missing(self):
        env = FakeEnv(self._tmp.name, 105, 107, resume=True)
        for boot in range(101, 105):
            write_valid_session(env.outdir, boot)
        acquired, programmed = [], []
        rc, out, _ = run(env, program=make_program(programmed),
                         acquire=make_acquire(env, acquired))
        self.assertEqual(rc, 0, out.getvalue())
        self.assertEqual(acquired, [105, 106, 107])
        self.assertEqual(programmed, [2, 2, 2])

    def test_resume_skips_valid_sessions(self):
        env = FakeEnv(self._tmp.name, 105, 107, resume=True)
        for boot in range(101, 108):
            write_valid_session(env.outdir, boot)
        acquired = []
        rc, out, _ = run(env, program=make_program([]),
                         acquire=make_acquire(env, acquired))
        self.assertEqual(rc, 0, out.getvalue())
        self.assertEqual(acquired, [])

    def test_resume_requires_prior_valid_history(self):
        env = FakeEnv(self._tmp.name, 105, 105, resume=True)
        acquired = []
        rc, out, _ = run(env, program=make_program([]),
                         acquire=make_acquire(env, acquired))
        self.assertEqual(rc, 1)
        self.assertIn("requires a VALID session for boot 101", out.getvalue())
        self.assertEqual(acquired, [])

    def test_invalid_and_superseded_are_not_valid(self):
        env = FakeEnv(self._tmp.name, 105, 105, resume=True)
        for boot in range(101, 105):
            write_valid_session(env.outdir, boot)
        stem = env.session(105)
        Path(str(stem) + ".invalid").write_text("{}")
        Path(str(stem) + ".superseded").write_text("{}")
        acquired = []
        rc, out, _ = run(env, program=make_program([]),
                         acquire=make_acquire(env, acquired))
        self.assertEqual(rc, 0, out.getvalue())
        self.assertEqual(acquired, [105])

    def test_exact_name_invalid_session_blocks_resume(self):
        env = FakeEnv(self._tmp.name, 105, 105, resume=True)
        for boot in range(101, 105):
            write_valid_session(env.outdir, boot)
        env.session(105).write_text(json.dumps({"status": "INVALID"}))
        acquired = []
        rc, out, _ = run(env, program=make_program([]),
                         acquire=make_acquire(env, acquired))
        self.assertEqual(rc, 1)
        self.assertIn("refusing to reuse the index", out.getvalue())
        self.assertEqual(acquired, [])

    def test_duplicate_boot_without_resume_fails(self):
        env = FakeEnv(self._tmp.name, 105, 105)
        write_valid_session(env.outdir, 105)
        acquired, programmed = [], []
        rc, out, _ = run(env, program=make_program(programmed),
                         acquire=make_acquire(env, acquired))
        self.assertEqual(rc, 1)
        self.assertIn("already has a session", out.getvalue())
        self.assertEqual(acquired, [])
        self.assertEqual(programmed, [])

    def test_power_off_too_short_is_rejected(self):
        clock = Clock()
        input_fn = ScriptedInput(clock, [3.0, 9.0])
        out = io.StringIO()
        prompt, confirm = BATCH.confirm_power_cycle(
            105, 10.0, input_fn, clock.monotonic, out)
        self.assertEqual(input_fn.calls, 2)
        self.assertEqual(confirm - prompt, 12.0)
        self.assertIn("chờ thêm", out.getvalue())

    def test_device_reconnect_timeout(self):
        env = FakeEnv(self._tmp.name, 105, 105)
        acquired, programmed = [], []
        rc, out, _ = run(env, exists=lambda p: False,
                         program=make_program(programmed),
                         acquire=make_acquire(env, acquired))
        self.assertEqual(rc, 1)
        self.assertIn("did not reconnect", out.getvalue())
        self.assertEqual(acquired, [])
        self.assertEqual(programmed, [])

    def test_program_failure_stops_batch(self):
        env = FakeEnv(self._tmp.name, 105, 106)
        acquired, programmed = [], []
        rc, out, _ = run(env, program=make_program(programmed, raise_error=True),
                         acquire=make_acquire(env, acquired))
        self.assertEqual(rc, 1)
        self.assertIn("program failed", out.getvalue())
        self.assertEqual(acquired, [])

    def test_acquire_failure_quarantines_and_stops(self):
        env = FakeEnv(self._tmp.name, 105, 106)
        acquired = []
        rc, out, _ = run(env, program=make_program([]),
                         acquire=make_acquire(env, acquired, fail_boots={105}))
        self.assertEqual(rc, 1)
        self.assertEqual(acquired, [105])  # boot 106 never attempted
        self.assertTrue(Path(str(env.session(105)) + ".invalid").is_file())
        self.assertIn("quarantined", out.getvalue())

    def test_start_end_range_drives_every_boot(self):
        env = FakeEnv(self._tmp.name, 105, 107)
        acquired = []
        rc, out, _ = run(env, program=make_program([]),
                         acquire=make_acquire(env, acquired))
        self.assertEqual(rc, 0, out.getvalue())
        self.assertEqual(acquired, [105, 106, 107])

    def test_golden_identity_change_stops_batch(self):
        env = FakeEnv(self._tmp.name, 105, 106)

        def on_boot(boot):
            if boot == 105:
                changed = json.loads(env.golden.read_text())
                changed["bitstream_sha256"] = "0" * 64
                env.golden.write_text(json.dumps(changed))

        acquired = []
        rc, out, _ = run(env, program=make_program([]),
                         acquire=make_acquire(env, acquired, on_boot=on_boot))
        self.assertEqual(rc, 1)
        self.assertIn("identity changed mid-batch", out.getvalue())
        self.assertEqual(acquired, [105])

    def test_invalid_range_is_rejected(self):
        env = FakeEnv(self._tmp.name, 110, 105)
        rc, out, _ = run(env, program=make_program([]),
                         acquire=make_acquire(env, []))
        self.assertEqual(rc, 1)
        self.assertIn("start_boot", out.getvalue())

    def test_never_calls_selector_or_holdout(self):
        source = (HOST / "puf64_campaign_batch.py").read_text()
        self.assertNotIn("puf64_train_select", source)
        self.assertNotIn("puf64_holdout_eval", source)
        self.assertNotIn("puf64_mapping_train", source)


if __name__ == "__main__":
    unittest.main()
