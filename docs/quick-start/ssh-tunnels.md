# SSH Tunnels

Most researchers run Grafana on a laptop or desktop and the collector on a compute node. WCCKIT uses SSH reverse tunnels so the compute-node collector can write to services that are actually running on the laptop.

Run this on the laptop, where the viewer stack is already running:

```bash
dockerfiles/bin/run-wcckit-ssh-tunnel.sh <user>@<compute-node>
```

Keep the SSH session open while collecting.

## What Gets Forwarded

After the tunnel is open, the compute node can use:

```text
InfluxDB:  http://127.0.0.1:18086
Pyroscope: http://127.0.0.1:14040
```

Use these URLs in the collector command:

```bash
--influx-url http://127.0.0.1:18086
--pyroscope-url http://127.0.0.1:14040
```

## Intel PCM Sensor Forward

The Intel dashboard can scrape a live `pcm-sensor-server`. For Intel nodes, start the tunnel with:

```bash
dockerfiles/bin/run-wcckit-ssh-tunnel.sh --pcm-sensor <user>@<compute-node>
```

The wrapper prints a `WCCKIT_PCM_SENSOR_URL=...` value when the PCM sensor forward is enabled. If necessary, use that value for the viewer-side PCM bridge.

## Common Connection Refused Cases

- The viewer stack is not running on the laptop.
- The SSH tunnel was closed.
- The collector is using `http://127.0.0.1:8086` on the compute node instead of the reverse-tunnel port `18086`.
- Intel `pcm-sensor-server` was not started on the compute node.
- The PCM forward is bound to the wrong laptop-side address for Docker to scrape.

The debug wrapper can check the common paths from the collector side:

```bash
dockerfiles/bin/run-wcckit-debug-connection.sh \
  --influx-url http://127.0.0.1:18086 \
  --pyroscope-url http://127.0.0.1:14040
```
