# Telemetry Model

WCCKIT collects complementary views of the same run. No single tool answers every performance question.

| Source | What It Shows | Notes |
| --- | --- | --- |
| Intel PCM | CPU, memory, power, PCIe telemetry on Intel hosts | Usually socket/core/system level, not strictly per-PID. |
| AMD uProf / AMDuProfPcm | AMD CPU counters, memory and roofline where available | Requires AMD package and host support. |
| AMD e-smi | Socket energy and derived package power | Depends on host HSMP/e-smi support. |
| BCC/eBPF | Kernel, block I/O, scheduler and runtime probes | Requires privileged host access. |
| perf/BCC profile.py | Sampled CPU stack profiles | Good for PID attribution and flamegraphs. |
| `/proc/<pid>` | Process memory footprint | Low dependency path for RSS/virtual-memory trends. |
| InfluxDB | Time-series summaries | Avoids unbounded raw event/cardinality loads. |
| Pyroscope | Interactive profiles | Stores folded stack profiles for Grafana flamegraph panels. |

## Raw Versus Summary Data

WCCKIT keeps dense raw data on disk. It exports bounded summaries and status points to InfluxDB. This avoids putting full stack traces, arbitrary paths, unbounded method names, or raw event streams directly into time-series tags.

## PID Attribution

BPF and sampled CPU profiling are stronger for PID attribution. Hardware counters from Intel PCM and AMD tools are often system, socket, or core scoped. They are still useful for understanding resource pressure during the pipeline window, but they should not be interpreted as purely per-process counters unless the tool explicitly supports that mode.
