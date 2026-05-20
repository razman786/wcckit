#!/usr/bin/env bash
# Copyright (c) 2026, Raz.
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
IFS=$'\n\t'

PROFILE_DURATION="${WCCKIT_HOTSPOT_PROFILE_DURATION:-15}"
TARGET_DURATION="${WCCKIT_HOTSPOT_TARGET_DURATION:-90}"
FREQUENCY="${WCCKIT_HOTSPOT_FREQUENCY:-99}"
OUT_DIR="${WCCKIT_HOTSPOT_OUT_DIR:-profile-output}"
SVG_NAME="${WCCKIT_HOTSPOT_SVG:-python-hotspot.svg}"

usage() {
    cat <<EOF
Run the WCCKIT Python hotspot profiling smoke test.

Usage:
  ${0##*/} [options]

Options:
  --profile-duration SECONDS  BCC profiling duration. Default: ${PROFILE_DURATION}
  --target-duration SECONDS   Python target duration. Default: ${TARGET_DURATION}
  --frequency HZ              BCC sampling frequency. Default: ${FREQUENCY}
  --out DIR                   Host output directory. Default: ${OUT_DIR}
  --svg NAME                  SVG filename under /out. Default: ${SVG_NAME}
  -h, --help                  Print this help.

The script starts examples/profiling/python_hotspot.py, captures its PID, then
profiles that PID through dockerfiles/bin/run-wcckit-profiler.sh.
EOF
}

die() {
    printf 'profile_python_hotspot.sh: error: %s\n' "$*" >&2
    exit 1
}

repo_root() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    cd "${script_dir}/../.." && pwd
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile-duration)
            [[ $# -ge 2 ]] || die "--profile-duration requires a value"
            PROFILE_DURATION="$2"
            shift 2
            ;;
        --profile-duration=*)
            PROFILE_DURATION="${1#*=}"
            shift
            ;;
        --target-duration)
            [[ $# -ge 2 ]] || die "--target-duration requires a value"
            TARGET_DURATION="$2"
            shift 2
            ;;
        --target-duration=*)
            TARGET_DURATION="${1#*=}"
            shift
            ;;
        --frequency)
            [[ $# -ge 2 ]] || die "--frequency requires a value"
            FREQUENCY="$2"
            shift 2
            ;;
        --frequency=*)
            FREQUENCY="${1#*=}"
            shift
            ;;
        --out)
            [[ $# -ge 2 ]] || die "--out requires a value"
            OUT_DIR="$2"
            shift 2
            ;;
        --out=*)
            OUT_DIR="${1#*=}"
            shift
            ;;
        --svg)
            [[ $# -ge 2 ]] || die "--svg requires a value"
            SVG_NAME="$2"
            shift 2
            ;;
        --svg=*)
            SVG_NAME="${1#*=}"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown option: $1"
            ;;
    esac
done

[[ "${PROFILE_DURATION}" =~ ^[1-9][0-9]*$ ]] || die "profile duration must be a positive integer"
[[ "${TARGET_DURATION}" =~ ^[1-9][0-9]*$ ]] || die "target duration must be a positive integer"
[[ "${FREQUENCY}" =~ ^[1-9][0-9]*$ ]] || die "frequency must be a positive integer"

ROOT="$(repo_root)"
cd "${ROOT}"

mkdir -p "${OUT_DIR}"
LOG_FILE="${OUT_DIR}/python-hotspot.log"

python3 -X perf examples/profiling/python_hotspot.py \
    --duration "${TARGET_DURATION}" >"${LOG_FILE}" 2>&1 &
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
    sed -n '1,80p' "${LOG_FILE}" >&2 || true
    die "Python hotspot target exited before profiling started"
fi

HOTSPOT_LINE="$(sed -n 's/^HOTSPOT=//p' "${LOG_FILE}" | head -n 1)"

printf 'Target PID: %s\n' "${TARGET_PID}"
printf 'Target log: %s\n' "${LOG_FILE}"
sed -n '1,6p' "${LOG_FILE}"

PROFILE_CMD=(
    dockerfiles/bin/run-wcckit-profiler.sh --out "${OUT_DIR}" --
    wcckit_profile_cpu.sh
    --pid "${TARGET_PID}"
    --duration "${PROFILE_DURATION}"
    --frequency "${FREQUENCY}"
    --output "/out/${SVG_NAME}"
)
if [[ -n "${HOTSPOT_LINE}" ]]; then
    PROFILE_CMD+=(--subtitle "Target hotspot: ${HOTSPOT_LINE}")
fi

"${PROFILE_CMD[@]}"

printf 'Flame graph: %s/%s\n' "${OUT_DIR}" "${SVG_NAME}"
printf 'The target log and SVG subtitle record the intended Python hotspot source line.\n'
printf 'With Python perf support, the SVG may also include wcckit_intentional_hotspot frames.\n'
