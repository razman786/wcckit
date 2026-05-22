#!/usr/bin/env bash
# Copyright (c) 2026, Raz.
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
IFS=$'\n\t'

PROFILE_DURATION="${WCCKIT_FLAMECPU_PROFILE_DURATION:-20}"
TARGET_DURATION="${WCCKIT_FLAMECPU_TARGET_DURATION:-}"
OUT_DIR="${WCCKIT_FLAMECPU_OUT_DIR:-/tmp/wcckit-flamecpu-smoke}"
RUN_ID="${WCCKIT_FLAMECPU_RUN_ID:-flamecpu-smoke-$(date -u +%Y%m%dT%H%M%SZ)}"
PIPELINE="${WCCKIT_FLAMECPU_PIPELINE:-PythonHotspot}"
INFLUX_URL="${WCCKIT_INFLUX_URL:-http://127.0.0.1:8086}"
INFLUX_ORG="${WCCKIT_INFLUX_ORG:-wcckit}"
INFLUX_BUCKET="${WCCKIT_INFLUX_BUCKET:-wcckit}"
INFLUX_TOKEN="${WCCKIT_INFLUX_TOKEN:-wcckit-dev-token}"
PYROSCOPE_URL="${WCCKIT_PYROSCOPE_URL:-http://127.0.0.1:4040}"
FREQUENCY="${WCCKIT_FLAMECPU_FREQUENCY:-99}"

