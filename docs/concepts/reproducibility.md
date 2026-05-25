# Reproducibility

WCCKIT is designed around repeatable characterisation rather than one-off benchmarking.

A useful run should answer:

- Which pipeline was profiled?
- Which PID and command window were observed?
- Which collector options were enabled?
- Which CPU vendor and hardware counter backend were selected?
- Which tools were available or unavailable?
- Which raw files support the dashboard view?
- Did any collector fail, timeout, or report no data?

## Compare Runs Carefully

Hardware counter availability, CPU frequency behaviour, kernel version, container privileges, BPF support, and pipeline input size all affect results. WCCKIT records these where practical, but interpretation still requires care.

## Avoid Unsupported Claims

Do not claim a setting improves performance unless it has been measured on a representative workload. WCCKIT helps collect the evidence; it does not make performance claims by itself.

## Test Coverage

The repository test suite covers parser behaviour, dashboard semantics, viewer-stack provisioning, pipeline coordinator runs with live collectors disabled, and opti_disk dry-run safety checks. These tests are deliberately non-destructive and do not require root, real hardware counters, live BPF tracing, or mounted profiling filesystems.

Manual smoke scripts under `examples/profiling/` cover the remaining hardware-dependent paths: Intel PCM, AMD uProf/e-smi, BPF I/O, CPU flamegraphs, and viewer ingestion. Those checks should be run on representative compute nodes when validating a deployment.

When a manual hardware run exposes a new tool output format, promote a small redacted sample with `scripts/collect_fixture_from_run.py` and expand the parser tests. This keeps the compatibility corpus tied to real Intel, AMD, BPF, and application-runtime outputs without committing full run directories.
