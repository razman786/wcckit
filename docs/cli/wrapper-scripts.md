# WCCKIT Wrapper Scripts

## Installation

```bash
dockerfiles/bin/install-wcckit-profiler-ubuntu2404.sh --viewer-only
dockerfiles/bin/install-wcckit-profiler-ubuntu2404.sh --collector-only
```

## Viewer

```bash
dockerfiles/bin/run-wcckit-viewer.sh up
dockerfiles/bin/run-wcckit-viewer.sh status
dockerfiles/bin/run-wcckit-viewer.sh logs
dockerfiles/bin/run-wcckit-viewer.sh stop
```

## SSH Tunnel

```bash
dockerfiles/bin/run-wcckit-ssh-tunnel.sh <user>@<compute-node>
dockerfiles/bin/run-wcckit-ssh-tunnel.sh --pcm-sensor <user>@<intel-compute-node>
```

## Overview Collectors

```bash
dockerfiles/bin/run-wcckit-intel-overview.sh --pid "$PID" --pipeline DDFacet --max-duration 60
dockerfiles/bin/run-wcckit-amd-overview.sh --pid "$PID" --pipeline DDFacet --max-duration 60
```

## General Profiler

```bash
dockerfiles/bin/run-wcckit-pipeline-profiler.sh --pid "$PID" --duration 120 --pipeline DDFacet
```

## Standalone CPU Profiler

```bash
dockerfiles/bin/run-wcckit-profiler.sh --out ./profile-output -- \
  wcckit_profile_cpu.sh --pid "$PID" --duration 30 --output /out/cpu.svg
```

## AMD Roofline

```bash
dockerfiles/bin/run-wcckit-amd-roofline.sh --help
```
