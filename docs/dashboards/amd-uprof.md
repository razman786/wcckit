# 02 AMD uProf / AMDuProfPcm Dashboard

The AMD dashboard is for AMD hosts where AMDuProfPcm and optionally e-smi can collect hardware telemetry.

Panels:

- **CPU Utilisation**: utilisation-like fields parsed from AMDuProfPcm output when present.
- **Effective Frequency**: frequency fields such as effective GHz when available.
- **IPC And CPI**: instruction-per-cycle or cycle-per-instruction fields where AMDuProfPcm exposes them.
- **Instruction Throughput**: instruction count or rate fields when parsed.
- **User/System Execution Split**: user/system execution fields when available.
- **Branch Activity**: branch-related fields when parsed.
- **Memory Bandwidth**: memory read/write bandwidth fields when available.
- **Power**: AMDuProfPcm power fields or e-smi derived package watts from socket-energy deltas.
- **Socket Energy**: cumulative socket energy from `e_smi_tool` where host support exists.
- **Samples Parsed** and **Numeric Fields Parsed**: parser coverage counters.
- **Collector Exit Code** and **Collector Status Detail**: availability and failure information.

## Requirements

AMDuProfPcm requires AMD uProf in the collector image. e-smi requires the e-smi tool and host AMD HSMP support. HSMP is a host kernel/firmware capability; WCCKIT does not install or load host kernel modules from inside the container.

## Common Empty States

- AMD uProf `.deb` was not included in the collector build.
- The host CPU or firmware does not expose the required counters.
- HSMP/e-smi support is missing or the module is not loaded.
- The collector ran without `--amd-uprof-memory` or `--amd-uprof-power` for those optional paths.
- The selected Grafana time range does not include the run.

## Roofline

AMD roofline reports are generated separately with `run-wcckit-amd-roofline.sh`. The canonical output is the AMD HTML report under the run directory, with status exported to Grafana.

References:

- [AMD uProf](https://www.amd.com/en/developer/uprof.html)
- [AMD uProf User Guide](https://docs.amd.com/r/en-US/57368-uProf-user-guide/uProf-User-Guide)
- [AMD Classic Roofline Model](https://docs.amd.com/r/en-US/57368-uProf-user-guide/Classic-Roofline-Model)
- [AMD HSMP](https://github.com/amd/amd_hsmp)
