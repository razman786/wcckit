# Intel PCM CLI Tools

The pipeline collector image installs Intel PCM from Ubuntu packages. Useful tools include:

| Tool | Use |
| --- | --- |
| `pcm` | General CPU and memory performance counters. |
| `pcm-memory` | Memory bandwidth and memory-controller oriented metrics. |
| `pcm-power` | Power/energy fields where hardware supports them. |
| `pcm-pcie` | PCIe and I/O related counters where available. |
| `pcm-sensor` | Sensor-style PCM output. |
| `pcm-sensor-server` | HTTP server used by the live Intel Grafana path. |

Some Intel PCM packages may include additional tools such as `pcm-iio` or `pcm-numa`; availability depends on the packaged version.

## Run PCM Manually

```bash
docker run --rm -it --privileged --pid=host --net=host \
  wcckit/pipeline-profiler:24.04 \
  bash -lc 'pcm 1'
```

Memory bandwidth:

```bash
docker run --rm -it --privileged --pid=host --net=host \
  wcckit/pipeline-profiler:24.04 \
  bash -lc 'pcm-memory 1'
```

Sensor server:

```bash
docker run --rm -it --privileged --pid=host --net=host \
  wcckit/pipeline-profiler:24.04 \
  bash -lc 'pcm-sensor-server -p 9738'
```

Query:

```bash
curl -H 'Accept: application/json' http://127.0.0.1:9738/persecond/
```

## Limitations

PCM is hardware-level telemetry. It is useful for CPU/socket/memory/PCIe context but should not be treated as a strict per-PID profiler. Use BPF/perf for process attribution.

References:

- [Intel PCM](https://github.com/intel/pcm)
- [Intel PCM Grafana scripts](https://github.com/intel/pcm/tree/master/scripts/grafana)
