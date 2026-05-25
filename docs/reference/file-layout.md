# File Layout

Important repository areas:

```text
dockerfiles/                 Dockerfiles, wrappers, viewer stack, collector scripts
docs/                        GitHub Pages documentation and visual assets
examples/profiling/          Small profiling smoke-test workloads
opti_disk/                   Destructive-capable disk/NVMe/fio subset
tests/fixtures/              Parser fixtures used by CI
.github/workflows/           CI and documentation deployment workflows
```

Important run output areas:

```text
runs/<run_id>/manifest.json
runs/<run_id>/events/
runs/<run_id>/metrics/
runs/<run_id>/profiles/
runs/<run_id>/flamegraphs/
runs/<run_id>/logs/
runs/<run_id>/roofline/
```
