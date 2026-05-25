# Manual Hardware Tests

Normal CI deliberately avoids live profilers, privileged tracing, real hardware counters, and any opti_disk operation. The scripts in `examples/profiling/` are opt-in checks for a prepared compute node after the viewer stack and SSH tunnel are already running.

These scripts do not format disks, change CPU governors, drop caches, or run opti_disk. They may still require privileged Docker access because BPF, perf, Intel PCM, and AMD uProf observe the host kernel and hardware counters.

## Viewer Ingestion

Use this on the laptop or desktop where the viewer stack is running:

```bash
examples/profiling/manual_viewer_ingestion_smoke.sh
```

It checks InfluxDB and Pyroscope health endpoints and writes one synthetic `wcckit_viewer_smoke` point. This confirms the viewer can accept data before involving a compute node.

## Intel PCM

On an Intel compute node, first ensure the SSH tunnel is running. Then either start `pcm-sensor-server` manually or use the WCCKIT collector path that starts it.

```bash
examples/profiling/manual_intel_pcm_smoke.sh --pid <pipeline-pid> --duration 30
```

Expected result: the Pipeline Overview receives hardware activity and the Intel PCM dashboard receives PCM scrape data. If no data appears, test the endpoint directly:

```bash
curl -H 'Accept: application/json' http://127.0.0.1:9738/persecond/
```

A `406 Not Acceptable` response means the server is alive but the client did not request a supported content type.

## AMD uProf and e-smi

On an AMD compute node with an AMD-enabled collector image:

```bash
examples/profiling/manual_amd_uprof_smoke.sh --pid <pipeline-pid> --duration 30
```

Expected result: the Pipeline Overview receives hardware and memory points where available, and the AMD dashboard reports AMDuProfPcm and e-smi status. e-smi energy data depends on host HSMP support; WCCKIT does not load host kernel modules from inside Docker.

## BPF I/O

To validate BPF I/O tracing independently of hardware counters:

```bash
examples/profiling/manual_bpf_io_smoke.sh --pid <pipeline-pid> --duration 20
```

Expected result: `events/bpf-io.jsonl` is written under the run directory and the BPF I/O Events panel receives points. This requires privileged BPF access and a kernel/BCC combination that supports the selected tool.

## CPU Flamegraph

To validate sampled CPU flamegraph generation with the included Python hotspot workload:

```bash
examples/profiling/manual_cpu_flamegraph_smoke.sh --duration 20 --push-profiles
```

Expected result: folded stack and SVG artifacts are written locally, and Pyroscope receives a profile when `--push-profiles` is used. CPU flamegraphs are sampled profiles; they do not claim to capture every function call.

## Application Runtime Tools

`uflow`, `ucalls`, and `ustat` depend on runtime support and probe availability. If they are unavailable, WCCKIT should record an unavailable collector status rather than failing the whole run. Treat these as runtime-specific checks and preserve the raw logs for analysis.
