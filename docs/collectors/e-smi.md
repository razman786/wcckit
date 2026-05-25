# AMD e-smi Collector

AMD e-smi can expose socket energy on supported AMD platforms. WCCKIT uses it to derive package watts from energy deltas when `--amd-uprof-power` is enabled and e-smi is available.

## Host Requirements

The e-smi tool alone is not enough. The compute node needs compatible AMD CPU/firmware support and a working host HSMP path, commonly through `hsmp_acpi` or `amd_hsmp` depending on kernel/platform.

WCCKIT does not install or load host kernel modules from inside the collector container.

## Build Behaviour

Normal collector builds download AMD e-smi from AMD's public `.deb` URL unless `--no-amd-esmi` is specified. CI-style and offline builds can disable it.

## Interpretation

Socket energy is not per-PID. It is useful for understanding host/socket power behaviour during a pipeline window. Combine it with run markers and BPF/perf data to understand timing and attribution.
