import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SET_NVME = ROOT / "opti_disk" / "set_nvme.sh"
RUN_FIO = ROOT / "opti_disk" / "fio_scripts" / "run_fio.sh"


def run(args, env=None, check=False, input_text=None):
    result = subprocess.run(args, cwd=ROOT, env=env, input=input_text, text=True, capture_output=True)
    if check and result.returncode != 0:
        raise AssertionError(f"command failed: {args}\nstdout={result.stdout}\nstderr={result.stderr}")
    return result


def fake_path(tmpdir):
    bindir = Path(tmpdir) / "bin"
    bindir.mkdir()
    log = Path(tmpdir) / "commands.log"
    def script(name, body):
        p = bindir / name
        p.write_text("#!/bin/sh\n" + body)
        p.chmod(0o755)
    script("findmnt", f"echo findmnt \"$@\" >> {log}\nexit 1\n")
    script("lsblk", f"echo lsblk \"$@\" >> {log}\nif [ \"$1\" = \"-nr\" ]; then exit 0; fi\nexit 0\n")
    script("lscpu", "printf 'On-line CPU(s) list: 0-1\\n'\n")
    env = os.environ.copy()
    env["PATH"] = f"{bindir}:{env.get('PATH', '')}"
    env["WCCKIT_OPTI_DISK_RUN_PARENT"] = str(Path(tmpdir) / "runs")
    return env, log


class OptiDiskSafetyTests(unittest.TestCase):
    def test_set_nvme_dry_run_prints_destructive_plan_without_execution(self):
        with tempfile.TemporaryDirectory() as td:
            env, log = fake_path(td)
            result = run([str(SET_NVME), "--dry-run", "--device", "/dev/nvme-test", "--sector-size", "4096"], env=env)
            self.assertEqual(result.returncode, 0, result.stderr)
            output = result.stdout + result.stderr
            self.assertIn("dry-run mode", output)
            self.assertIn("[dry-run] parted", output)
            self.assertIn("[dry-run] mkfs.ext4", output)
            self.assertIn("/dev/nvme-test", output)
            self.assertNotIn("nvme format", log.read_text() if log.exists() else "")

    def test_set_nvme_rejects_missing_device_and_invalid_sector(self):
        missing = run([str(SET_NVME), "--dry-run"])
        self.assertNotEqual(missing.returncode, 0)
        self.assertIn("--device is required", missing.stderr)

        invalid = run([str(SET_NVME), "--dry-run", "--device", "/dev/nvme-test", "--sector-size", "not-a-number"])
        self.assertNotEqual(invalid.returncode, 0)
        self.assertIn("sector size must be numeric", invalid.stderr)

    def test_set_nvme_contains_confirmation_and_partition_safety_guards(self):
        text = SET_NVME.read_text()
        self.assertIn("Type the exact target device path to continue", text)
        self.assertIn('[[ "${confirmation}" == "${dev}" ]]', text)
        self.assertIn("expected exactly one partition", text)
        self.assertIn("refusing to operate", text)
        self.assertIn("/proc/swaps", text)

    def test_run_fio_dry_run_normalises_device_and_writes_manifest(self):
        with tempfile.TemporaryDirectory() as td:
            env, _log = fake_path(td)
            target = Path(td) / "target"
            target.mkdir()
            result = run([
                str(RUN_FIO),
                "--dry-run",
                "--device", "/dev/nvme0n1",
                "--target-dir", str(target),
                "--test", "reads",
            ], env=env)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("Target device: /dev/nvme0n1", result.stdout)
            self.assertNotIn("/dev//dev/nvme0n1", result.stdout)
            self.assertIn("[dry-run] hdparm -f /dev/nvme0n1", result.stdout)
            run_dirs = sorted((Path(td) / "runs").glob("*"))
            self.assertEqual(len(run_dirs), 1)
            manifest = (run_dirs[0] / "manifest.txt").read_text()
            self.assertIn("Dry run: 1", manifest)
            self.assertIn("JSON output: 1", manifest)
            self.assertTrue((run_dirs[0] / "fio").is_dir())

    def test_run_fio_invalid_test_fails_with_usage_style_error(self):
        result = run([str(RUN_FIO), "--dry-run", "--test", "invalid"])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("invalid test", result.stderr)

    def test_cpu_tuning_help_is_non_destructive(self):
        for rel in ["opti_disk/set_cpu_mode.sh", "opti_disk/reset_cpu_mode.sh"]:
            result = run([str(ROOT / rel), "--help"])
            self.assertEqual(result.returncode, 0, rel)
            self.assertIn("Options", result.stdout)


if __name__ == "__main__":
    unittest.main()
