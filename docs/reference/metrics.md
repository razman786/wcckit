# Metrics Reference

WCCKIT writes time-series metrics to InfluxDB and local line protocol files. Measurements are intentionally bounded and summary-oriented.

Common measurements include:

| Measurement | Meaning |
| --- | --- |
| `wcckit_run_marker` | Run start/end markers and dashboard lane values. |
| `wcckit_collector_status` | Collector availability, exit codes, and status. |
| `wcckit_bpf_io_event` / `wcckit_bpf_io_summary` | BPF I/O event and summary data. |
| `wcckit_app_ustat` | Application/runtime activity summary where available. |
| `wcckit_app_ucalls` | Application/runtime call summaries where available. |
| `wcckit_app_uflow_summary` | Bounded uflow summary counts. |
| `wcckit_pcm_cpu` | Intel PCM scrape-derived CPU fields. |
| `wcckit_pcm_memory` | Intel PCM memory fields when present. |
| `wcckit_pcm_power` | Intel PCM power/energy fields when present. |
| `wcckit_amd_uprof_pcm` | Parsed AMD uProf PCM numeric fields. |
| `wcckit_amd_uprof_status` | AMD uProf collector status. |

Metric availability depends on collector options, CPU vendor, host support, permissions, and image build choices.

Avoid treating method names, full paths, stack traces, or command lines as time-series tags. WCCKIT keeps those in raw files instead.
