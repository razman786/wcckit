# Collectors

WCCKIT collectors provide different views of a pipeline run:

- **BPF/perf** for kernel, I/O, syscall, runtime, and sampled CPU profiling.
- **Intel PCM** for Intel hardware counters.
- **AMD uProf / AMDuProfPcm** for AMD CPU telemetry and roofline reports.
- **AMD e-smi** for socket-energy based power data where HSMP support exists.
- **Pyroscope** for interactive profile storage and Grafana flamegraph panels.

Collectors can fail independently. WCCKIT records collector status so one missing hardware-counter path does not invalidate all other telemetry.
