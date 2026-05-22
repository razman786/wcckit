#!/usr/bin/env bash
# Copyright (c) 2026, Raz.
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
IFS=$'\n\t'

DURATION="${WCCKIT_PROFILE_DURATION:-15}"
FREQUENCY="${WCCKIT_PROFILE_FREQUENCY:-99}"
OUT_FILE="${WCCKIT_PROFILE_OUT:-/out/perf.svg}"
FOLDED_OUT="${WCCKIT_PROFILE_FOLDED_OUT:-}"
TITLE="${WCCKIT_PROFILE_TITLE:-WCCKIT CPU Flame Graph}"
SUBTITLE="${WCCKIT_PROFILE_SUBTITLE:-}"
PID="${PID:-}"
RUN_ID="${WCCKIT_RUN_ID:-}"
PYROSCOPE_URL="${WCCKIT_PYROSCOPE_URL:-}"
PYROSCOPE_APP="${WCCKIT_PYROSCOPE_APP:-wcckit}"
PUSH_PROFILES=0
BCC_PROFILE="${BCC_PROFILE:-/src/bcc/tools/profile.py}"
FLAMEGRAPH="${FLAMEGRAPH:-/src/FlameGraph/flamegraph.pl}"

proc_value() {
    local file="$1"
    [[ -r "${file}" ]] || return 1
    tr '\0' ' ' < "${file}" 2>/dev/null || return 1
}

python_perf_status() {
    local cmdline environ exe exe_base version status details
    cmdline="$(proc_value "/proc/${PID}/cmdline" || true)"
    environ="$(proc_value "/proc/${PID}/environ" || true)"
    exe="$(readlink "/proc/${PID}/exe" 2>/dev/null || true)"
    exe_base="${exe##*/}"

    if [[ "${exe_base}" != python* && "${cmdline}" != *python* ]]; then
        return 0
    fi

    version="unknown"
    if [[ -n "${exe}" && -x "/proc/${PID}/root${exe}" ]]; then
        version="$(timeout 3 "/proc/${PID}/root${exe}" -V 2>&1 || true)"
        version="${version//$'\n'/ }"
    fi

    status="not-enabled"
    details="start Python 3.12+ targets with python3 -X perf or PYTHONPERFSUPPORT=1 for clearer sampled CPU flame graphs"
    if [[ " ${cmdline} " == *" -X perf "* || " ${cmdline} " == *" -X perf_jit "* || "${cmdline}" == *" -Xperf"* ]]; then
        status="enabled"
        details="detected -X perf/perf_jit in target command line"
    elif [[ "${environ}" == *"PYTHONPERFSUPPORT=1"* || "${environ}" == *"PYTHON_PERF_JIT_SUPPORT=1"* ]]; then
        status="enabled"
        details="detected Python perf support environment variable"
    fi

    echo "Python perf support check: ${status}; exe=${exe:-unknown}; version=${version}; ${details}"
    if [[ "${status}" != "enabled" ]]; then
        echo "Python perf support warning: CPU profiling will still run, but Python frames may be less clear without -X perf/PYTHONPERFSUPPORT=1." >&2
    fi
}

