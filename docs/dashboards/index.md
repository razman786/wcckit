# Dashboards

The viewer stack provisions these dashboards:

1. **00 WCCKIT Home**
2. **01 WCCKIT Pipeline Overview**
3. **02 AMD uProf / AMDuProfPcm Dashboard**
4. **03 Intel Performance Counter Monitor Dashboard**
5. **04 WCCKIT Flamegraphs**

Start with the Pipeline Overview. It shows whether the run produced application events, hardware samples, memory samples, BPF I/O events, run start/end markers, and collector status. Then open the CPU-vendor-specific dashboard.

`Disabled: No data` means the selected time range has no matching points for that panel. It can be normal when a collector was disabled, unsupported on the host, or not available in the image.
