# Docker Images

WCCKIT uses several local images:

| Image | Purpose |
| --- | --- |
| `wcckit/ubuntu-profiling-base:24.04` | Ubuntu 24.04 base with Linux profiling tools. |
| `wcckit/bcc-profiler:24.04` | BCC/eBPF CPU profiling and FlameGraph support. |
| `wcckit/pipeline-profiler:24.04` | Combined collector image for BPF, PCM, AMD uProf, e-smi, perf, and WCCKIT scripts. |

The viewer stack uses upstream Docker images for Grafana, InfluxDB, and Pyroscope through Docker Compose.

Build only the role needed on a given machine:

```bash
dockerfiles/bin/install-wcckit-profiler-ubuntu2404.sh --viewer-only
dockerfiles/bin/install-wcckit-profiler-ubuntu2404.sh --collector-only
```
