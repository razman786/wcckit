#!/usr/bin/env bash
# Copyright (c) 2026, Raz.
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLLECTOR="${SCRIPT_DIR}/run-wcckit-pipeline-profiler.sh"

PID=""
MATCH=""
PIPELINE=""
RUN_ID=""
OUT_DIR="runs"
LANGUAGE="python"
HARDWARE_COUNTERS="auto"
JOB_LANE="1"
MAX_DURATION="${WCCKIT_MAX_DURATION:-86400}"
INFLUX_URL="${WCCKIT_INFLUX_URL:-http://127.0.0.1:8086}"
INFLUX_ORG="${WCCKIT_INFLUX_ORG:-wcckit}"
INFLUX_BUCKET="${WCCKIT_INFLUX_BUCKET:-wcckit}"
INFLUX_TOKEN="${WCCKIT_INFLUX_TOKEN:-wcckit-dev-token}"
PYROSCOPE_URL="${WCCKIT_PYROSCOPE_URL:-}"
PUSH_PROFILES=0
FLAMEGRAPH=0
EXTRA_ARGS=()

usage() {
    cat <<EOF
Profile a pipeline PID for the WCCKIT Pipeline Overview dashboard.

This is the researcher-facing wrapper for the normal dashboard workflow. It
starts the privileged collector and keeps collecting until the target PID exits,
or until --max-duration is reached.

Usage:
  ${0##*/} --pid PID [options]
  ${0##*/} --match PATTERN [options]

Required:
  --pid PID                 Host process ID to profile.
  --match PATTERN           Alternative: profile the newest process matching pgrep -f.

Common options:
  --pipeline NAME           Pipeline name shown in Grafana. Default: process name or PATTERN.
  --run-id RUN_ID           Run identifier. Default: <pipeline>-<UTC timestamp>.
  --out DIR                 Host output root. Default: runs.
  --language LANGUAGE       python|java|perl|php|ruby|tcl. Default: python.
  --hardware-counters MODE  auto|intel-pcm|amd-uprof|none. Default: auto.
  --job-lane N              Dashboard lane/counter. Default: 1.
  --max-duration SECONDS    Safety cap while waiting for PID exit. Default: ${MAX_DURATION}.

Viewer endpoints:
  --influx-url URL          Default: ${INFLUX_URL}
  --influx-org ORG          Default: ${INFLUX_ORG}
  --influx-bucket BUCKET    Default: ${INFLUX_BUCKET}
  --influx-token TOKEN      Default: ${INFLUX_TOKEN}
  --pyroscope-url URL       Optional, e.g. http://127.0.0.1:4040.
  --push-profiles           Push folded profiles when --pyroscope-url is set.
  --flamegraph              Also collect sampled CPU flamegraph artifacts. Default: off.
  --no-flamegraph           Disable sampled CPU flamegraph artifacts.

Everything after -- is passed to run-wcckit-pipeline-profiler.sh.

Examples:
  ${0##*/} --match DDFacet --pipeline DDFacet
  ${0##*/} --pid 12345 --pipeline wsclean --hardware-counters auto

Remote compute-node example after opening an SSH reverse tunnel:
  ${0##*/} --match DDFacet --pipeline DDFacet \\
    --influx-url http://127.0.0.1:18086 \\
    --pyroscope-url http://127.0.0.1:14040 --push-profiles
EOF
}

die() {
    printf '[wcckit-overview] error: %s\n' "$*" >&2
    exit 1
}

slug() {
    printf '%s' "$1" | tr '[:upper:] /' '[:lower:]--' | tr -cd 'a-z0-9._:-'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --pid) [[ $# -ge 2 ]] || die "--pid requires a value"; PID="$2"; shift 2 ;;
        --pid=*) PID="${1#*=}"; shift ;;
        --match) [[ $# -ge 2 ]] || die "--match requires a value"; MATCH="$2"; shift 2 ;;
        --match=*) MATCH="${1#*=}"; shift ;;
        --pipeline) [[ $# -ge 2 ]] || die "--pipeline requires a value"; PIPELINE="$2"; shift 2 ;;
        --pipeline=*) PIPELINE="${1#*=}"; shift ;;
        --run-id) [[ $# -ge 2 ]] || die "--run-id requires a value"; RUN_ID="$2"; shift 2 ;;
        --run-id=*) RUN_ID="${1#*=}"; shift ;;
        --out) [[ $# -ge 2 ]] || die "--out requires a value"; OUT_DIR="$2"; shift 2 ;;
        --out=*) OUT_DIR="${1#*=}"; shift ;;
        --language) [[ $# -ge 2 ]] || die "--language requires a value"; LANGUAGE="$2"; shift 2 ;;
        --language=*) LANGUAGE="${1#*=}"; shift ;;
        --hardware-counters) [[ $# -ge 2 ]] || die "--hardware-counters requires a value"; HARDWARE_COUNTERS="$2"; shift 2 ;;
        --hardware-counters=*) HARDWARE_COUNTERS="${1#*=}"; shift ;;
        --job-lane) [[ $# -ge 2 ]] || die "--job-lane requires a value"; JOB_LANE="$2"; shift 2 ;;
        --job-lane=*) JOB_LANE="${1#*=}"; shift ;;
        --max-duration) [[ $# -ge 2 ]] || die "--max-duration requires a value"; MAX_DURATION="$2"; shift 2 ;;
        --max-duration=*) MAX_DURATION="${1#*=}"; shift ;;
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
        --push-profiles) PUSH_PROFILES=1; shift ;;
        --flamegraph) FLAMEGRAPH=1; shift ;;
        --no-flamegraph) FLAMEGRAPH=0; shift ;;
        --) shift; EXTRA_ARGS+=("$@"); break ;;
        *) EXTRA_ARGS+=("$1"); shift ;;
    esac
done

[[ -x "${COLLECTOR}" ]] || die "collector wrapper not executable: ${COLLECTOR}"
[[ "${MAX_DURATION}" =~ ^[1-9][0-9]*$ ]] || die "--max-duration must be a positive integer"
[[ "${JOB_LANE}" =~ ^[1-9][0-9]*$ ]] || die "--job-lane must be a positive integer"

if [[ -z "${PID}" ]]; then
    [[ -n "${MATCH}" ]] || die "use --pid PID or --match PATTERN"
    command -v pgrep >/dev/null 2>&1 || die "pgrep is required for --match"
    PID="$(pgrep -n -f "${MATCH}" || true)"
    [[ -n "${PID}" ]] || die "no process matched: ${MATCH}"
fi

[[ "${PID}" =~ ^[1-9][0-9]*$ ]] || die "PID must be a positive integer: ${PID}"
[[ -e "/proc/${PID}" ]] || die "PID ${PID} is not running"

if [[ -z "${PIPELINE}" ]]; then
    if [[ -n "${MATCH}" ]]; then
        PIPELINE="${MATCH}"
    elif [[ -r "/proc/${PID}/comm" ]]; then
        PIPELINE="$(tr -d '\0\n' < "/proc/${PID}/comm")"
    else
        PIPELINE="pipeline"
    fi
fi

if [[ -z "${RUN_ID}" ]]; then
    RUN_ID="$(slug "${PIPELINE}")-$(date -u +%Y%m%dT%H%M%SZ)"
fi

printf '[wcckit-overview] profiling pid=%s pipeline=%s run_id=%s until exit, max_duration=%ss\n' \
    "${PID}" "${PIPELINE}" "${RUN_ID}" "${MAX_DURATION}" >&2

cmd=(
    "${COLLECTOR}"
    --pid "${PID}"
    --until-exit
    --duration "${MAX_DURATION}"
    --pipeline "${PIPELINE}"
    --language "${LANGUAGE}"
    --hardware-counters "${HARDWARE_COUNTERS}"
    --job-lane "${JOB_LANE}"
    --run-id "${RUN_ID}"
    --out "${OUT_DIR}/${RUN_ID}"
    --influx-url "${INFLUX_URL}"
    --influx-org "${INFLUX_ORG}"
    --influx-bucket "${INFLUX_BUCKET}"
    --influx-token "${INFLUX_TOKEN}"
)

if [[ "${FLAMEGRAPH}" -eq 1 ]]; then
    cmd+=(--flamegraph)
else
    cmd+=(--no-flamegraph)
fi
if [[ -n "${PYROSCOPE_URL}" ]]; then
    cmd+=(--pyroscope-url "${PYROSCOPE_URL}")
fi
if [[ "${PUSH_PROFILES}" -eq 1 ]]; then
    cmd+=(--push-profiles)
fi
cmd+=("${EXTRA_ARGS[@]}")

exec "${cmd[@]}"
