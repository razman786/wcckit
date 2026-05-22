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

Use the same Git repository on the researcher laptop and on the compute node.
Build only the role needed on each host.

```bash
git clone https://github.com/razman786/wcckit.git
cd wcckit
```

Deployment model:

```text
researcher laptop/desktop:  viewer stack, unprivileged Grafana + InfluxDB + Pyroscope
compute node/server:        collector stack, privileged BCC/perf/hardware-counter tools
```

### Researcher Laptop: Viewer

Install Docker support for the viewer role:

```bash
dockerfiles/bin/install-wcckit-profiler-ubuntu2404.sh --viewer-only
```

Start the viewer:

```bash
dockerfiles/bin/run-wcckit-viewer.sh up
```

Open Grafana:

```text
http://localhost:3000
username: admin
password: wcckit
```

The viewer also exposes:

```text
InfluxDB:  http://localhost:8086
Pyroscope: http://localhost:4040
```

### Compute Node: Collector

Install Docker support and build the collector images:

```bash
dockerfiles/bin/install-wcckit-profiler-ubuntu2404.sh --collector-only
```

The collector builds without AMD μProf unless an AMD μProf package is supplied.
To include AMD μProf, download `amduprof_5.3-518_amd64.deb` from
<https://www.amd.com/en/developer/uprof.html>, accept AMD's EULA in the browser,
and place the file in the repository root:

```text
wcckit/amduprof_5.3-518_amd64.deb
```

The installer auto-detects that file. You can also pass
`--amd-uprof-deb <path>` or `--amd-uprof-url <url>` explicitly.

### Docker Access

If Docker was just installed and the user cannot access it yet:

```bash
sudo usermod -aG docker "$USER"
newgrp docker
```

Then rerun the installer with `--no-apt`:

```bash
dockerfiles/bin/install-wcckit-profiler-ubuntu2404.sh --viewer-only --no-apt
dockerfiles/bin/install-wcckit-profiler-ubuntu2404.sh --collector-only --no-apt
```

## Quick Start: Profile A Pipeline

This workflow is for the normal split deployment: viewer on the laptop, collector
on the compute node. It fills the WCCKIT Pipeline Overview dashboard and the
appropriate hardware dashboard.

### 1. Start The Viewer On The Laptop

```bash
dockerfiles/bin/run-wcckit-viewer.sh up
```

Keep the viewer running and open Grafana at:

```text
http://localhost:3000
```

### 2. Open The SSH Tunnel From The Laptop

For AMD systems, tunnel InfluxDB and Pyroscope back to the laptop:

```bash
dockerfiles/bin/run-wcckit-ssh-tunnel.sh <user>@<compute-node>
```

For Intel PCM systems, also forward the compute-node `pcm-sensor-server` endpoint
back to the laptop so the Intel PCM Grafana dashboard can scrape it:

```bash
dockerfiles/bin/run-wcckit-ssh-tunnel.sh --pcm-sensor <user>@<compute-node>
```

Keep this SSH session open while profiling. The collector on the compute node
will write to:

```text
InfluxDB:  http://127.0.0.1:18086
Pyroscope: http://127.0.0.1:14040
```

For Intel PCM, the tunnel prints a `WCCKIT_PCM_SENSOR_URL=...` value if Grafana
needs to scrape the forwarded PCM sensor endpoint.

### 3. Run The Collector On The Compute Node

Find the process ID:

```bash
pgrep -af DDFacet
PID=$(pgrep -n -f DDFacet)
```

Intel CPU:

```bash
dockerfiles/bin/run-wcckit-intel-overview.sh \
  --pid "$PID" \
  --pipeline DDFacet \
  --language python \
  --influx-url http://127.0.0.1:18086
```

AMD CPU:

```bash
dockerfiles/bin/run-wcckit-amd-overview.sh \
  --pid "$PID" \
  --pipeline DDFacet \
  --language python \
  --influx-url http://127.0.0.1:18086 \
  --amd-uprof-memory \
  --amd-uprof-power
```

The overview wrappers collect until the PID exits, or until their safety timeout
is reached. Use `--max-duration SECONDS` for a bounded capture.

Useful alternatives:

```bash
dockerfiles/bin/run-wcckit-intel-overview.sh --match DDFacet --pipeline DDFacet --influx-url http://127.0.0.1:18086
dockerfiles/bin/run-wcckit-amd-overview.sh --match DDFacet --pipeline DDFacet --influx-url http://127.0.0.1:18086
```

### 4. Inspect Grafana

Open:

```text
http://localhost:3000
```

Start with:

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

![Intel PCM live view](docs/images/wcckit-pcm-grafana-flow.svg)

Intel systems use Intel PCM. PCM counters are hardware and system level; they are
not strictly per-PID. BCC and perf provide stronger PID attribution.

![AMD μProf live view](docs/images/wcckit-amd-uprof-grafana-flow.svg)

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
