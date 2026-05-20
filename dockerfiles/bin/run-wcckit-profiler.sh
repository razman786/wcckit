#!/usr/bin/env bash
# Copyright (c) 2026, Dr Rahim Lakhoo.
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
IFS=$'\n\t'

IMAGE="${WCCKIT_PROFILER_IMAGE:-${WCCKIT_BCC_IMAGE:-wcckit/bcc-profiler:24.04}}"
OUT_DIR="${WCCKIT_OUT_DIR:-$PWD}"

usage() {
    cat <<EOF
Start the WCCKIT profiling container.

Usage:
  ${0##*/} [--image IMAGE] [--out DIR] [--] [COMMAND...]

Environment:
  WCCKIT_PROFILER_IMAGE  Image to run. Default: wcckit/bcc-profiler:24.04
  WCCKIT_BCC_IMAGE       Backward-compatible image override.
  WCCKIT_OUT_DIR    Host output directory mounted at /out. Default: current directory

Examples:
  ${0##*/}
  ${0##*/} --out ./profile-output
  ${0##*/} -- biolatency-bpfcc
  ${0##*/} -- wcckit_profile_cpu.sh --pid 1234 --output /out/perf.svg
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --image)
            [[ $# -ge 2 ]] || { echo "--image requires a value" >&2; exit 1; }
            IMAGE="$2"
            shift 2
            ;;
        --image=*)
            IMAGE="${1#*=}"
            shift
            ;;
        --out)
            [[ $# -ge 2 ]] || { echo "--out requires a value" >&2; exit 1; }
            OUT_DIR="$2"
            shift 2
            ;;
        --out=*)
            OUT_DIR="${1#*=}"
            shift
            ;;
        --)
            shift
            break
            ;;
        *)
            break
            ;;
    esac
done

mkdir -p "${OUT_DIR}"
OUT_DIR="$(cd "${OUT_DIR}" && pwd)"

if ! command -v docker >/dev/null 2>&1; then
    echo "docker is not installed or not on PATH" >&2
    exit 1
fi

exec docker run -it --rm \
    --privileged \
    --pid=host \
    --net=host \
    -v "${OUT_DIR}":/out \
    -v /etc/localtime:/etc/localtime:ro \
    -v /sys/kernel/debug:/sys/kernel/debug:rw \
    -v /sys/kernel/tracing:/sys/kernel/tracing:rw \
    -v /sys/fs/bpf:/sys/fs/bpf:rw \
    -v /sys/fs/cgroup:/sys/fs/cgroup:ro \
    -v /lib/modules:/lib/modules:ro \
    -v /usr/src:/usr/src:ro \
    "${IMAGE}" \
    "$@"
