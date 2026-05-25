# 04 WCCKIT Flamegraphs

The Flamegraphs dashboard uses Grafana's Pyroscope datasource for interactive profile views.

Panels:

- **CPU Sampled Flame Graph**: sampled CPU stack profile pushed from folded stack artifacts.
- **Profile Interpretation Notes**: reminders about sampled CPU profiles and uflow traces.
- **Application uflow Entry Call Tree**: reconstructed call-flow tree where BCC `uflow` data is available.
- **Profile Push Status**: whether WCCKIT pushed profile data to Pyroscope.
- **uflow Event Preservation Summary**: counts of parsed and unparsed uflow rows.

## CPU Flamegraphs

CPU flamegraphs are sampled. They show where sampled CPU time was spent, which is useful for finding hot functions, expensive loops, missing native symbols, and runtime overhead. They do not show every function call.

## uflow

`uflow` is a runtime call-flow stream exposed by BCC language wrappers where supported. WCCKIT preserves raw uflow rows and writes parsed JSONL/folded artifacts. If a row cannot be parsed, it should be preserved as an unparsed record rather than silently discarded.

## Artifacts

Look under:

```text
runs/<run_id>/profiles/
runs/<run_id>/flamegraphs/
runs/<run_id>/events/
```

Pyroscope is an interactive viewer; the local files remain the reproducible record.
