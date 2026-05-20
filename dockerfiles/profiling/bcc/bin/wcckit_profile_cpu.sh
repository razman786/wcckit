#!/usr/bin/env bash
# Copyright (c) 2026, Raz.
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
IFS=$'\n\t'

DURATION="${WCCKIT_PROFILE_DURATION:-15}"
FREQUENCY="${WCCKIT_PROFILE_FREQUENCY:-99}"
OUT_FILE="${WCCKIT_PROFILE_OUT:-/out/perf.svg}"
TITLE="${WCCKIT_PROFILE_TITLE:-WCCKIT CPU Flame Graph}"
SUBTITLE="${WCCKIT_PROFILE_SUBTITLE:-}"
PID="${PID:-}"
BCC_PROFILE="${BCC_PROFILE:-/src/bcc/tools/profile.py}"
FLAMEGRAPH="${FLAMEGRAPH:-/src/FlameGraph/flamegraph.pl}"

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
  --title TEXT           SVG title. Default: ${TITLE}
  --subtitle TEXT        Optional SVG subtitle, useful for source-line anchors.
  -h, --help              Print this help.

Environment:
  PID                       Target process ID fallback.
  WCCKIT_PROFILE_DURATION   Default duration.
  WCCKIT_PROFILE_FREQUENCY  Default frequency.
  WCCKIT_PROFILE_OUT        Default output file.
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

mkdir -p "$(dirname "${OUT_FILE}")"

FLAMEGRAPH_ARGS=(--title "${TITLE}")
if [[ -n "${SUBTITLE}" ]]; then
    FLAMEGRAPH_ARGS+=(--subtitle "${SUBTITLE}" --notes "${SUBTITLE}")
fi

echo "Profiling PID ${PID} for ${DURATION}s at ${FREQUENCY}Hz"
echo "Writing flame graph to ${OUT_FILE}"
if [[ -n "${SUBTITLE}" ]]; then
    echo "SVG subtitle: ${SUBTITLE}"
fi

python3 "${BCC_PROFILE}" -dF "${FREQUENCY}" -f "${DURATION}" -p "${PID}" \
    | perl "${FLAMEGRAPH}" "${FLAMEGRAPH_ARGS[@]}" > "${OUT_FILE}"

echo "CPU flame graph written: ${OUT_FILE}"
