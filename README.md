# WCCKIT

[![CI](https://github.com/razman786/wcckit/actions/workflows/ci.yml/badge.svg)](https://github.com/razman786/wcckit/actions/workflows/ci.yml)

Copyright (c) 2026, Raz.
Licensed under the GNU General Public License v2.0. See [`LICENSE`](LICENSE).

WCCKIT is the Workload Characterisation and Capacity Kit: a Linux toolkit for
profiling and characterising radio-astronomy and astrophysics processing
pipelines. It follows the Workload Characterisation Framework emphasis on
standardised measurement, provenance, verification, operating-system profiling,
resource utilisation, and repeatable comparison across software and hardware
versions.

![WCCKIT profiling architecture](docs/images/wcckit-profiler-overview.svg)

## What This Repository Contains

- `dockerfiles/`: Ubuntu 24.04 profiler, collector, and viewer containers.
- `examples/profiling/`: small workloads for validating profiling setup before
  attaching to a real pipeline.
- `opti_disk/`: disk and CPU tuning helpers for radio-astronomy style processing
  pipelines. This is a focused WCCKIT subset for disk speed, efficiency, and
  system-setting experiments.

> **Disk safety warning:** `opti_disk/` is intended for controlled disk and NVMe
> characterisation work. Some workflows can format NVMe namespaces, rewrite
> partition tables, create filesystems, change sysfs/kernel settings, drop
> caches, and run destructive or heavy fio workloads. Do not use `opti_disk`
> unless you understand the commands, have selected the correct test device, and
> accept the risk of data loss or system disruption. You are responsible for your
> own hardware, data, and backups; WCCKIT accepts no responsibility for loss,
> damage, downtime, or data destruction caused by misuse or incorrect targets.

## Quick Start: Installation

Most researchers will use WCCKIT across two machines: a laptop or desktop for
the dashboards, and a compute node for the pipeline itself. Clone the same
repository on both machines, then build only the part each machine needs.

```bash
git clone https://github.com/razman786/wcckit.git
cd wcckit
```

In practice, the split looks like this:

```text
researcher laptop/desktop:  viewer stack for Grafana, InfluxDB, and Pyroscope
compute node/server:        collector stack beside the running pipeline process
```

### Researcher Laptop: Viewer

Do this on the machine where you want to open Grafana in a web browser:

```bash
dockerfiles/bin/install-wcckit-profiler-ubuntu2404.sh --viewer-only
```

Start the dashboard stack:

```bash
dockerfiles/bin/run-wcckit-viewer.sh up
```

Then open Grafana:

```text
http://localhost:3000
username: admin
password: wcckit
```

The collector will later send data back to these local services:

```text
InfluxDB:  http://localhost:8086
Pyroscope: http://localhost:4040
```

### Compute Node: Collector

Do this on the machine where the pipeline will run. The collector needs host
visibility for BPF, perf, and hardware counters, so it is kept separate from the
laptop viewer:

```bash
dockerfiles/bin/install-wcckit-profiler-ubuntu2404.sh --collector-only
```

For Intel-only use, no extra vendor package is needed. For AMD CPU hardware
counters, first download `amduprof_5.3-518_amd64.deb` from
<https://www.amd.com/en/developer/uprof.html>, accept AMD's EULA in the browser,
and place the file in the repository root before building:

```text
wcckit/amduprof_5.3-518_amd64.deb
```

The installer auto-detects that file and builds AMD μProf into the collector
image. You can also pass `--amd-uprof-deb <path>` or `--amd-uprof-url <url>`
explicitly.

### Docker Access

If Docker has just been installed and your shell cannot access it yet:

```bash
sudo usermod -aG docker "$USER"
newgrp docker
```

Then rerun the relevant installer command with `--no-apt`:

```bash
dockerfiles/bin/install-wcckit-profiler-ubuntu2404.sh --viewer-only --no-apt
dockerfiles/bin/install-wcckit-profiler-ubuntu2404.sh --collector-only --no-apt
```

## Quick Start: Profile A Pipeline

Use this path when the pipeline is running on a compute node and Grafana is open
on your laptop. The aim is simple: attach to one pipeline PID for 60 seconds and
fill the WCCKIT Pipeline Overview plus the Intel or AMD hardware dashboard.

### 1. Start The Viewer On The Laptop

```bash
dockerfiles/bin/run-wcckit-viewer.sh up
```

Leave this running, then open Grafana at:

```text
http://localhost:3000
```

### 2. Open The SSH Tunnel From The Laptop

Now make the compute node see your laptop viewer as local services. For AMD
systems, the normal tunnel is enough:

```bash
dockerfiles/bin/run-wcckit-ssh-tunnel.sh <user>@<compute-node>
```

For Intel PCM systems, add the PCM sensor forward. This lets the Intel dashboard
scrape the live `pcm-sensor-server` data from the compute node:

```bash
dockerfiles/bin/run-wcckit-ssh-tunnel.sh --pcm-sensor <user>@<compute-node>
```

Keep this SSH session open. From the compute node, the collector will write to:

```text
InfluxDB:  http://127.0.0.1:18086
Pyroscope: http://127.0.0.1:14040
```

For Intel PCM, the tunnel also prints a `WCCKIT_PCM_SENSOR_URL=...` value. Use
that value if the Intel dashboard needs the forwarded sensor endpoint explicitly.

### 3. Run The Collector On The Compute Node

In a second SSH session to the compute node, find the pipeline process:

```bash
pgrep -af DDFacet
PID=$(pgrep -n -f DDFacet)
```

For an Intel CPU, run this collector command:

![Intel PCM live view](docs/images/wcckit-pcm-grafana-flow.svg)

```bash
dockerfiles/bin/run-wcckit-intel-overview.sh \
  --pid "$PID" \
  --pipeline DDFacet \
  --language python \
  --max-duration 60 \
  --influx-url http://127.0.0.1:18086
```

For an AMD CPU, run this collector command:

![AMD μProf live view](docs/images/wcckit-amd-uprof-grafana-flow.svg)

```bash
dockerfiles/bin/run-wcckit-amd-overview.sh \
  --pid "$PID" \
  --pipeline DDFacet \
  --language python \
  --max-duration 60 \
  --influx-url http://127.0.0.1:18086 \
  --amd-uprof-memory \
  --amd-uprof-power
```

These examples stop after 60 seconds even if the pipeline keeps running. Increase
`--max-duration` when you want a longer window.

If it is easier, let WCCKIT find the newest matching process for you:

```bash
dockerfiles/bin/run-wcckit-intel-overview.sh --match DDFacet --pipeline DDFacet --max-duration 60 --influx-url http://127.0.0.1:18086
dockerfiles/bin/run-wcckit-amd-overview.sh --match DDFacet --pipeline DDFacet --max-duration 60 --influx-url http://127.0.0.1:18086 --amd-uprof-memory --amd-uprof-power
```

## Open Grafana And Select A Dashboard

Return to the laptop and open Grafana in a web browser:

```text
http://localhost:3000
username: admin
password: wcckit
```

Use the left-hand Grafana navigation to open **Dashboards**, then start with:

- **WCCKIT Pipeline Overview**: runtime events, CPU activity, memory footprint,
  BPF I/O events, roofline status, run span, and collector status.
- **Intel® Performance Counter Monitor Dashboard**: Intel PCM live telemetry.
- **AMD μProf / AMDuProfPcm Dashboard**: AMD hardware-counter telemetry.
- **WCCKIT Profiles**: interactive CPU and application profile views when
  profile pushing is enabled.

## WCCKIT

### Flame Graphs

Flame graphs are optional in the overview wrappers. They add useful source and
stack context, but they also add profiler overhead and data volume.

Enable sampled CPU flame graphs and push folded profiles to Pyroscope:

```bash
dockerfiles/bin/run-wcckit-intel-overview.sh \
  --pid "$PID" \
  --pipeline DDFacet \
  --language python \
  --max-duration 60 \
  --influx-url http://127.0.0.1:18086 \
  --pyroscope-url http://127.0.0.1:14040 \
  --flamegraph \
  --push-profiles
```

For AMD, use the same profile options with `run-wcckit-amd-overview.sh`.

![Simplified flame graph readout](docs/images/wcckit-flamegraph-readout.svg)

CPU flame graphs are sampled profiles. They show where sampled CPU time was
spent; they are not complete function-call traces. WCCKIT preserves folded stack
artifacts and SVG files under each run directory.

For Python 3.12 and 3.13 workloads, prefer Python perf-map support:

```bash
python3 -X perf my_pipeline.py
```

This improves Python frame visibility in Linux `perf` and BCC CPU flame graphs.

### Validate The Flame Graph Path

Run the synthetic hotspot before profiling a real pipeline:

```bash
examples/profiling/profile_python_hotspot.sh
```

Outputs:

```text
profile-output/python-hotspot.svg
profile-output/python-hotspot.log
```

The log records the PID, hotspot function, and source-line anchor. The SVG should
show the intentional hotspot when Python perf-map support is available.

### Hardware Counter Backends

Intel systems use Intel PCM. PCM counters are hardware and system level; they are
not strictly per-PID. BCC and perf provide stronger PID attribution.

AMD systems use AMD μProf / `AMDuProfPcm` when it is installed in the collector
image. WCCKIT records unavailable or unsupported counters rather than treating
them as fatal. AMD roofline support is exposed separately through:

```bash
dockerfiles/bin/run-wcckit-amd-roofline.sh --help
```

### Raw Artifacts

Each run writes reproducible local artifacts:

```text
runs/<run_id>/
  manifest.json
  events/
  metrics/
  profiles/
  flamegraphs/
  logs/
```

InfluxDB and Grafana are for live analysis. JSONL, CSV, folded profiles, SVGs,
and logs remain the canonical archive for later review.

### Low-Level Disk Characterisation

`opti_disk/` is a lower-level subset for NVMe, fio, queue, and CPU-mode
experiments. Use dry-run modes first and review every target device before
running destructive setup commands.

## Useful Commands

Viewer:

```bash
dockerfiles/bin/run-wcckit-viewer.sh up
dockerfiles/bin/run-wcckit-viewer.sh status
dockerfiles/bin/run-wcckit-viewer.sh logs
dockerfiles/bin/run-wcckit-viewer.sh stop
```

Connection diagnostics on the compute node:

```bash
dockerfiles/bin/run-wcckit-debug-connection.sh \
  --influx-url http://127.0.0.1:18086 \
  --pyroscope-url http://127.0.0.1:14040
```

General pipeline wrapper:

```bash
dockerfiles/bin/run-wcckit-pipeline-overview.sh --help
dockerfiles/bin/run-wcckit-pipeline-profiler.sh --help
```

Standalone CPU profiler:

```bash
dockerfiles/bin/run-wcckit-profiler.sh --out ./profile-output -- \
  wcckit_profile_cpu.sh --pid "$PID" --duration 30 --output /out/cpu.svg
```

## FAQ

### How Do I Stop The Collector Without Losing Progress?

Press `Ctrl-C` once in the collector terminal. The wrapper traps shutdown,
stops child collectors, writes logs and status points, and pushes the line
protocol collected so far. If the profiled PID exits naturally, the wrapper also
finishes and writes the run artifacts.

### Why Is The Intel PCM Dashboard Empty?

The Intel dashboard reads the live `pcm-sensor-server` endpoint. For split
deployment, start the SSH tunnel with `--pcm-sensor` and keep it open:

```bash
dockerfiles/bin/run-wcckit-ssh-tunnel.sh --pcm-sensor <user>@<compute-node>
```

The tunnel prints the `WCCKIT_PCM_SENSOR_URL=...` value expected by the viewer.
If the dashboard is still empty, run the connection debugger and confirm that
`pcm-sensor-server` is listening on the compute node.

### Why Is The AMD Dashboard Empty?

The collector image must include AMD μProf for `AMDuProfPcm` telemetry. Place
`amduprof_5.3-518_amd64.deb` in the repository root or pass `--amd-uprof-deb`
when building the collector. Some counters also require CPU, kernel, MSR, or
permission support from the host.

### Should I Use A Desktop IP Address Instead Of SSH Tunnels?

Prefer SSH tunnels. They avoid opening InfluxDB, Pyroscope, or Grafana directly
on the network and give the collector stable localhost endpoints on the compute
node.

### What If Docker Installation Reports A `containerd` Conflict?

The host has mixed Docker packaging sources. Either keep the current Docker
installation and rerun WCCKIT with `--no-apt`, or choose one Docker package
family. Do not install Ubuntu `docker.io` and Docker CE `containerd.io` together.

### Does WCCKIT Support Go, C, Or Other Non-Python Pipelines?

CPU flame graphs work for native, Go, C/C++, and mixed workloads when symbols and
frame pointers or unwind data are available. BCC `uflow` language tracing is more
runtime-dependent and is not the primary path for Go pipelines. For Go services,
use sampled CPU profiling first.

### Why Not Store Everything In InfluxDB?

Full stacks, paths, method names, and raw event streams can create high-cardinality
time-series data. WCCKIT keeps dense raw data on disk and sends bounded metrics,
status, and summaries to InfluxDB.

### Where Are The Advanced Notes?

Use the script help output for current options:

```bash
dockerfiles/bin/install-wcckit-profiler-ubuntu2404.sh --help
dockerfiles/bin/run-wcckit-ssh-tunnel.sh --help
dockerfiles/bin/run-wcckit-intel-overview.sh --help
dockerfiles/bin/run-wcckit-amd-overview.sh --help
dockerfiles/bin/run-wcckit-pipeline-profiler.sh --help
```

Detailed operational notes are better suited to project wiki pages as the
deployment patterns stabilise.
