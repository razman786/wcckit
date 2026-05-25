import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "collect_fixture_from_run.py"


def run_cmd(args, check=True):
    result = subprocess.run(args, cwd=ROOT, text=True, capture_output=True)
    if check and result.returncode != 0:
        raise AssertionError(f"command failed: {args}\nstdout={result.stdout}\nstderr={result.stderr}")
    return result


class FixtureCollectionTests(unittest.TestCase):
    def make_run(self, base: Path) -> Path:
        run = base / "ddfacet-real-001"
        for child in ["logs", "events", "metrics"]:
            (run / child).mkdir(parents=True)
        (run / "manifest.json").write_text('{"run_id":"ddfacet-real-001","hostname":"node01"}\n')
        (run / "logs" / "bpf.log").write_text(
            "host=node01 user=demon ip=10.4.1.102 path=/home/demon/data/ms email=test@example.org\n"
            "TIME COMM PID DISK T SECTOR BYTES LAT(ms)\n"
        )
        (run / "events" / "bpf-io.jsonl").write_text('{"device":"nvme0n1","bytes":4096}\n')
        (run / "metrics" / "bpf-io.lp").write_text('wcckit_bpf_io_summary events_total=1i 1\n')
        return run

    def test_collects_redacted_fixture_set_with_metadata(self):
        with tempfile.TemporaryDirectory() as td:
            td = Path(td)
            run_dir = self.make_run(td)
            out = td / "fixtures"
            result = run_cmd([
                sys.executable,
                str(SCRIPT),
                "--run", str(run_dir),
                "--collector", "bpf-io",
                "--output", str(out),
                "--label", "ci-bpf",
                "--redact-regex", "node01",
            ])
            self.assertIn("wrote 3 fixture file", result.stdout)
            fixture_dir = out / "ci-bpf"
            bpf_log = (fixture_dir / "logs" / "bpf.log").read_text()
            self.assertIn("<IP>", bpf_log)
            self.assertIn("/home/<USER>", bpf_log)
            self.assertIn("<EMAIL>", bpf_log)
            self.assertIn("<REDACTED>", bpf_log)
            self.assertNotIn("10.4.1.102", bpf_log)
            meta = json.loads((fixture_dir / "fixture.meta.json").read_text())
            self.assertEqual(meta["schema"], "wcckit.fixture_capture.v1")
            self.assertEqual(meta["collector"], "bpf-io")
            self.assertEqual(meta["run_id"], "ddfacet-real-001")
            self.assertEqual(len(meta["files"]), 3)
            self.assertTrue(any(item["redacted"] for item in meta["files"]))

    def test_refuses_to_overwrite_without_force(self):
        with tempfile.TemporaryDirectory() as td:
            td = Path(td)
            run_dir = self.make_run(td)
            out = td / "fixtures"
            args = [
                sys.executable,
                str(SCRIPT),
                "--run", str(run_dir),
                "--collector", "bpf-io",
                "--output", str(out),
                "--label", "ci-bpf",
            ]
            run_cmd(args)
            second = run_cmd(args, check=False)
            self.assertNotEqual(second.returncode, 0)
            self.assertIn("use --force", second.stderr)
            forced = run_cmd([*args, "--force"])
            self.assertEqual(forced.returncode, 0)

    def test_missing_collector_files_fail_cleanly(self):
        with tempfile.TemporaryDirectory() as td:
            run_dir = Path(td) / "empty-run"
            run_dir.mkdir()
            out = Path(td) / "fixtures"
            result = run_cmd([
                sys.executable,
                str(SCRIPT),
                "--run", str(run_dir),
                "--collector", "amd-uprof-pcm",
                "--output", str(out),
            ], check=False)
            self.assertEqual(result.returncode, 1)
            self.assertIn("no known files found", result.stderr)

    def test_truncates_large_fixture_files(self):
        with tempfile.TemporaryDirectory() as td:
            td = Path(td)
            run_dir = self.make_run(td)
            (run_dir / "logs" / "bpf.log").write_text("x" * 1024)
            out = td / "fixtures"
            run_cmd([
                sys.executable,
                str(SCRIPT),
                "--run", str(run_dir),
                "--collector", "bpf-io",
                "--output", str(out),
                "--label", "small",
                "--max-bytes", "256",
            ])
            text = (out / "small" / "logs" / "bpf.log").read_text()
            self.assertIn("WCCKIT_FIXTURE_TRUNCATED", text)
            meta = json.loads((out / "small" / "fixture.meta.json").read_text())
            self.assertTrue(any(item["truncated"] for item in meta["files"]))


if __name__ == "__main__":
    unittest.main()
