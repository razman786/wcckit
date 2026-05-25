# Profile an Intel Pipeline

Use this path on an Intel compute node. It populates the WCCKIT Pipeline Overview and the Intel PCM dashboard.

## On the Laptop

Start the viewer:

```bash
dockerfiles/bin/run-wcckit-viewer.sh up
```

Start the SSH tunnel with PCM sensor support:

```bash
dockerfiles/bin/run-wcckit-ssh-tunnel.sh --pcm-sensor <user>@<compute-node>
```

## On the Compute Node

Find the pipeline PID:

```bash
pgrep -af DDFacet
PID=$(pgrep -n -f DDFacet)
```

Run a 60 second capture:

```bash
dockerfiles/bin/run-wcckit-intel-overview.sh \
  --pid "$PID" \
  --pipeline DDFacet \
  --language python \
  --max-duration 60 \
  --influx-url http://127.0.0.1:18086
```

Or let WCCKIT select the newest matching process:

```bash
dockerfiles/bin/run-wcckit-intel-overview.sh \
  --match DDFacet \
  --pipeline DDFacet \
  --language python \
  --max-duration 60 \
  --influx-url http://127.0.0.1:18086
```

## Optional Flamegraph

Enable CPU flamegraphs only when you want stack context:

```bash
dockerfiles/bin/run-wcckit-intel-overview.sh \
  --pid "$PID" \
  --pipeline DDFacet \
  --language python \
  --max-duration 60 \
  --influx-url http://127.0.0.1:18086 \
  --pyroscope-url http://127.0.0.1:14040 \
  --flamegraph \
  --push-profiles
```

CPU flamegraphs are sampled. They show sampled CPU time, not every function call.

## Dashboards to Check

- **01 WCCKIT Pipeline Overview** for the overall run.
- **03 Intel Performance Counter Monitor Dashboard** for Intel PCM telemetry.
- **04 WCCKIT Flamegraphs** if `--flamegraph --push-profiles` was used.
