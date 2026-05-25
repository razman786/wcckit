#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

duration=30
pid=""
pipeline="manual-amd-smoke"
influx_url="http://127.0.0.1:18086"
pyroscope_url="http://127.0.0.1:14040"

usage() {
    cat <<'EOF'
Manual AMD uProf/e-smi smoke test for WCCKIT.

This is an opt-in live hardware check. It requires an AMD-capable collector image
and host support for the requested counters. It does not change CPU governors,
disks, filesystems, or opti_disk settings.

Options:
  --pid PID                 Pipeline PID to attach to.
  --duration SECONDS        Maximum collection duration (default: 30).
  --pipeline NAME           Pipeline label (default: manual-amd-smoke).
  --influx-url URL          Collector-side Influx URL (default: http://127.0.0.1:18086).
  --pyroscope-url URL       Collector-side Pyroscope URL (default: http://127.0.0.1:14040).
  -h, --help                Show this help.

Expected result:
  - 01 WCCKIT Pipeline Overview receives hardware/memory points where available.
  - 02 AMD uProf / AMDuProfPcm dashboard reports uProf and e-smi status.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --pid) pid="$2"; shift 2 ;;
        --duration) duration="$2"; shift 2 ;;
        --pipeline) pipeline="$2"; shift 2 ;;
        --influx-url) influx_url="$2"; shift 2 ;;
        --pyroscope-url) pyroscope_url="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

[[ -n "$pid" ]] || { echo "--pid is required for the AMD live smoke test" >&2; exit 2; }

exec dockerfiles/bin/run-wcckit-amd-overview.sh \
    --pid "$pid" \
    --max-duration "$duration" \
    --pipeline "$pipeline" \
    --influx-url "$influx_url" \
    --pyroscope-url "$pyroscope_url" \
    --amd-uprof-memory \
    --amd-uprof-power
