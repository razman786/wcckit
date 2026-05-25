# AMD uProf Collector

AMD uProf provides AMDuProfPcm and roofline tooling for AMD CPUs. WCCKIT treats AMDuProfPcm as the first AMD CPU hardware-counter backend comparable to the Intel PCM role.

## Build-Time Package

AMD uProf is not committed to the repository. Download the `.deb` from AMD, accept AMD's EULA in the browser, and place the package in the repository root or pass it explicitly to the installer.

## AMDuProfPcm

AMDuProfPcm can expose CPU, memory, power, and performance-counter fields depending on CPU, kernel, permissions, and tool version. WCCKIT parses a conservative numeric subset and preserves raw output for later inspection.

## Roofline

WCCKIT exposes AMD roofline through `run-wcckit-amd-roofline.sh`. AMD roofline reports are workload-launch oriented: the tool runs the command and emits an output directory containing an HTML report.

## Limits

AMDuProfPcm CLI flags and output fields may vary by AMD uProf version. WCCKIT parsers are defensive and should not invent values that were not present in the tool output.
