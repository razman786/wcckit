#!/usr/bin/env bash
# Copyright (c) 2026, Raz.
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
IFS=$'\n\t'

IMAGE="${WCCKIT_PIPELINE_IMAGE:-wcckit/pipeline-profiler:24.04}"
OUT_DIR="${WCCKIT_OUT_DIR:-runs}"
WORKDIR_HOST="${PWD}"
RUN_ID=""
OUT_ARG_SET=0
PASS_ARGS=()
CMD=()

usage() {
    cat <<EOF
Start an AMD uProf Classic Roofline collection in the WCCKIT profiler image.

Usage:
  ${0##*/} [options] -- command [args...]

Common options:
  --image IMAGE             Collector image. Default: ${IMAGE}
  --out DIR                 Host output root or run directory. Default: ${OUT_DIR}
  --workdir DIR             Host workload directory mounted as /work. Default: current directory.
  --run-id RUN_ID           Run identifier. Defaults inside the container.
  --pipeline NAME           Pipeline/application name, for example DDFacet.
  --influx-url URL          InfluxDB URL, for example http://127.0.0.1:8086.
  --influx-org ORG          InfluxDB organisation.
  --influx-bucket BUCKET    InfluxDB bucket.
  --influx-token TOKEN      InfluxDB API token.
  --msr                     Pass --msr to AMDuProfPcm roofline.
  --read-smbios             Pass --read-smbios to AMDuProfPcm roofline.
  -h, --help                Print this help.

Examples:
  ${0##*/} --pipeline DDFacet --run-id ddfacet-roofline-001 --out runs -- DDFacet --help
  ${0##*/} --workdir /data/pipeline --pipeline MyPipeline -- ./run_pipeline.sh
EOF
}

die() { printf '[wcckit-amd-roofline] error: %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --image) [[ $# -ge 2 ]] || die "--image requires a value"; IMAGE="$2"; shift 2 ;;
        --image=*) IMAGE="${1#*=}"; shift ;;
        --workdir) [[ $# -ge 2 ]] || die "--workdir requires a value"; WORKDIR_HOST="$2"; shift 2 ;;
        --workdir=*) WORKDIR_HOST="${1#*=}"; shift ;;
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
        --)
            shift
            CMD=("$@")
            break
            ;;
        *) PASS_ARGS+=("$1"); shift ;;
    esac
done

[[ ${#CMD[@]} -gt 0 ]] || die "a workload command is required after --"
if [[ "${OUT_ARG_SET}" -eq 0 ]]; then PASS_ARGS=("--out" "/out" "${PASS_ARGS[@]}"); fi
[[ -n "${OUT_DIR}" ]] || die "--out cannot be empty"
[[ -d "${WORKDIR_HOST}" ]] || die "--workdir does not exist or is not a directory: ${WORKDIR_HOST}"

HOST_MOUNT="${OUT_DIR}"
if [[ -n "${RUN_ID}" && "$(basename -- "${OUT_DIR}")" == "${RUN_ID}" ]]; then
    HOST_MOUNT="$(dirname -- "${OUT_DIR}")"
fi
mkdir -p "${HOST_MOUNT}"
HOST_MOUNT="$(cd "${HOST_MOUNT}" && pwd)"
WORKDIR_HOST="$(cd "${WORKDIR_HOST}" && pwd)"

command -v docker >/dev/null 2>&1 || die "docker is not installed or not on PATH"

DOCKER_TTY_ARGS=(-i)
if [[ -t 0 && -t 1 ]]; then DOCKER_TTY_ARGS=(-it); fi

exec docker run "${DOCKER_TTY_ARGS[@]}" --rm \
    --privileged \
    --pid=host \
    --net=host \
    -v "${HOST_MOUNT}":/out \
    -v "${WORKDIR_HOST}":/work \
    -v /etc/localtime:/etc/localtime:ro \
    -v /tmp:/tmp:rw \
    -v /sys/kernel/debug:/sys/kernel/debug:rw \
    -v /sys/kernel/tracing:/sys/kernel/tracing:rw \
    -v /sys/fs/bpf:/sys/fs/bpf:rw \
    -v /sys/fs/cgroup:/sys/fs/cgroup:ro \
    -v /lib/modules:/lib/modules:ro \
    -v /usr/src:/usr/src:ro \
    -e "WCCKIT_HOST_UID=$(id -u)" \
    -e "WCCKIT_HOST_GID=$(id -g)" \
    -w /work \
    "${IMAGE}" \
    wcckit_amd_uprof_roofline.sh "${PASS_ARGS[@]}" -- "${CMD[@]}"
