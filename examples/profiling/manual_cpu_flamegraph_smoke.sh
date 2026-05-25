#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

duration=20
frequency=99
out_dir="/tmp/wcckit-flamecpu-smoke"
pyroscope_url="http://127.0.0.1:4040"

usage() {
    cat <<'EOF'
Manual CPU flamegraph smoke test for WCCKIT.

This starts the included Python hotspot workload and captures a sampled CPU
flamegraph. It may require privileged Docker/perf access. CPU flamegraphs are
sampled profiles, not complete call traces.

Options:
  --duration SECONDS        Workload/profile duration (default: 20).
  --frequency HZ            Sampling frequency (default: 99).
  --out DIR                 Output directory (default: /tmp/wcckit-flamecpu-smoke).
  --pyroscope-url URL       Pyroscope URL (default: http://127.0.0.1:4040).
  -h, --help                Show this help.

Expected result:
  - CPU SVG and folded stack artifacts are created.
  - WCCKIT Flamegraphs dashboard receives data when Pyroscope is reachable.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --duration) duration="$2"; shift 2 ;;
        --frequency) frequency="$2"; shift 2 ;;
        --out) out_dir="$2"; shift 2 ;;
        --pyroscope-url) pyroscope_url="$2"; shift 2 ;;
        --push-profiles) push=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

exec examples/profiling/profile_cpu_flamegraph_grafana_smoke.sh \
    --profile-duration "$duration" \
    --frequency "$frequency" \
    --out "$out_dir" \
    --pyroscope-url "$pyroscope_url"
