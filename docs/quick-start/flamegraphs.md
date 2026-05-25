# Quick Flamegraph Path

WCCKIT supports sampled CPU flamegraphs and, where the runtime supports it, BCC application call-flow traces.

## Sampled CPU Flamegraphs

Add these options to an overview wrapper:

```bash
--pyroscope-url http://127.0.0.1:14040 --flamegraph --push-profiles
```

Example:

```bash
dockerfiles/bin/run-wcckit-intel-overview.sh \
  --pid "$PID" \
  --pipeline DDFacet \
  --language python \
  --max-duration 60 \
  --influx-url http://127.0.0.1:18086 \
  --pyroscope-url http://127.0.0.1:14040 \
  --flamegraph \
  --push-profiles
```

WCCKIT writes folded stack files and SVG artifacts under `runs/<run_id>/`, and pushes folded profiles to Pyroscope when requested.

## Python Frame Visibility

For Python 3.12 and 3.13 workloads, prefer Python perf-map support:

```bash
python3 -X perf my_pipeline.py
```

This improves Python frame names in Linux `perf` and BCC sampled CPU flamegraphs.

## Validate Before a Real Pipeline

Run the synthetic hotspot:

```bash
examples/profiling/profile_python_hotspot.sh
```

Expected outputs:

```text
profile-output/python-hotspot.svg
profile-output/python-hotspot.log
```

## Interpretation

CPU flamegraphs are sampled profiles. They identify where sampled CPU time was spent, but they do not capture every call. BCC `uflow` is a call-flow stream and is different from sampled CPU profiling; WCCKIT preserves raw `uflow` rows when enabled, but runtime support varies.
