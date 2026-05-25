# Start the Viewer

The viewer stack runs on the laptop or desktop where the researcher opens a browser. It contains:

- **Grafana** for dashboards.
- **InfluxDB** for time-series metrics and collector status.
- **Pyroscope** for interactive flamegraph/profile views.

Start it with:

```bash
dockerfiles/bin/run-wcckit-viewer.sh up
```

Open Grafana:

```text
http://localhost:3000
username: admin
password: wcckit
```

Development endpoints:

```text
Grafana:   http://localhost:3000
InfluxDB:  http://localhost:8086
Pyroscope: http://localhost:4040
Org:       wcckit
Bucket:    wcckit
Token:     wcckit-dev-token
```

These are development defaults, not production secrets.

## Viewer Commands

```bash
dockerfiles/bin/run-wcckit-viewer.sh up
dockerfiles/bin/run-wcckit-viewer.sh status
dockerfiles/bin/run-wcckit-viewer.sh logs
dockerfiles/bin/run-wcckit-viewer.sh config
dockerfiles/bin/run-wcckit-viewer.sh stop
```

The first dashboard to open is **01 WCCKIT Pipeline Overview**. Use the AMD, Intel, or Flamegraphs dashboard after you know which collector path was used.
