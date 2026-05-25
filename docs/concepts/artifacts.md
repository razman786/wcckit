# Artifacts

Each WCCKIT run writes a directory under `runs/<run_id>/`.

```text
runs/<run_id>/
  manifest.json
  events/
  metrics/
  profiles/
  flamegraphs/
  logs/
  roofline/
```

## `manifest.json`

The manifest records provenance: host, PID, pipeline name, collection settings, selected hardware counter backend, tool availability, and run metadata. It is the first file to inspect when comparing runs.

## `events/`

Event files are JSONL, CSV, or raw logs derived from collectors. Examples include BPF I/O events, application runtime summaries, AMD uProf PCM rows, uflow rows, and memory samples. JSONL keeps one event per line so large files can be streamed by later tools.

## `metrics/`

The `metrics/` directory contains Influx line protocol such as `influx.lp`. This is what WCCKIT pushes to InfluxDB when `--influx-url` is supplied.

## `profiles/` and `flamegraphs/`

Folded stack files live under `profiles/`; static SVG flamegraphs live under `flamegraphs/`. Pyroscope receives folded data when profile pushing is enabled, but the local files remain the reproducible record.

## `logs/`

Collector logs and status files live under `logs/`. Use these when a dashboard shows `Disabled: No data` or a collector exit status is non-zero.
