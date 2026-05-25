#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

duration=30
pid=""
pipeline="manual-intel-smoke"
influx_url="http://127.0.0.1:18086"
pyroscope_url="http://127.0.0.1:14040"

usage() {
    cat <<'EOF'
Manual Intel PCM smoke test for WCCKIT.

This is an opt-in live hardware check. It runs the collector wrappers against a
real host and may require privileged Docker access, but it does not change CPU
governors, disks, filesystems, or opti_disk settings.

Options:
  --pid PID                 Pipeline PID to attach to. If omitted, only PCM endpoint guidance is printed.
  --duration SECONDS        Maximum collection duration (default: 30).
  --pipeline NAME           Pipeline label (default: manual-intel-smoke).
  --influx-url URL          Collector-side Influx URL (default: http://127.0.0.1:18086).
  --pyroscope-url URL       Collector-side Pyroscope URL (default: http://127.0.0.1:14040).
  -h, --help                Show this help.

Expected result:
  - pcm-sensor-server is reachable at http://127.0.0.1:9738/persecond/.
  - 01 WCCKIT Pipeline Overview and 03 Intel PCM dashboard receive points.
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

if [[ -z "$pid" ]]; then
    cat <<EOF
Start or confirm the Intel PCM sensor endpoint first:

  docker run --rm -it --privileged --pid=host --net=host wcckit/pipeline-profiler:24.04 \\
    bash -lc 'pcm-sensor-server -p 9738'

Then check:

  curl -H 'Accept: application/json' http://127.0.0.1:9738/persecond/

Re-run this script with --pid <PID> to collect dashboard data.
EOF
    exit 0
fi

exec dockerfiles/bin/run-wcckit-intel-overview.sh \
    --pid "$pid" \
    --max-duration "$duration" \
    --pipeline "$pipeline" \
    --influx-url "$influx_url" \
    --pyroscope-url "$pyroscope_url"
