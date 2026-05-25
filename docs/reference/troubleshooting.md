# Troubleshooting

## Grafana Shows No Data

Check the selected time range first. Then confirm the collector pushed to InfluxDB:

```bash
dockerfiles/bin/run-wcckit-debug-connection.sh \
  --influx-url http://127.0.0.1:18086 \
  --pyroscope-url http://127.0.0.1:14040
```

Inspect `runs/<run_id>/logs/` and `runs/<run_id>/metrics/influx.lp`.

## Disabled: No Data

This means the panel query returned no points in the selected time range. It can be expected if a collector was disabled, unsupported, unavailable, or not built into the image.

## SSH Tunnel Connection Refused

The viewer stack may not be running, the SSH tunnel may have closed, or the collector may be using the wrong port. From the compute node, use `http://127.0.0.1:18086` for InfluxDB and `http://127.0.0.1:14040` for Pyroscope when using the default tunnel.

## Intel PCM Endpoint Not Available

Start the tunnel with `--pcm-sensor`. Confirm `pcm-sensor-server` is listening on the compute node. Query with:

```bash
curl -H 'Accept: application/json' http://127.0.0.1:9738/persecond/
```

A 406 response means the server is reachable but needs an accepted content type.

## AMD uProf Unavailable

Confirm the AMD uProf `.deb` was included at collector build time and that `AMDuProfPcm` exists in the image. If absent, rebuild with a local package or explicit `--amd-uprof-deb`.

## e-smi or HSMP Unavailable

Confirm host AMD HSMP support. WCCKIT does not install or load host kernel modules from inside Docker. Check with the compute node administrator if `hsmp_acpi` or `amd_hsmp` should be loaded.

## BPF Permission Errors

The collector must run privileged with host PID namespace and the relevant debug/tracing filesystems mounted. Use the WCCKIT wrappers rather than a plain `docker run` unless testing manually.

## No CPU Flamegraph Samples

The process may have exited, the duration may have been too short, symbols may be missing, or the profile path may not have been enabled. For Python, run the workload with `python3 -X perf` where supported.

## uflow Unavailable

BCC language uflow support depends on runtime probes and build flags. Use sampled CPU flamegraphs first for runtimes where uflow is not available.

## Collector Exit 124

Exit status 124 usually indicates a timeout cap was reached. This can be normal when `--max-duration` stops a collector while the pipeline continues.

## Docker Permission Problems

Add the user to the Docker group and start a new group session:

```bash
sudo usermod -aG docker "$USER"
newgrp docker
```
