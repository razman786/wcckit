#!/usr/bin/env bash
# Copyright (c) 2026, Raz.
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVERVIEW="${SCRIPT_DIR}/run-wcckit-pipeline-overview.sh"

usage() {
    cat <<'EOF'
Run the WCCKIT Pipeline Overview collector with Intel PCM hardware counters.

This wrapper enables the normal dashboard metrics by default and leaves CPU
flame graph collection off unless you explicitly pass --flamegraph.

Usage:
  run-wcckit-intel-overview.sh --pid PID [options]
  run-wcckit-intel-overview.sh --match PATTERN [options]

Common examples:
  run-wcckit-intel-overview.sh --match DDFacet --pipeline DDFacet --language python \
    --influx-url http://127.0.0.1:18086

  run-wcckit-intel-overview.sh --pid 12345 --pipeline MyPipeline --language python \
    --influx-url http://127.0.0.1:18086

Add interactive CPU flame graphs only when needed:
  run-wcckit-intel-overview.sh --match DDFacet --pipeline DDFacet --language python \
    --influx-url http://127.0.0.1:18086 \
    --pyroscope-url http://127.0.0.1:14040 \
    --flamegraph --push-profiles

All options except --hardware-counters are passed through to
run-wcckit-pipeline-overview.sh. This wrapper always sets:
  --hardware-counters intel-pcm
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

[[ -x "${OVERVIEW}" ]] || { printf '[wcckit-intel-pcm] error: missing overview wrapper: %s\n' "${OVERVIEW}" >&2; exit 1; }

exec "${OVERVIEW}" --hardware-counters intel-pcm "$@"
