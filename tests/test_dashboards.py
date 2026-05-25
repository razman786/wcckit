import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DASH_DIR = ROOT / "dockerfiles" / "viewer" / "influxdb-grafana" / "grafana" / "dashboards"
PROV_DIR = ROOT / "dockerfiles" / "viewer" / "influxdb-grafana" / "grafana" / "provisioning"


def walk(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child)


def panel_titles(dashboard):
    panels = []
    for node in walk(dashboard):
        if "title" in node and ("type" in node or "gridPos" in node):
            panels.append((node.get("title", ""), node.get("gridPos", {}).get("y", 0)))
    return panels


class DashboardSemanticTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dashboards = {p.name: json.loads(p.read_text()) for p in DASH_DIR.glob("*.json")}

    def test_dashboards_have_unique_uids_and_titles(self):
        uids = []
        titles = []
        for name, dashboard in self.dashboards.items():
            self.assertTrue(dashboard.get("uid"), name)
            self.assertTrue(dashboard.get("title"), name)
            uids.append(dashboard["uid"])
            titles.append(dashboard["title"])
        self.assertEqual(len(uids), len(set(uids)))
        self.assertEqual(len(titles), len(set(titles)))

    def test_datasource_provisioning_matches_dashboard_references(self):
        datasource_text = "\n".join(p.read_text() for p in (PROV_DIR / "datasources").glob("*.yml"))
        self.assertIn("WCCKIT InfluxDB", datasource_text)
        self.assertIn("WCCKIT Pyroscope", datasource_text)
        self.assertIn("${WCCKIT_INFLUX_URL}", datasource_text)
        compose_text = (ROOT / "dockerfiles" / "viewer" / "influxdb-grafana" / "docker-compose.yml").read_text()
        self.assertIn("WCCKIT_INFLUX_URL: http://influxdb:8086", compose_text)
        self.assertIn("http://pyroscope:4040", datasource_text)
        dashboards_text = (PROV_DIR / "dashboards" / "dashboards.yml").read_text()
        self.assertIn("/var/lib/grafana/dashboards", dashboards_text)

        all_json = json.dumps(self.dashboards)
        self.assertIn("WCCKIT InfluxDB", all_json)
        self.assertIn("wcckit-pyroscope", all_json)

    def test_home_dashboard_links_point_to_existing_dashboards(self):
        home = self.dashboards["wcckit-home.json"]
        known_uids = {d["uid"] for d in self.dashboards.values()}
        text = json.dumps(home)
        linked = set(re.findall(r"/d/([A-Za-z0-9_-]+)", text))
        self.assertTrue(linked)
        self.assertTrue(linked.issubset(known_uids), linked - known_uids)

    def test_pipeline_overview_panel_order(self):
        overview = self.dashboards["wcckit-overview.json"]
        panels = panel_titles(overview)
        expected = [
            "Application Runtime Event Counts",
            "Hardware CPU Activity",
            "Memory Footprint",
            "BPF I/O Events",
            "Roofline",
            "Run Start/End Timeline",
            "Collector Exit Status",
        ]
        matched = []
        for wanted in expected:
            hits = [(title, y) for title, y in panels if wanted.lower() in title.lower()]
            self.assertTrue(hits, wanted)
            matched.append(min(y for _title, y in hits))
        self.assertEqual(matched, sorted(matched))

    def test_dashboard_queries_match_emitted_measurements(self):
        overview = json.dumps(self.dashboards["wcckit-overview.json"])
        self.assertIn("wcckit_app_ucalls", overview)
        self.assertIn("wcckit_app_ustat", overview)
        self.assertIn("wcckit_process_memory", overview)
        self.assertIn("wcckit_bpf_io_summary", overview)
        self.assertIn("wcckit_run_marker", overview)
        self.assertIn("wcckit_roofline_status", overview)

        intel = json.dumps(self.dashboards["intel-pcm-dashboard.json"])
        self.assertIn("wcckit_pcm_sensor", intel)
        self.assertIn("wcckit_pcm_cpu", intel)

        amd = json.dumps(self.dashboards["amd-uprof-dashboard.json"])
        self.assertIn("wcckit_amd_uprof_pcm", amd)
        self.assertIn("wcckit_amd_uprof_status", amd)
        self.assertIn("package_energy_kj", amd)
        self.assertIn("package_watts", amd)

    def test_flamegraph_dashboard_uses_pyroscope_and_current_label(self):
        profiles = self.dashboards["wcckit-profiles.json"]
        self.assertEqual(profiles["title"], "04 WCCKIT Flamegraphs")
        text = json.dumps(profiles)
        self.assertIn("wcckit-pyroscope", text)
        self.assertIn("CPU Sampled Flame Graph", text)
        self.assertIn("Application uflow", text)
        self.assertNotIn("WCCKIT Profiles", text)

    def test_disabled_no_data_text_is_intentional_and_not_huge(self):
        for name, dashboard in self.dashboards.items():
            for node in walk(dashboard):
                if isinstance(node.get("noValue"), str) and "Disabled: No data" in node["noValue"]:
                    self.assertLessEqual(len(node["noValue"]), 32, name)
                    options = node.get("options", {})
                    text = json.dumps(options)
                    self.assertNotIn("300%", text)


if __name__ == "__main__":
    unittest.main()
