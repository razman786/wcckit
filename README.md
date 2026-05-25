<p align="center">
  <img src="docs/logos/PNGs/wcckit_logo_rectangle_cropped.png" alt="WCCKIT logo" width="760">
</p>

<h1 align="center">WCCKIT</h1>

<p align="center">
  <strong>Workload Characterisation and Capacity Kit for radio-astronomy pipeline profiling.</strong>
</p>

<p align="center">
  <a href="https://github.com/razman786/wcckit/actions/workflows/ci.yml"><img src="https://github.com/razman786/wcckit/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
</p>

Copyright (c) 2026, Raz. Licensed under the GNU General Public License v2.0. See [`LICENSE`](LICENSE).

WCCKIT is a Linux toolkit for profiling and characterising radio-astronomy and astrophysics processing pipelines. It helps a researcher attach to a running pipeline PID, collect CPU, memory, I/O, hardware-counter, and flamegraph telemetry, view the run in Grafana, and keep reproducible raw artifacts for later comparison.

![WCCKIT profiling architecture](docs/images/wcckit-profiler-overview.svg)

## Documentation

The full user guide is published with GitHub Pages:

**https://razman786.github.io/wcckit/**

Useful sections:

- [Quick start](https://razman786.github.io/wcckit/quick-start/)
- [Dashboard guide](https://razman786.github.io/wcckit/dashboards/)
- [Intel PCM guide](https://razman786.github.io/wcckit/cli/intel-pcm-tools/)
- [AMD uProf guide](https://razman786.github.io/wcckit/cli/amd-uprof-tools/)
- [Flamegraph guide](https://razman786.github.io/wcckit/quick-start/flamegraphs/)
- [opti_disk safety](https://razman786.github.io/wcckit/opti-disk/safety/)
- [Troubleshooting](https://razman786.github.io/wcckit/reference/troubleshooting/)

## What WCCKIT Does

- Profiles radio-astronomy and astrophysics pipelines by PID.
- Splits the privileged compute-node collector from the laptop/desktop viewer.
- Provides Grafana dashboards for pipeline overview, Intel PCM, AMD uProf, and flamegraphs.
- Collects Intel hardware telemetry with Intel PCM.
- Collects AMD hardware telemetry with AMD uProf/AMDuProfPcm and e-smi where supported.
- Uses BCC/eBPF for I/O and runtime tracing paths.
- Produces sampled CPU flamegraphs and interactive Pyroscope profile views.
- Writes reproducible run artifacts under `runs/<run_id>/`.
- Uses local Docker images and wrappers rather than requiring native Grafana on compute nodes.

## Quick Start

Clone the repository on the laptop/desktop and on the compute node:

```bash
git clone https://github.com/razman786/wcckit.git
cd wcckit
```

On the laptop or desktop, install and start the viewer:

```bash
dockerfiles/bin/install-wcckit-profiler-ubuntu2404.sh --viewer-only
dockerfiles/bin/run-wcckit-viewer.sh up
```

Open Grafana:

```text
http://localhost:3000
username: admin
password: wcckit
```

On the compute node, build the collector images:

```bash
dockerfiles/bin/install-wcckit-profiler-ubuntu2404.sh --collector-only
```

From the laptop, open the SSH tunnel to the compute node:

```bash
dockerfiles/bin/run-wcckit-ssh-tunnel.sh <user>@<compute-node>
```

For Intel PCM live dashboard support, include the PCM sensor forward:

```bash
dockerfiles/bin/run-wcckit-ssh-tunnel.sh --pcm-sensor <user>@<compute-node>
```

On the compute node, find the pipeline PID:

```bash
pgrep -af DDFacet
PID=$(pgrep -n -f DDFacet)
```

Intel CPU example for a 60 second overview run:

```bash
dockerfiles/bin/run-wcckit-intel-overview.sh \
  --pid "$PID" \
  --pipeline DDFacet \
  --language python \
  --max-duration 60 \
  --influx-url http://127.0.0.1:18086
```

AMD CPU example for a 60 second overview run:

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

Return to Grafana and start with **01 WCCKIT Pipeline Overview**. Open the AMD, Intel, or Flamegraphs dashboard according to the collector path used.

## FAQ

### Do I need Grafana?

No. Grafana is the interactive viewer. WCCKIT still writes raw artifacts under `runs/<run_id>/`, and Intel PCM, AMD uProf, BCC, and perf tools can also be run directly from the collector image.

### Can I use WCCKIT on Intel and AMD nodes?

Yes. Use `run-wcckit-intel-overview.sh` on Intel hosts and `run-wcckit-amd-overview.sh` on AMD hosts. Optional vendor metrics depend on CPU, firmware, kernel, permissions, and whether the collector image includes the required package.

### Are hardware counters per-PID?

Usually not. Intel PCM and many AMD hardware counters are socket, core, memory-controller, PCIe, or system scoped. BPF and sampled CPU profiling provide stronger PID attribution.

### Where are results saved?

Each run writes a directory under `runs/<run_id>/` containing a manifest, events, metrics, profiles, flamegraphs, logs, and optional roofline outputs.

### Why does Grafana show `Disabled: No data`?

The selected time range has no matching points for that panel. The collector may have been disabled, unsupported on that host, unavailable in the image, or unable to push to InfluxDB/Pyroscope.

### Does WCCKIT change CPU governors?

The normal pipeline profiler does not change CPU governors. Some `opti_disk/` scripts can change CPU settings, but `opti_disk` is a separate low-level subset.

### Does the normal pipeline profiler run opti_disk?

No. The default pipeline profiler and Grafana workflow do not run `opti_disk`.

### Is opti_disk destructive?

It can be. `opti_disk/` contains disk and NVMe characterisation helpers that may format devices, rewrite partition tables, create filesystems, change kernel/sysfs settings, drop caches, or run heavy `fio` workloads. Read the [opti_disk safety guide](https://razman786.github.io/wcckit/opti-disk/safety/) before using it.

### Can I use the CLI tools directly?

Yes. The collector image includes Intel PCM, BCC tools, perf support, and WCCKIT wrappers. AMD uProf and e-smi availability depends on the collector build and host support. See the CLI guide in the documentation site.

## Repository Contents

- `dockerfiles/`: Ubuntu 24.04 profiler, collector, and viewer containers.
- `docs/`: MkDocs documentation site, images, and WCCKIT logo assets.
- `examples/profiling/`: small workloads for validating profiling setup before attaching to a real pipeline.
- `opti_disk/`: separate disk/NVMe/fio and CPU-setting characterisation subset.
- `tests/fixtures/`: parser fixtures used by CI.

## opti_disk Safety Note

`opti_disk/` is separate from the normal WCCKIT pipeline profiler. It is intended for controlled disk and NVMe experiments and can be destructive if used on the wrong device. Use it only when you understand the target device, have backups, and accept the risk of data loss or system disruption. WCCKIT accepts no responsibility for loss, damage, downtime, or data destruction caused by misuse or incorrect targets.
