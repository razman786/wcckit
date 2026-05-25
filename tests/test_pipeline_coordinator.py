import json
import os
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "dockerfiles" / "profiling" / "pipeline" / "bin" / "wcckit_profile_pipeline.sh"
PIPELINE_BIN = ROOT / "dockerfiles" / "profiling" / "pipeline" / "bin"
BCC_BIN = ROOT / "dockerfiles" / "profiling" / "bcc" / "bin"


def env():
    e = os.environ.copy()
    e["PATH"] = f"{PIPELINE_BIN}:{BCC_BIN}:{e.get('PATH', '')}"
    return e


def run_pipeline(args, check=True):
    result = subprocess.run([str(SCRIPT), *args], cwd=ROOT, text=True, capture_output=True, env=env())
    if check and result.returncode != 0:
        raise AssertionError(f"pipeline failed\nstdout={result.stdout}\nstderr={result.stderr}")
    return result


class PipelineCoordinatorTests(unittest.TestCase):
    def setUp(self):
        self.proc = subprocess.Popen(["sleep", "30"])
        time.sleep(0.1)

    def tearDown(self):
        self.proc.terminate()
        try:
            self.proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            self.proc.kill()

    def disabled_args(self, tmpdir, run_id, hardware="none"):
        return [
            "--pid", str(self.proc.pid),
            "--duration", "1",
            "--pipeline", "ci",
            "--language", "python",
            "--run-id", run_id,
            "--out", str(tmpdir),
            "--hardware-counters", hardware,
            "--no-bpf-io",
            "--no-app-stat",
            "--no-app-calls",
            "--no-app-flow-summary",
            "--no-flamegraph",
            "--no-process-memory",
        ]

    def test_disabled_collectors_create_reproducible_run_structure(self):
        with tempfile.TemporaryDirectory() as td:
            run_pipeline(self.disabled_args(td, "coordinator-smoke"))
            run_dir = Path(td) / "coordinator-smoke"
            self.assertTrue((run_dir / "manifest.json").is_file())
            for name in ["events", "metrics", "logs", "profiles", "flamegraphs"]:
                self.assertTrue((run_dir / name).is_dir(), name)
            influx = (run_dir / "metrics" / "influx.lp").read_text()
            self.assertIn("wcckit_run_marker", influx)
            self.assertIn("phase=start", influx)
            self.assertIn("phase=end", influx)
            self.assertIn("tool=hardware-counters", influx)
            manifest = json.loads((run_dir / "manifest.json").read_text())
            self.assertEqual(manifest["hardware_counters"]["selected"], "none")
            self.assertFalse(manifest["collectors"]["bpf_io"])
            self.assertFalse(manifest["collectors"]["process_memory"])

    def test_amd_uprof_absent_records_unavailable_without_failing_run(self):
        if shutil.which("AMDuProfPcm"):
            self.skipTest("AMDuProfPcm is installed on this host; unavailable path is not testable")
        with tempfile.TemporaryDirectory() as td:
            run_pipeline(self.disabled_args(td, "amd-unavailable", hardware="amd-uprof"))
            run_dir = Path(td) / "amd-unavailable"
            text = (run_dir / "metrics" / "influx.lp").read_text()
            self.assertIn("tool=amd-uprof-pcm", text)
            self.assertIn("available=false", text)
            manifest = json.loads((run_dir / "manifest.json").read_text())
            self.assertEqual(manifest["hardware_counters"]["selected"], "amd-uprof")
            self.assertFalse(manifest["hardware_counters"]["amd_uprof_available"])

    def test_invalid_hardware_backend_and_duration_fail_early(self):
        with tempfile.TemporaryDirectory() as td:
            bad_backend = run_pipeline(self.disabled_args(td, "bad-backend", hardware="made-up"), check=False)
            self.assertNotEqual(bad_backend.returncode, 0)
            self.assertIn("unsupported hardware-counter backend", bad_backend.stderr)

            bad_duration_args = self.disabled_args(td, "bad-duration")
            i = bad_duration_args.index("--duration") + 1
            bad_duration_args[i] = "zero"
            bad_duration = run_pipeline(bad_duration_args, check=False)
            self.assertNotEqual(bad_duration.returncode, 0)
            self.assertIn("duration must be a positive integer", bad_duration.stderr)


if __name__ == "__main__":
    unittest.main()
