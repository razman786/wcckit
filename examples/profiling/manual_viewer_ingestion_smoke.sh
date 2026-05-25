#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

influx_url="http://127.0.0.1:8086"
pyroscope_url="http://127.0.0.1:4040"
org="wcckit"
bucket="wcckit"
token="wcckit-dev-token"

usage() {
    cat <<'EOF'
Manual viewer ingestion smoke test for WCCKIT.

This checks local viewer endpoints and writes one synthetic non-hardware point to
InfluxDB. It does not run profilers and does not require privileged Docker.

Options:
  --influx-url URL          InfluxDB URL (default: http://127.0.0.1:8086).
  --pyroscope-url URL       Pyroscope URL (default: http://127.0.0.1:4040).
  --org ORG                 InfluxDB org (default: wcckit).
  --bucket BUCKET           InfluxDB bucket (default: wcckit).
  --token TOKEN             InfluxDB token (default: wcckit-dev-token).
  -h, --help                Show this help.

Expected result:
  - InfluxDB /health is reachable.
  - Pyroscope /ready is reachable.
  - InfluxDB accepts one wcckit_viewer_smoke line protocol point.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --influx-url) influx_url="$2"; shift 2 ;;
        --pyroscope-url) pyroscope_url="$2"; shift 2 ;;
        --org) org="$2"; shift 2 ;;
        --bucket) bucket="$2"; shift 2 ;;
        --token) token="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

curl -fsS "${influx_url%/}/health" >/dev/null
curl -fsS "${pyroscope_url%/}/ready" >/dev/null
line="wcckit_viewer_smoke,run_id=manual-viewer,tool=viewer-smoke available=true,value=1i $(date +%s%N)"
curl -fsS -X POST "${influx_url%/}/api/v2/write?org=${org}&bucket=${bucket}&precision=ns" \
    -H "Authorization: Token ${token}" \
    --data-binary "$line" >/dev/null
printf 'Viewer ingestion smoke point written to bucket %s.\n' "$bucket"
