# 01 WCCKIT Pipeline Overview

The Pipeline Overview is the main operational dashboard. It is designed to show whether a profiling run covered the expected time span and whether the major collectors produced data.

## Application Runtime Event Counts

This panel plots event counts from application/runtime collectors. It can include BCC `ustat`, `ucalls`, `uflow` summaries, and syscall fallback summaries depending on what was enabled and supported. Use it to correlate application activity with CPU, memory, and I/O panels over the same x-axis time window.

## Hardware CPU Activity

This panel plots CPU activity from Intel PCM or AMD uProf/e-smi derived records where available. It is best interpreted as host or socket context for the pipeline run, not as a strict per-PID CPU accounting panel.

## Memory Footprint

This panel uses process memory samples, currently from `/proc/<pid>` in the collector. It is intended to show memory footprint over time, such as RSS growth, steady memory use, or abrupt changes during a pipeline phase.

## BPF I/O Events

This panel plots BPF I/O event activity over time. It is useful for correlating disk pressure with pipeline stages, CPU stalls, or memory changes. If it is empty, check BPF permissions and whether the pipeline generated block I/O during the selected time range.

## AMD uProf Roofline Status

This table reports AMD roofline collection status when the roofline wrapper is used. Roofline output is an artifact-oriented path; the HTML report remains under the run directory.

## Run Start/End Timeline

This panel plots start and end markers for each run as two points joined by a thin horizontal line. The y-axis is a lane/counter; duration is read from the x-axis distance between start and end.

## Collector Exit Status

This table lists collector exit codes. Zero means success for that collector path. Non-zero values can mean unavailable, timeout, skipped, unsupported, or failure; inspect `runs/<run_id>/logs/` for the exact reason.

## Disabled: No Data

This usually means one of:

- the time range does not include the run;
- the collector was disabled;
- the tool is unsupported on that CPU/kernel;
- the image was built without the optional vendor package;
- the SSH tunnel or InfluxDB push failed.