usage() {
    cat <<EOF
Run a local WCCKIT CPU flame graph + Pyroscope/Grafana smoke test.

The test starts examples/profiling/python_hotspot.py, attaches the WCCKIT
pipeline overview collector to its PID, enables sampled CPU flame graph capture,
pushes folded stacks to Pyroscope, and checks that local folded/SVG artifacts
were produced.

Usage:
  ${0##*/} [options]

Options:
  --profile-duration SECONDS  CPU profiling duration. Default: ${PROFILE_DURATION}
  --target-duration SECONDS   Target runtime. Default: profile duration + 30s.
  --out DIR                   Host output root. Default: ${OUT_DIR}
  --run-id RUN_ID             Run identifier. Default: ${RUN_ID}
  --pipeline NAME             Pipeline label. Default: ${PIPELINE}
  --influx-url URL            InfluxDB URL. Default: ${INFLUX_URL}
  --influx-org ORG            InfluxDB org. Default: ${INFLUX_ORG}
  --influx-bucket BUCKET      InfluxDB bucket. Default: ${INFLUX_BUCKET}
  --influx-token TOKEN        InfluxDB token. Default: ${INFLUX_TOKEN}
  --pyroscope-url URL         Pyroscope URL. Default: ${PYROSCOPE_URL}
  --frequency HZ              Sampling frequency. Default: ${FREQUENCY}
  -h, --help                  Print this help.

Prerequisites:
  dockerfiles/bin/run-wcckit-viewer.sh up
  docker image wcckit/pipeline-profiler:24.04 built locally
EOF
}

die() { printf '[wcckit-flamecpu-smoke] error: %s
' "$*" >&2; exit 1; }
info() { printf '[wcckit-flamecpu-smoke] %s
' "$*" >&2; }

repo_root() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    cd "${script_dir}/../.." && pwd
}

http_ready() {
    local url="$1"
    command -v curl >/dev/null 2>&1 || return 1
    curl -fsS -m 4 "$url" >/dev/null 2>&1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --profile-duration) [[ $# -ge 2 ]] || die "--profile-duration requires a value"; PROFILE_DURATION="$2"; shift 2 ;;
        --profile-duration=*) PROFILE_DURATION="${1#*=}"; shift ;;
        --target-duration) [[ $# -ge 2 ]] || die "--target-duration requires a value"; TARGET_DURATION="$2"; shift 2 ;;
        --target-duration=*) TARGET_DURATION="${1#*=}"; shift ;;
        --out) [[ $# -ge 2 ]] || die "--out requires a value"; OUT_DIR="$2"; shift 2 ;;
        --out=*) OUT_DIR="${1#*=}"; shift ;;
        --run-id) [[ $# -ge 2 ]] || die "--run-id requires a value"; RUN_ID="$2"; shift 2 ;;
        --run-id=*) RUN_ID="${1#*=}"; shift ;;
        --pipeline) [[ $# -ge 2 ]] || die "--pipeline requires a value"; PIPELINE="$2"; shift 2 ;;
        --pipeline=*) PIPELINE="${1#*=}"; shift ;;
        --influx-url) [[ $# -ge 2 ]] || die "--influx-url requires a value"; INFLUX_URL="$2"; shift 2 ;;
        --influx-url=*) INFLUX_URL="${1#*=}"; shift ;;
        --influx-org) [[ $# -ge 2 ]] || die "--influx-org requires a value"; INFLUX_ORG="$2"; shift 2 ;;
        --influx-org=*) INFLUX_ORG="${1#*=}"; shift ;;
        --influx-bucket) [[ $# -ge 2 ]] || die "--influx-bucket requires a value"; INFLUX_BUCKET="$2"; shift 2 ;;
        --influx-bucket=*) INFLUX_BUCKET="${1#*=}"; shift ;;
        --influx-token) [[ $# -ge 2 ]] || die "--influx-token requires a value"; INFLUX_TOKEN="$2"; shift 2 ;;
        --influx-token=*) INFLUX_TOKEN="${1#*=}"; shift ;;
        --pyroscope-url) [[ $# -ge 2 ]] || die "--pyroscope-url requires a value"; PYROSCOPE_URL="$2"; shift 2 ;;
        --pyroscope-url=*) PYROSCOPE_URL="${1#*=}"; shift ;;
        --frequency) [[ $# -ge 2 ]] || die "--frequency requires a value"; FREQUENCY="$2"; shift 2 ;;
        --frequency=*) FREQUENCY="${1#*=}"; shift ;;
        *) die "unknown option: $1" ;;
    esac
done

[[ "${PROFILE_DURATION}" =~ ^[1-9][0-9]*$ ]] || die "profile duration must be a positive integer"
[[ "${FREQUENCY}" =~ ^[1-9][0-9]*$ ]] || die "frequency must be a positive integer"
if [[ -z "${TARGET_DURATION}" ]]; then
    TARGET_DURATION=$((PROFILE_DURATION + 30))
fi
[[ "${TARGET_DURATION}" =~ ^[1-9][0-9]*$ ]] || die "target duration must be a positive integer"
(( TARGET_DURATION > PROFILE_DURATION )) || die "target duration must be greater than profile duration"

ROOT="$(repo_root)"
cd "${ROOT}"

[[ -x dockerfiles/bin/run-wcckit-pipeline-profiler.sh ]] || die "pipeline profiler wrapper is missing or not executable"
command -v python3 >/dev/null 2>&1 || die "python3 is not installed or not on PATH"
command -v docker >/dev/null 2>&1 || die "docker is not installed or not on PATH"

if ! http_ready "${PYROSCOPE_URL%/}/ready"; then
    die "Pyroscope is not reachable at ${PYROSCOPE_URL}; start the viewer with dockerfiles/bin/run-wcckit-viewer.sh up"
fi

mkdir -p "${OUT_DIR}"
TARGET_LOG="${OUT_DIR}/${RUN_ID}-target.log"

python3 -X perf examples/profiling/python_hotspot.py \
    --duration "${TARGET_DURATION}" >"${TARGET_LOG}" 2>&1 &
TARGET_PID="$!"

cleanup() {
    if kill -0 "${TARGET_PID}" >/dev/null 2>&1; then
        kill "${TARGET_PID}" >/dev/null 2>&1 || true
        wait "${TARGET_PID}" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

sleep 2
if ! kill -0 "${TARGET_PID}" >/dev/null 2>&1; then
    sed -n '1,80p' "${TARGET_LOG}" >&2 || true
    die "Python hotspot target exited before profiling started"
fi

info "target pid=${TARGET_PID} log=${TARGET_LOG}"
sed -n '1,6p' "${TARGET_LOG}" >&2 || true

PROFILE_CMD=(
    dockerfiles/bin/run-wcckit-pipeline-profiler.sh
    --pid "${TARGET_PID}"
    --duration "${PROFILE_DURATION}"
    --pipeline "${PIPELINE}"
    --language python
    --hardware-counters none
    --influx-url "${INFLUX_URL}"
    --influx-org "${INFLUX_ORG}"
    --influx-bucket "${INFLUX_BUCKET}"
    --influx-token "${INFLUX_TOKEN}"
    --pyroscope-url "${PYROSCOPE_URL}"
    --flamegraph
    --push-profiles
    --run-id "${RUN_ID}"
    --out "${OUT_DIR}/${RUN_ID}"
    --no-bpf-io
    --no-app-stat
    --no-app-calls
    --no-app-flow-summary
    --no-app-flow-raw
)

WCCKIT_PROFILE_FREQUENCY="${FREQUENCY}" "${PROFILE_CMD[@]}"

RUN_DIR="${OUT_DIR}/${RUN_ID}"
FOLDED="${RUN_DIR}/profiles/cpu.folded"
SVG="${RUN_DIR}/flamegraphs/cpu.svg"
LP="${RUN_DIR}/metrics/influx.lp"
PYRO_LOG="${RUN_DIR}/logs/pyroscope.log"

[[ -s "${FOLDED}" ]] || die "missing or empty folded profile: ${FOLDED}"
[[ -s "${SVG}" ]] || die "missing or empty SVG flame graph: ${SVG}"
if [[ -f "${LP}" ]] && grep -q 'wcckit_profile_status' "${LP}"; then
    info "profile status metric found in ${LP}"
else
    die "missing wcckit_profile_status in ${LP}"
fi

info "folded profile: ${FOLDED} ($(wc -l < "${FOLDED}") lines)"
info "static flame graph: ${SVG}"
info "pyroscope log: ${PYRO_LOG}"
info "open Grafana -> WCCKIT Profiles, service/app ${PIPELINE}, run_id ${RUN_ID}, profile_type cpu"
