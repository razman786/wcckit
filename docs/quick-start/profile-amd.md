# Profile an AMD Pipeline

Use this path on an AMD compute node. It populates the WCCKIT Pipeline Overview and, where host support is available, the AMD uProf dashboard.

## Build With AMD Tools

For AMDuProfPcm support, place the AMD uProf `.deb` in the repository root before building the collector, or pass `--amd-uprof-deb` explicitly. AMD e-smi is downloaded into normal collector images by default unless `--no-amd-esmi` is used.

## On the Laptop

Start the viewer and tunnel:

```bash
dockerfiles/bin/run-wcckit-viewer.sh up
dockerfiles/bin/run-wcckit-ssh-tunnel.sh <user>@<compute-node>
```

## On the Compute Node

Find the pipeline PID:

```bash
pgrep -af DDFacet
PID=$(pgrep -n -f DDFacet)
```

Run a 60 second capture:

```bash
dockerfiles/bin/run-wcckit-amd-overview.sh \
  --pid "$PID" \
  --pipeline DDFacet \
  --language python \
  --max-duration 60 \
  --influx-url http://127.0.0.1:18086 \
  --amd-uprof-memory \
  --amd-uprof-power
```

Or use process matching:

```bash
dockerfiles/bin/run-wcckit-amd-overview.sh \
  --match DDFacet \
  --pipeline DDFacet \
  --language python \
  --max-duration 60 \
  --influx-url http://127.0.0.1:18086 \
  --amd-uprof-memory \
  --amd-uprof-power
```

## Optional Flamegraph

```bash
dockerfiles/bin/run-wcckit-amd-overview.sh \
  --pid "$PID" \
  --pipeline DDFacet \
  --language python \
  --max-duration 60 \
  --influx-url http://127.0.0.1:18086 \
  --pyroscope-url http://127.0.0.1:14040 \
  --amd-uprof-memory \
  --amd-uprof-power \
  --flamegraph \
  --push-profiles
```

## Dashboard Notes

AMD counters are conditional. If the AMD dashboard shows `Disabled: No data`, check whether AMDuProfPcm is installed in the collector image and whether the host exposes the required AMD HSMP/e-smi interfaces.
