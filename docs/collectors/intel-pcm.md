# Intel PCM Collector

Intel PCM provides hardware telemetry for Intel CPUs. WCCKIT uses PCM directly in the collector and also supports a live `pcm-sensor-server` path for the Intel Grafana dashboard.

## What It Contributes

- CPU activity and frequency fields where exposed.
- Memory bandwidth fields from memory-controller counters.
- Power and energy fields on supported platforms.
- PCIe/I/O oriented fields where available.
- Scrape health and collector status.

## Limits

PCM counters are generally system, socket, core, memory-controller, or PCIe scoped. They are not automatically per-PID. Interpret PCM data as hardware context during the pipeline run and combine it with BPF/perf for PID-specific evidence.

## Sensor Server

The live dashboard path expects `pcm-sensor-server` on the compute node and an SSH forward back to the laptop viewer. If the endpoint is reachable but returns 406, query it with an `Accept` header.
