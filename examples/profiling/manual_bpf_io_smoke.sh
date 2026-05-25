#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

duration=20
pid=""
pipeline="manual-bpf-io-smoke"
influx_url="http://127.0.0.1:18086"

usage() {
    cat <<'EOF'
Manual BPF I/O smoke test for WCCKIT.

This is an opt-in live profiler check. It requires privileged Docker/BPF access.
It does not run opti_disk and does not modify disks or CPU settings.

Options:
  --pid PID                 Pipeline PID to attach to.
  --duration SECONDS        Maximum collection duration (default: 20).
  --pipeline NAME           Pipeline label (default: manual-bpf-io-smoke).
  --influx-url URL          Collector-side Influx URL (default: http://127.0.0.1:18086).
  -h, --help                Show this help.

Expected result:
  - runs/<run_id>/events/bpf-io.jsonl is written.
  - BPF I/O Events panel receives points.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --pid) pid="$2"; shift 2 ;;
        --duration) duration="$2"; shift 2 ;;
        --pipeline) pipeline="$2"; shift 2 ;;
        --influx-url) influx_url="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

[[ -n "$pid" ]] || { echo "--pid is required for the BPF I/O live smoke test" >&2; exit 2; }

exec dockerfiles/bin/run-wcckit-pipeline-overview.sh \
    --pid "$pid" \
    --max-duration "$duration" \
    --pipeline "$pipeline" \
    --language python \
    --hardware-counters none \
    --no-app-stat \
    --no-app-calls \
    --no-app-flow-summary \
    --no-flamegraph \
    --influx-url "$influx_url"
