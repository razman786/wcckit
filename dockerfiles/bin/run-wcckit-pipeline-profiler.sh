#!/usr/bin/env bash
# Copyright (c) 2026, Raz.
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
IFS=$'\n\t'

IMAGE="${WCCKIT_PIPELINE_IMAGE:-wcckit/pipeline-profiler:24.04}"
OUT_DIR="${WCCKIT_OUT_DIR:-runs}"
RUN_ID=""
OUT_ARG_SET=0
PASS_ARGS=()

usage() {
    cat <<EOF
Start the combined WCCKIT pipeline profiler container.

Usage:
  ${0##*/} [options]

Required for a real run:
  --pid PID                 Host process ID to profile.

Common options:
  --image IMAGE             Collector image. Default: ${IMAGE}
  --out DIR                 Host output root or run directory. Default: ${OUT_DIR}
  --run-id RUN_ID           Run identifier. Defaults inside the container.
  --duration SECONDS        Collection duration.
  --pipeline NAME           Pipeline/application name, for example DDFacet.
  --language LANGUAGE       python|java|perl|php|ruby|tcl. Default: python.
  --hardware-counters MODE  auto|intel-pcm|amd-uprof|none. Default: auto.
  --influx-url URL          InfluxDB URL, for example http://127.0.0.1:8086.
  --influx-org ORG          InfluxDB organisation.
  --influx-bucket BUCKET    InfluxDB bucket.
  --influx-token TOKEN      InfluxDB API token.
  -h, --help                Print this help.

Collector feature flags are passed through to wcckit_profile_pipeline.sh, for example:
  --no-app-flow-summary
  --app-flow-raw
  --hardware-counters amd-uprof
  --no-amd-uprof-memory
  --no-amd-uprof-power
  --no-flamegraph

Examples:
  ${0##*/} --pid 1234 --duration 120 --pipeline DDFacet --run-id ddfacet-001 --out runs
  ${0##*/} --pid 1234 --duration 120 --pipeline DDFacet --run-id ddfacet-001 --out runs/ddfacet-001
EOF
}

die() {
    printf '[wcckit-pipeline-profiler] error: %s\n' "$*" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --image)
            [[ $# -ge 2 ]] || die "--image requires a value"
            IMAGE="$2"
            shift 2
            ;;
        --image=*)
            IMAGE="${1#*=}"
            shift
            ;;
        --out)
            [[ $# -ge 2 ]] || die "--out requires a value"
            OUT_DIR="$2"
            OUT_ARG_SET=1
            PASS_ARGS+=("--out" "/out")
            shift 2
            ;;
        --out=*)
            OUT_DIR="${1#*=}"
            OUT_ARG_SET=1
            PASS_ARGS+=("--out" "/out")
            shift
            ;;
        --run-id)
            [[ $# -ge 2 ]] || die "--run-id requires a value"
            RUN_ID="$2"
            PASS_ARGS+=("--run-id" "$2")
            shift 2
            ;;
        --run-id=*)
            RUN_ID="${1#*=}"
            PASS_ARGS+=("--run-id" "${1#*=}")
            shift
            ;;
        *)
            PASS_ARGS+=("$1")
            shift
            ;;
    esac
done

if [[ "${OUT_ARG_SET}" -eq 0 ]]; then
    PASS_ARGS=("--out" "/out" "${PASS_ARGS[@]}")
fi

[[ -n "${OUT_DIR}" ]] || die "--out cannot be empty"

HOST_MOUNT="${OUT_DIR}"
if [[ -n "${RUN_ID}" && "$(basename -- "${OUT_DIR}")" == "${RUN_ID}" ]]; then
    HOST_MOUNT="$(dirname -- "${OUT_DIR}")"
fi

mkdir -p "${HOST_MOUNT}"
HOST_MOUNT="$(cd "${HOST_MOUNT}" && pwd)"

command -v docker >/dev/null 2>&1 || die "docker is not installed or not on PATH"

DOCKER_TTY_ARGS=(-i)
if [[ -t 0 && -t 1 ]]; then
    DOCKER_TTY_ARGS=(-it)
fi

exec docker run "${DOCKER_TTY_ARGS[@]}" --rm \
    --privileged \
    --pid=host \
    --net=host \
    -v "${HOST_MOUNT}":/out \
    -v /etc/localtime:/etc/localtime:ro \
    -v /tmp:/tmp:ro \
    -v /sys/kernel/debug:/sys/kernel/debug:rw \
    -v /sys/kernel/tracing:/sys/kernel/tracing:rw \
    -v /sys/fs/bpf:/sys/fs/bpf:rw \
    -v /sys/fs/cgroup:/sys/fs/cgroup:ro \
    -v /lib/modules:/lib/modules:ro \
    -v /usr/src:/usr/src:ro \
    -e "WCCKIT_HOST_UID=$(id -u)" \
    -e "WCCKIT_HOST_GID=$(id -g)" \
    "${IMAGE}" \
    wcckit_profile_pipeline.sh "${PASS_ARGS[@]}"
