# AMD uProf CLI Tools

AMD uProf is optional because AMD distributes it separately. When included in the WCCKIT collector image, the main first-round tool is `AMDuProfPcm`.

## AMDuProfPcm

AMDuProfPcm is used for AMD CPU hardware telemetry. Depending on version and platform, it can expose CPU, memory, power, and event fields.

Manual check:

```bash
docker run --rm -it --privileged --pid=host --net=host \
  wcckit/pipeline-profiler:24.04 \
  bash -lc 'command -v AMDuProfPcm && AMDuProfPcm --help || true'
```

## Roofline

AMD documents roofline collection with AMDuProfPcm:

```bash
AMDuProfPcm roofline -O /tmp -- /tmp/myapp.exe
```

On Zen 4 and later systems where the kernel does not support the required DF counters, AMD documents an `--msr` mode:

```bash
AMDuProfPcm roofline --msr -O /tmp -- /tmp/myapp.exe
```

WCCKIT wraps this path with:

```bash
dockerfiles/bin/run-wcckit-amd-roofline.sh --help
```

## AMDuProfModelling.py and AMDuProfCLI

Some AMD uProf packages include modelling and CLI tools such as `AMDuProfModelling.py` or `AMDuProfCLI`. Availability depends on the AMD uProf package version and installation layout. WCCKIT documentation treats those as direct AMD tool paths unless a WCCKIT wrapper exists.

## e_smi_tool

`e_smi_tool` can expose socket energy when host HSMP support exists. WCCKIT can use this for derived package watts. It remains socket/system-level telemetry, not per-PID power attribution.

References:

- [AMD uProf](https://www.amd.com/en/developer/uprof.html)
- [AMD uProf User Guide](https://docs.amd.com/r/en-US/57368-uProf-user-guide/uProf-User-Guide)
- [Classic Roofline Model](https://docs.amd.com/r/en-US/57368-uProf-user-guide/Classic-Roofline-Model)
- [AMD Lab Notes profilers](https://github.com/amd/amd-lab-notes/tree/release/profilers)
- [AMD HSMP](https://github.com/amd/amd_hsmp)
- [AMD e-smi package](https://download.amd.com/developer/eula/e-smi/e-smi-tool-5.2.1.deb)
