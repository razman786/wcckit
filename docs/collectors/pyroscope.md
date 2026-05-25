# Pyroscope Collector Path

Pyroscope stores folded profile data so Grafana can display interactive flamegraphs.

WCCKIT pushes profiles when these conditions are met:

- `--pyroscope-url` is supplied;
- profile artifacts exist;
- `--push-profiles` is set;
- Pyroscope is reachable through the viewer stack or SSH tunnel.

Example:

```bash
--pyroscope-url http://127.0.0.1:14040 --flamegraph --push-profiles
```

Pyroscope does not replace local artifacts. It is a viewer/indexing path for interactive flamegraph panels. The folded stack and SVG files remain under `runs/<run_id>/`.
