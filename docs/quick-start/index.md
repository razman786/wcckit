# Quick Start

The normal WCCKIT workflow uses two roles.

| Role | Usually Runs On | Purpose |
| --- | --- | --- |
| Viewer | Researcher laptop or desktop | Grafana, InfluxDB, Pyroscope, dashboards, and profile viewing. |
| Collector | Compute node or server | Privileged container that attaches to the pipeline PID and writes telemetry. |

This split keeps Grafana off the compute node and lets the collector observe the host kernel and hardware counters where the pipeline is actually running.

## Minimal Sequence

On both machines:

```bash
git clone https://github.com/razman786/wcckit.git
cd wcckit
```

On the laptop or desktop:

```bash
dockerfiles/bin/install-wcckit-profiler-ubuntu2404.sh --viewer-only
dockerfiles/bin/run-wcckit-viewer.sh up
```

On the compute node:

```bash
dockerfiles/bin/install-wcckit-profiler-ubuntu2404.sh --collector-only
```

From the laptop, keep an SSH tunnel open:

```bash
dockerfiles/bin/run-wcckit-ssh-tunnel.sh <user>@<compute-node>
```

On the compute node, attach the collector to a PID:

```bash
PID=$(pgrep -n -f DDFacet)
dockerfiles/bin/run-wcckit-intel-overview.sh \
  --pid "$PID" \
  --pipeline DDFacet \
  --language python \
  --max-duration 60 \
  --influx-url http://127.0.0.1:18086
```

For AMD nodes, use `run-wcckit-amd-overview.sh` instead. Open Grafana at `http://localhost:3000` with `admin` / `wcckit`.
