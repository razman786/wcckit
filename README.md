<p align="center">
  <img src="docs/logos/PNGs/wcckit_logo_rectangle_cropped.png" alt="WCCKIT logo" width="760">
</p>

<p align="center">
  <a href="https://github.com/razman786/wcckit/actions/workflows/ci.yml"><img src="https://github.com/razman786/wcckit/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://razman786.github.io/wcckit/">
    <img src="https://img.shields.io/badge/Full%20User%20Guide-Open%20Documentation-1f6f93?style=for-the-badge" alt="Open the full WCCKIT user guide">
  </a>
</p>

<p align="center">
  <strong>Workload Characterisation and Capacity Kit</strong>
</p>

WCCKIT is a Linux toolkit for profiling and characterising radio-astronomy and astrophysics processing pipelines. It helps a researcher attach to a running pipeline PID, collect CPU, memory, I/O, hardware-counter, and flamegraph telemetry, view the run in Grafana, and keep reproducible raw artifacts for later comparison.

<p align="center">
  <img src="docs/images/wcckit-profiler-overview.svg" alt="WCCKIT split viewer and collector workflow" width="760">
</p>

<p align="center">
  <a href="https://razman786.github.io/wcckit/quick-start/"><strong>Start the Quick Guide</strong></a> |
  <a href="https://razman786.github.io/wcckit/dashboards/"><strong>Read the Dashboard Guide</strong></a> |
  <a href="https://razman786.github.io/wcckit/cli/"><strong>CLI Tools</strong></a>
</p>

## Overview

WCCKIT follows the Workload Characterisation Framework idea that a useful benchmark is not only a final number. A profiling run should record the workload, the host, the software version, the collection settings, the timing window, and the raw observations needed to re-check or compare results later.

The toolkit keeps the collector close to the workload on the compute node, while Grafana, InfluxDB, and Pyroscope run as a separate viewer stack on the researcher laptop or desktop. This makes the default workflow suitable for long-running pipeline jobs without requiring a native Grafana installation on the compute node.

| Capability | What it gives you |
| --- | --- |
| Pipeline-aware telemetry | Attach to a PID, collect bounded time-series metrics, and align run start/end markers with application runtime, I/O, memory, and CPU activity. |
| Hardware counter backends | Use Intel PCM on Intel nodes and AMD uProf/e-smi on AMD nodes where the hardware, drivers, and permissions expose those counters. |
| Reproducible artifacts | Keep manifests, JSONL events, logs, line protocol, folded stacks, static SVG flamegraphs, and roofline outputs under `runs/<run_id>/`. |

## What WCCKIT Gives You

- A **viewer stack** for Grafana, InfluxDB, and Pyroscope on a laptop or desktop.
- A **collector stack** for the compute node that runs beside the pipeline process.
- Intel CPU telemetry through **Intel PCM**.
- AMD CPU telemetry through **AMD uProf / AMDuProfPcm** and **AMD e-smi** where supported.
- Kernel and I/O telemetry through **BCC/eBPF** tools.
- Sampled CPU flamegraphs through **perf/BCC profile.py** and interactive profile views through **Pyroscope**.
- Reproducible run directories under `runs/<run_id>/` with manifests, JSONL events, logs, folded profiles, SVG flamegraphs, and line protocol.

## Start Here

| Step | Guide |
| --- | --- |
| 1. Install | Clone the repository on the viewer machine and, where needed, on the compute node. Build only the role required on each machine. [Installation guide](https://razman786.github.io/wcckit/quick-start/installation/) |
| 2. Connect | Start the viewer, open the SSH tunnel, and forward InfluxDB, Pyroscope, and Intel PCM sensor endpoints as required. [SSH tunnel guide](https://razman786.github.io/wcckit/quick-start/ssh-tunnels/) |
| 3. Profile | Find a pipeline PID, run the Intel or AMD overview wrapper for 60 seconds, then inspect Grafana and the run directory. [Intel workflow](https://razman786.github.io/wcckit/quick-start/profile-intel/) · [AMD workflow](https://razman786.github.io/wcckit/quick-start/profile-amd/) |

## Collector And Profile Views

<p align="center">
  <img src="docs/images/wcckit-pcm-grafana-flow.svg" alt="Intel PCM live view architecture" width="720">
</p>

Intel PCM metrics can be scraped from the collector stack and viewed in Grafana when the CPU and permissions support PCM counters. These measurements are usually socket, core, memory-controller, or system scoped rather than strictly per-PID.

<p align="center">
  <img src="docs/images/wcckit-amd-uprof-grafana-flow.svg" alt="AMD uProf and e-smi view architecture" width="720">
</p>

AMD hosts use AMD uProf and e-smi paths where available. WCCKIT records unavailable counters clearly, because AMD uProf, e-smi, HSMP, firmware, and kernel support vary by machine.

<p align="center">
  <img src="docs/images/wcckit-flamegraph-readout.svg" alt="WCCKIT flamegraph profile view" width="720">
</p>

CPU flamegraphs are sampled profiles. WCCKIT keeps folded stacks and SVG outputs alongside the Pyroscope view so the interactive dashboard does not replace the reproducible profile artifacts.

## Dashboards

The viewer stack opens with WCCKIT dashboards for different analysis layers:

- [00 WCCKIT Home](https://razman786.github.io/wcckit/dashboards/home/): viewer health, dashboard links, and run guidance.
- [01 WCCKIT Pipeline Overview](https://razman786.github.io/wcckit/dashboards/pipeline-overview/): runtime event counts, hardware CPU activity, memory footprint, BPF I/O events, roofline availability, run timing, and collector status.
- [AMD uProf / AMDuProfPcm Dashboard](https://razman786.github.io/wcckit/dashboards/amd-uprof/): AMD hardware-counter, e-smi, power/energy, memory, and roofline telemetry where available.
- [Intel PCM Dashboard](https://razman786.github.io/wcckit/dashboards/intel-pcm/): Intel PCM scrape health, CPU activity, memory bandwidth, power, and socket/core-level metrics where available.
- [WCCKIT Flamegraphs](https://razman786.github.io/wcckit/dashboards/flamegraphs/): sampled CPU profiles and runtime call-flow profiles through Pyroscope.

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

---

Copyright (c) 2026, Raz. Licensed under the GNU General Public License v2.0. See [`LICENSE`](LICENSE).
