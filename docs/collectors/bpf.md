# BPF and perf Collectors

BCC/eBPF tools give WCCKIT kernel and runtime visibility. They require privileged host access and kernel support.

## CPU Profiling

WCCKIT uses BCC `profile.py` or packaged perf tooling to produce sampled CPU stack profiles. These profiles are folded, converted to SVG flamegraphs, and optionally pushed to Pyroscope.

## I/O Tracing

The BPF I/O path records block I/O event activity so the Pipeline Overview can correlate I/O pressure with memory footprint, CPU activity, and run timing.

## Runtime Tools

BCC language wrappers such as `pythonflow.sh`, `pythoncalls.sh`, and `pythonstat.sh` can expose runtime call-flow or call-summary data where supported. Runtime support varies by language, interpreter build, USDT support, and kernel/BPF permissions.

## Python Notes

For Python 3.12 and 3.13, use `python3 -X perf` when launching a workload if you want better Python frame names in sampled CPU profiles.