usage() {
    cat <<EOF
Generate a CPU flame graph for a target process using BCC profile.py.

Usage:
  ${0##*/} -p PID [options]

Options:
  -p, --pid PID           Target process ID. Required unless PID env var is set.
  -d, --duration SECONDS  Profile duration. Default: ${DURATION}
  -F, --frequency HZ      Sampling frequency. Default: ${FREQUENCY}
  -o, --output FILE       SVG output path. Default: ${OUT_FILE}
  --folded-output FILE   Folded stack output path. Default: SVG basename + .folded.
  --title TEXT           SVG title. Default: ${TITLE}
  --subtitle TEXT        Optional SVG subtitle, useful for source-line anchors.
  --pyroscope-url URL    Optional Pyroscope URL for folded profile ingest.
  --pyroscope-app NAME   Pyroscope application name. Default: ${PYROSCOPE_APP}
  --run-id RUN_ID        Run label for Pyroscope ingest.
  --push-profiles        Push folded profile to Pyroscope after SVG generation.
  -h, --help              Print this help.

Environment:
  PID                       Target process ID fallback.
  WCCKIT_PROFILE_DURATION   Default duration.
  WCCKIT_PROFILE_FREQUENCY  Default frequency.
  WCCKIT_PROFILE_OUT        Default output file.
  WCCKIT_PROFILE_FOLDED_OUT Default folded stack output file.
  WCCKIT_PROFILE_TITLE      Default SVG title.
  WCCKIT_PROFILE_SUBTITLE   Default SVG subtitle.
  BCC_PROFILE               profile.py path. Default: /src/bcc/tools/profile.py
  FLAMEGRAPH                flamegraph.pl path. Default: /src/FlameGraph/flamegraph.pl

Example:
  ${0##*/} --pid 1234 --duration 15 --frequency 99 --output /out/perf.svg
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -p|--pid)
            [[ $# -ge 2 ]] || { echo "--pid requires a value" >&2; exit 1; }
            PID="$2"
            shift 2
            ;;
        --pid=*)
            PID="${1#*=}"
            shift
            ;;
        -d|--duration)
            [[ $# -ge 2 ]] || { echo "--duration requires a value" >&2; exit 1; }
            DURATION="$2"
            shift 2
            ;;
        --duration=*)
            DURATION="${1#*=}"
            shift
            ;;
        -F|--frequency)
            [[ $# -ge 2 ]] || { echo "--frequency requires a value" >&2; exit 1; }
            FREQUENCY="$2"
            shift 2
            ;;
        --frequency=*)
            FREQUENCY="${1#*=}"
            shift
            ;;
        -o|--output)
            [[ $# -ge 2 ]] || { echo "--output requires a value" >&2; exit 1; }
            OUT_FILE="$2"
            shift 2
            ;;
        --output=*)
            OUT_FILE="${1#*=}"
            shift
            ;;
        --folded-output)
            [[ $# -ge 2 ]] || { echo "--folded-output requires a value" >&2; exit 1; }
            FOLDED_OUT="$2"
            shift 2
            ;;
        --folded-output=*)
            FOLDED_OUT="${1#*=}"
            shift
            ;;
        --title)
            [[ $# -ge 2 ]] || { echo "--title requires a value" >&2; exit 1; }
            TITLE="$2"
            shift 2
            ;;
        --title=*)
            TITLE="${1#*=}"
            shift
            ;;
        --subtitle)
            [[ $# -ge 2 ]] || { echo "--subtitle requires a value" >&2; exit 1; }
            SUBTITLE="$2"
            shift 2
            ;;
        --subtitle=*)
            SUBTITLE="${1#*=}"
            shift
            ;;
        --pyroscope-url)
            [[ $# -ge 2 ]] || { echo "--pyroscope-url requires a value" >&2; exit 1; }
            PYROSCOPE_URL="$2"
            shift 2
            ;;
        --pyroscope-url=*)
            PYROSCOPE_URL="${1#*=}"
            shift
            ;;
        --pyroscope-app)
            [[ $# -ge 2 ]] || { echo "--pyroscope-app requires a value" >&2; exit 1; }
            PYROSCOPE_APP="$2"
            shift 2
            ;;
        --pyroscope-app=*)
            PYROSCOPE_APP="${1#*=}"
            shift
            ;;
        --run-id)
            [[ $# -ge 2 ]] || { echo "--run-id requires a value" >&2; exit 1; }
            RUN_ID="$2"
            shift 2
            ;;
        --run-id=*)
            RUN_ID="${1#*=}"
            shift
            ;;
        --push-profiles)
            PUSH_PROFILES=1
            shift
            ;;
        *)
            echo "unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

[[ -n "${PID}" ]] || { echo "PID is required; pass --pid or set PID" >&2; exit 1; }
[[ "${PID}" =~ ^[0-9]+$ ]] || { echo "PID must be numeric: ${PID}" >&2; exit 1; }
[[ "${DURATION}" =~ ^[1-9][0-9]*$ ]] || { echo "duration must be a positive integer: ${DURATION}" >&2; exit 1; }
[[ "${FREQUENCY}" =~ ^[1-9][0-9]*$ ]] || { echo "frequency must be a positive integer: ${FREQUENCY}" >&2; exit 1; }
[[ -x "${BCC_PROFILE}" || -f "${BCC_PROFILE}" ]] || { echo "profile.py not found: ${BCC_PROFILE}" >&2; exit 1; }
[[ -x "${FLAMEGRAPH}" || -f "${FLAMEGRAPH}" ]] || { echo "flamegraph.pl not found: ${FLAMEGRAPH}" >&2; exit 1; }

if [[ -z "${FOLDED_OUT}" ]]; then
    FOLDED_OUT="${OUT_FILE%.*}.folded"
fi
mkdir -p "$(dirname "${OUT_FILE}")" "$(dirname "${FOLDED_OUT}")"

FLAMEGRAPH_ARGS=(--title "${TITLE}")
if [[ -n "${SUBTITLE}" ]]; then
    FLAMEGRAPH_ARGS+=(--subtitle "${SUBTITLE}" --notes "${SUBTITLE}")
fi

echo "Profiling PID ${PID} for ${DURATION}s at ${FREQUENCY}Hz"
echo "Writing folded stacks to ${FOLDED_OUT}"
echo "Writing flame graph to ${OUT_FILE}"
if [[ -n "${SUBTITLE}" ]]; then
    echo "SVG subtitle: ${SUBTITLE}"
fi
python_perf_status

python3 "${BCC_PROFILE}" -dF "${FREQUENCY}" -f "${DURATION}" -p "${PID}" > "${FOLDED_OUT}"
perl "${FLAMEGRAPH}" "${FLAMEGRAPH_ARGS[@]}" < "${FOLDED_OUT}" > "${OUT_FILE}"

if [[ "${PUSH_PROFILES}" -eq 1 ]]; then
    [[ -n "${PYROSCOPE_URL}" ]] || { echo "--push-profiles requires --pyroscope-url" >&2; exit 1; }
    if command -v wcckit_push_pyroscope.py >/dev/null 2>&1; then
        wcckit_push_pyroscope.py --url "${PYROSCOPE_URL}" --app-name "${PYROSCOPE_APP}" \
            --profile-type cpu --input "${FOLDED_OUT}" --run-id "${RUN_ID:-standalone}" \
            --pipeline "${PYROSCOPE_APP}" --pid "${PID}"
    else
        echo "wcckit_push_pyroscope.py not found; cannot push profile" >&2
        exit 1
    fi
fi

echo "CPU folded stacks written: ${FOLDED_OUT}"
echo "CPU flame graph written: ${OUT_FILE}"
