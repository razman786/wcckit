# Architecture

WCCKIT separates the profiling system into three layers.

## Viewer Layer

The viewer layer runs Grafana, InfluxDB, and Pyroscope. It normally lives on a laptop or desktop. This keeps Grafana off the compute node and lets the researcher inspect results in a browser without installing Grafana natively.

## Collector Layer

The collector layer runs on the compute node in a privileged Docker container. It needs host visibility for BPF, perf, Intel PCM, AMD uProf, and process memory sampling. It attaches to a PID and writes both local artifacts and time-series data.

## Artifact Layer

Every run writes `runs/<run_id>/`. Grafana is useful for live analysis, but the run directory is the reproducible record. That is where WCCKIT keeps manifests, raw logs, JSONL event streams, folded stacks, SVG flamegraphs, roofline outputs, and line protocol.

## Why Split Viewer and Collector?

Radio-astronomy pipelines often run on shared or remote compute nodes. Those nodes may allow Docker collection but should not need a native Grafana installation. SSH reverse tunnels let the collector send data to the researcher's local viewer stack without exposing databases directly on the network.
