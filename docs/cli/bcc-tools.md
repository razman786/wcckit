# BCC and eBPF CLI Tools

The WCCKIT images include BCC tooling and a BCC source checkout for helper scripts.

## CPU Sampling

BCC `profile.py` samples CPU stacks:

```bash
dockerfiles/bin/run-wcckit-profiler.sh --out ./profile-output -- \
  wcckit_profile_cpu.sh --pid "$PID" --duration 30 --frequency 99 --output /out/cpu.svg
```

This path produces a static SVG. The pipeline profiler can also push folded profiles to Pyroscope.

## I/O Tools

BCC tools such as `biolatency`, `biosnoop`, and `biotop` are useful for manual block I/O diagnosis. WCCKIT's BPF I/O collector focuses on writing parseable events and summaries for the Pipeline Overview.

## Runtime Wrappers

BCC provides language wrappers such as:

```text
pythonflow.sh
pythoncalls.sh
pythonstat.sh
```

and equivalents for some other runtimes. Support depends on runtime probes, USDT availability, permissions, and the language implementation. WCCKIT records failures instead of hiding them.

Reference: [iovisor/bcc](https://github.com/iovisor/bcc)
