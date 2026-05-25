# Collector Role

The collector role runs on the compute node beside the pipeline process. It attaches to a host PID and starts selected collectors inside a privileged Docker container.

The main host wrapper is:

```bash
dockerfiles/bin/run-wcckit-pipeline-profiler.sh --help
```

The researcher-facing overview wrapper is:

```bash
dockerfiles/bin/run-wcckit-pipeline-overview.sh --help
```

Vendor-specific convenience wrappers are:

```bash
dockerfiles/bin/run-wcckit-intel-overview.sh --help
dockerfiles/bin/run-wcckit-amd-overview.sh --help
```

## What the Collector Starts

Depending on options and CPU vendor, the collector can start:

- Intel PCM telemetry.
- AMD uProf / AMDuProfPcm telemetry.
- AMD e-smi socket-energy sampling.
- BPF I/O tracing.
- process memory sampling from `/proc/<pid>`.
- application runtime summaries where BCC language tools are available.
- sampled CPU flamegraph collection when `--flamegraph` is enabled.
- Pyroscope push when `--push-profiles` and `--pyroscope-url` are supplied.

## Duration Modes

The overview wrapper normally collects until the target PID exits or until `--max-duration` is reached. Use a 60 second safety window for initial validation:

```bash
--max-duration 60
```

The lower-level profiler wrapper supports explicit duration and until-exit modes:

```bash
--duration 120
--until-exit
```

Press `Ctrl-C` once to stop early. The wrapper traps shutdown, stops child collectors, writes logs/status, and pushes the line protocol collected so far.
