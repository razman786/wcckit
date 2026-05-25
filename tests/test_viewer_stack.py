import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VIEWER = ROOT / "dockerfiles" / "viewer" / "influxdb-grafana"


class ViewerStackIntegrationChecks(unittest.TestCase):
    def test_compose_and_provisioning_files_are_consistent(self):
        compose = (VIEWER / "docker-compose.yml").read_text()
        self.assertIn("influxdb:", compose)
        self.assertIn("grafana:", compose)
        self.assertIn("pyroscope:", compose)
        self.assertIn("3000:3000", compose)
        self.assertIn("8086:8086", compose)
        self.assertIn("4040:4040", compose)
        self.assertIn("grafana/dashboards", compose)
        self.assertIn("grafana/provisioning", compose)

        influx = (VIEWER / "grafana" / "provisioning" / "datasources" / "influxdb.yml").read_text()
        pyro = (VIEWER / "grafana" / "provisioning" / "datasources" / "pyroscope.yml").read_text()
        dashboards = (VIEWER / "grafana" / "provisioning" / "dashboards" / "dashboards.yml").read_text()
        self.assertIn("${WCCKIT_INFLUX_URL}", influx)
        self.assertIn("WCCKIT_INFLUX_URL: http://influxdb:8086", compose)
        self.assertIn("WCCKIT InfluxDB", influx)
        self.assertIn("http://pyroscope:4040", pyro)
        self.assertIn("WCCKIT Pyroscope", pyro)
        self.assertIn("/var/lib/grafana/dashboards", dashboards)


if __name__ == "__main__":
    unittest.main()
