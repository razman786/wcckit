# 03 Intel PCM Dashboard

The Intel dashboard is for Intel hosts where Intel PCM can collect hardware telemetry.

Panels:

- **PCM Sensor Telemetry**: time-series values scraped from `pcm-sensor-server`.
- **PCM Power / Energy**: power or energy fields when PCM exposes them.
- **PCM Memory Bandwidth**: memory read/write bandwidth fields when available.
- **PCM PCIe / I/O**: PCIe or I/O-oriented PCM fields when available.
- **WCCKIT PCM Scrape Health**: whether WCCKIT scraped PCM data successfully.
- **PCM Collector Exit Status**: collector status rows for the PCM path.

## Manual PCM Sensor Test

On the compute node, start the PCM sensor server inside the collector image if needed:

```bash
docker run --rm -it --privileged --pid=host --net=host \
  wcckit/pipeline-profiler:24.04 \
  bash -lc 'pcm-sensor-server -p 9738'
```

From the same host, query it with an acceptable content type:

```bash
curl -H 'Accept: application/json' http://127.0.0.1:9738/persecond/
```

A `406 Not Acceptable` response means the server is reachable but the request did not include an accepted `Accept` header.

## Interpretation

Intel PCM counters are generally core, socket, memory-controller, PCIe, or system level. They are useful for understanding the hardware environment during the pipeline run. Use BPF/perf panels for stronger PID attribution.

Reference: [Intel PCM](https://github.com/intel/pcm) and the [Intel PCM Grafana scripts](https://github.com/intel/pcm/tree/master/scripts/grafana).
