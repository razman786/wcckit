import gzip
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / "dockerfiles" / "profiling" / "pipeline" / "bin"
FIXTURES = ROOT / "tests" / "fixtures"


def run_cmd(args, check=True):
    result = subprocess.run(args, cwd=ROOT, text=True, capture_output=True)
    if check and result.returncode != 0:
        raise AssertionError(f"command failed: {args}\nstdout={result.stdout}\nstderr={result.stderr}")
    return result


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class ParserTests(unittest.TestCase):
    def test_bpf_biosnoop_and_biolatency_outputs(self):
        with tempfile.TemporaryDirectory() as td:
            td = Path(td)
            jsonl = td / "bpf.jsonl"
            lp = td / "bpf.lp"
            run_cmd([
                sys.executable, str(BIN / "wcckit_parse_bpf_io.py"),
                "--input", str(FIXTURES / "biosnoop-sample.txt"),
                "--jsonl", str(jsonl),
                "--line-protocol", str(lp),
                "--run-id", "bpf-smoke",
                "--pipeline", "DDFacet",
            ])
            rows = [json.loads(line) for line in jsonl.read_text().splitlines()]
            self.assertEqual(len(rows), 2)
            self.assertEqual(sum(r.get("bytes", 0) for r in rows), 12288)
            text = lp.read_text()
            self.assertIn("wcckit_bpf_io_summary", text)
            self.assertIn("events_total=2i", text)
            self.assertIn("bytes=12288i", text)

            jsonl2 = td / "biolatency.jsonl"
            lp2 = td / "biolatency.lp"
            run_cmd([
                sys.executable, str(BIN / "wcckit_parse_bpf_io.py"),
                "--input", str(FIXTURES / "biolatency-sample.txt"),
                "--jsonl", str(jsonl2),
                "--line-protocol", str(lp2),
                "--run-id", "bpf-hist",
                "--pipeline", "DDFacet",
            ])
            hist_rows = [json.loads(line) for line in jsonl2.read_text().splitlines()]
            self.assertEqual(len(hist_rows), 1)
            self.assertEqual(hist_rows[0]["events_total"], 4)
            self.assertIn("tool=biolatency", lp2.read_text())

    def test_jsonl_to_influx_escaping_and_types(self):
        with tempfile.TemporaryDirectory() as td:
            out = Path(td) / "out.lp"
            run_cmd([
                sys.executable, str(BIN / "wcckit_jsonl_to_influx.py"),
                "--input", str(FIXTURES / "jsonl-to-influx-sample.jsonl"),
                "--output", str(out),
                "--measurement", "wcckit_test",
                "--tag", "run_id",
                "--tag", "pipeline",
            ])
            line = out.read_text().strip()
            self.assertIn(r"run_id=run\ one", line)
            self.assertIn(r"pipeline=DDFacet\,stage\=1", line)
            self.assertIn("pid=1234i", line)
            self.assertIn("events_total=7i", line)
            self.assertIn("ratio=1.5", line)
            self.assertIn("active=true", line)
            self.assertIn(r'message="quoted \"text\""', line)
            self.assertTrue(line.endswith(" 1000"))

    def test_app_tools_ucalls_ustat_syscall_and_empty(self):
        cases = [
            ("ucalls", "python", "app-ucalls-sample.txt", "events_total=5i", "errors_total=1i"),
            ("ustat", "python", "app-ustat-sample.txt", "events_total=1i", "available=true"),
            ("ucalls", "syscall", "app-syscalls-sample.txt", "events_total=3i", "errors_total=1i"),
        ]
        with tempfile.TemporaryDirectory() as td:
            td = Path(td)
            for tool, language, fixture, expected_a, expected_b in cases:
                jsonl = td / f"{fixture}.jsonl"
                lp = td / f"{fixture}.lp"
                run_cmd([
                    sys.executable, str(BIN / "wcckit_parse_app_tools.py"),
                    "--tool", tool,
                    "--language", language,
                    "--pid", "1234",
                    "--input", str(FIXTURES / fixture),
                    "--jsonl", str(jsonl),
                    "--line-protocol", str(lp),
                    "--run-id", "app-smoke",
                    "--pipeline", "DDFacet",
                ])
                text = lp.read_text()
                self.assertIn(expected_a, text)
                self.assertIn(expected_b, text)

            empty = td / "empty.txt"
            empty.write_text("")
            lp = td / "empty.lp"
            jsonl = td / "empty.jsonl"
            run_cmd([
                sys.executable, str(BIN / "wcckit_parse_app_tools.py"),
                "--tool", "ustat",
                "--language", "python",
                "--pid", "1234",
                "--input", str(empty),
                "--jsonl", str(jsonl),
                "--line-protocol", str(lp),
                "--run-id", "app-empty",
                "--pipeline", "DDFacet",
            ])
            self.assertEqual(jsonl.read_text(), "")
            self.assertIn("available=false", lp.read_text())

    def test_amd_uprof_pcm_memory_power_and_malformed_rows(self):
        with tempfile.TemporaryDirectory() as td:
            td = Path(td)
            for fixture, expected in [
                ("amd-uprof-pcm-sample.csv", ["ipc=", "frequency_ghz=", "package_watts="]),
                ("amd-uprof-memory-sample.csv", ["memory_read_gbs=", "memory_write_gbs="]),
                ("amd-uprof-power-sample.csv", ["package_watts=", "core_watts="]),
            ]:
                jsonl = td / f"{fixture}.jsonl"
                lp = td / f"{fixture}.lp"
                run_cmd([
                    sys.executable, str(BIN / "wcckit_parse_amd_uprof_pcm.py"),
                    "--input", str(FIXTURES / fixture),
                    "--jsonl", str(jsonl),
                    "--line-protocol", str(lp),
                    "--run-id", "amd-parser",
                    "--pipeline", "DDFacet",
                    "--pid", "1234",
                    "--vendor", "AuthenticAMD",
                    "--start-timestamp-ns", "1000000000",
                ])
                rows = [json.loads(line) for line in jsonl.read_text().splitlines()]
                self.assertGreaterEqual(len(rows), 1)
                text = lp.read_text()
                self.assertIn("wcckit_amd_uprof_pcm", text)
                self.assertIn("wcckit_amd_uprof_status", text)
                for token in expected:
                    self.assertIn(token, text)
                self.assertNotIn("not available", text)


    def test_esmi_energy_and_roofline_status_paths_are_explicit(self):
        esmi_rows = (FIXTURES / "esmi-energy-sample.csv").read_text().splitlines()
        self.assertEqual(esmi_rows[0], "Socket,Energy")
        self.assertIn("0,123.456", esmi_rows[1])
        coordinator = (BIN / "wcckit_profile_pipeline.sh").read_text()
        self.assertIn("--csv --showsockenergy", coordinator)
        self.assertIn("amd-esmi-energy", coordinator)
        self.assertIn("package_energy_kj", coordinator)
        self.assertIn("package_watts", coordinator)

        roofline = json.loads((FIXTURES / "amd-roofline-summary-sample.json").read_text())
        self.assertEqual(roofline["tool"], "amd-uprof-roofline")
        self.assertEqual(roofline["report_html_count"], 1)
        roofline_script = (BIN / "wcckit_amd_uprof_roofline.sh").read_text()
        self.assertIn("wcckit_roofline_status", roofline_script)
        self.assertIn("report_html_count", roofline_script)
        self.assertIn("csv_count", roofline_script)

    def test_uflow_preserves_all_lines_and_separates_threads(self):
        with tempfile.TemporaryDirectory() as td:
            td = Path(td)
            jsonl = td / "uflow.jsonl"
            folded = td / "uflow.folded"
            lp = td / "uflow.lp"
            run_cmd([
                sys.executable, str(BIN / "wcckit_parse_uflow.py"),
                "--input", str(FIXTURES / "uflow-nested-sample.txt"),
                "--jsonl", str(jsonl),
                "--folded", str(folded),
                "--line-protocol", str(lp),
                "--run-id", "uflow-nested",
                "--pipeline", "DDFacet",
                "--pid", "1234",
                "--language", "python",
            ])
            input_nonempty = [line for line in (FIXTURES / "uflow-nested-sample.txt").read_text().splitlines() if line.strip()]
            rows = [json.loads(line) for line in jsonl.read_text().splitlines()]
            # Header plus malformed data row are deliberately preserved as raw_unparsed rows.
            self.assertEqual(len(rows), len(input_nonempty))
            self.assertTrue(any(r.get("type") == "raw_unparsed" for r in rows))
            folded_text = folded.read_text()
            self.assertIn("DDFacet.Pipeline.run;DDFacet.Pipeline.solve", folded_text)
            self.assertIn("DDFacet.Writer.write", folded_text)
            lp_text = lp.read_text()
            self.assertIn("wcckit_app_uflow_summary", lp_text)
            self.assertIn("unparsed_events_total=2i", lp_text)

    def test_pyroscope_helpers_without_live_server(self):
        module = load_module("wcckit_push_pyroscope", BIN / "wcckit_push_pyroscope.py")
        with tempfile.TemporaryDirectory() as td:
            folded = Path(td) / "cpu.folded"
            folded.write_text("root;module.func 3\nroot;other 2\nmalformed\n")
            rows = module.parse_folded(folded)
            self.assertEqual(len(rows), 2)
            payload = module.folded_to_pprof(rows, 1000, 1_000_000)
            self.assertGreater(len(payload), 20)
            self.assertGreater(len(gzip.decompress(payload)), 0)
            self.assertEqual(module.clean_app_name("DDFacet pipeline!"), "DDFacet_pipeline_")
            self.assertEqual(module.label_value("run id/with spaces"), "run_id_with_spaces")
            # Stack symbols must stay in the pprof payload, not become labels.
            labels = []
            self.assertNotIn("module.func", labels)

            empty = Path(td) / "empty.folded"
            empty.write_text("")
            result = run_cmd([
                sys.executable, str(BIN / "wcckit_push_pyroscope.py"),
                "--url", "http://127.0.0.1:9",
                "--app-name", "ci",
                "--profile-type", "cpu",
                "--input", str(empty),
                "--run-id", "ci",
                "--pipeline", "ci",
                "--pid", "1",
            ], check=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("missing or empty", result.stderr)


if __name__ == "__main__":
    unittest.main()
