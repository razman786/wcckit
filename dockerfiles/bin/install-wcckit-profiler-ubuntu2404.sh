#!/usr/bin/env bash
# Copyright (c) 2026, Dr Rahim Lakhoo.
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
IFS=$'\n\t'

BASE_IMAGE="${WCCKIT_BASE_IMAGE:-wcckit/ubuntu-profiling-base:24.04}"
PROFILER_IMAGE="${WCCKIT_PROFILER_IMAGE:-wcckit/bcc-profiler:24.04}"
INSTALL_PACKAGES=1
BUILD_IMAGES=1
USE_SUDO=""

usage() {
    cat <<EOF
Install host dependencies and build WCCKIT profiler Docker images on Ubuntu 24.04.

Usage:
  ${0##*/} [options]

Options:
  --base-image IMAGE      Base image tag. Default: ${BASE_IMAGE}
  --profiler-image IMAGE  Profiler image tag. Default: ${PROFILER_IMAGE}
  --no-apt               Skip host package installation.
  --no-build             Skip Docker image builds.
  -h, --help             Print this help.

Environment:
  WCCKIT_BASE_IMAGE      Base image tag override.
  WCCKIT_PROFILER_IMAGE  Profiler image tag override.

This script installs only host-side dependencies needed to build/run the Docker
images. It does not start any privileged profiling container.
EOF
}

log() {
    printf '[wcckit-profiler-install] %s\n' "$*"
}

warn() {
    printf '[wcckit-profiler-install] warning: %s\n' "$*" >&2
}

die() {
    printf '[wcckit-profiler-install] error: %s\n' "$*" >&2
    exit 1
}

repo_root() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    cd "${script_dir}/../.." && pwd
}

check_ubuntu_2404() {
    [[ -r /etc/os-release ]] || die "/etc/os-release not found; this installer targets Ubuntu 24.04"
    # shellcheck disable=SC1091
    . /etc/os-release
    if [[ "${ID:-}" != "ubuntu" || "${VERSION_ID:-}" != "24.04" ]]; then
        die "unsupported host ${PRETTY_NAME:-unknown}; this installer targets Ubuntu 24.04"
    fi
    log "host OS: ${PRETTY_NAME:-Ubuntu 24.04}"
}

choose_sudo() {
    if [[ "${EUID}" -eq 0 ]]; then
        USE_SUDO=""
    elif command -v sudo >/dev/null 2>&1; then
        USE_SUDO="sudo"
    else
        die "sudo is required for package installation when not running as root"
    fi
}

install_host_packages() {
    choose_sudo
    log "installing host packages: docker.io git ca-certificates curl"
    ${USE_SUDO} apt-get update
    ${USE_SUDO} apt-get install -y docker.io git ca-certificates curl
    if command -v systemctl >/dev/null 2>&1; then
        ${USE_SUDO} systemctl enable --now docker || warn "could not enable/start docker via systemctl; check Docker service manually"
    fi
}

check_docker_access() {
    command -v docker >/dev/null 2>&1 || die "docker is not installed or not on PATH"
    if docker ps >/dev/null 2>&1; then
        log "docker daemon is reachable"
        return
    fi

    warn "docker is installed but this user cannot access the daemon"
    warn "if Docker was just installed, run: sudo usermod -aG docker \"$USER\""
    warn "then log out and back in, or run: newgrp docker"
    die "docker daemon access is required before building images"
}

build_images() {
    local root
    root="$(repo_root)"
    cd "${root}"

    log "building base image: ${BASE_IMAGE}"
    docker build \
        -t "${BASE_IMAGE}" \
        -f dockerfiles/base/ubuntu-24.04.4/Dockerfile \
        .

    log "building profiler image: ${PROFILER_IMAGE}"
    docker build \
        -t "${PROFILER_IMAGE}" \
        -f dockerfiles/profiling/bcc/Dockerfile \
        --build-arg "BASE_IMAGE=${BASE_IMAGE}" \
        .
}

print_next_steps() {
    cat <<EOF

WCCKIT profiler images are ready.

Example: profile a host pipeline PID and write an SVG flame graph to ./profile-output/perf.svg

  mkdir -p profile-output
  dockerfiles/bin/run-wcckit-profiler.sh --image ${PROFILER_IMAGE} --out ./profile-output -- \\
    wcckit_profile_cpu.sh --pid <PID> --duration 15 --frequency 99 --output /out/perf.svg

Find likely pipeline PIDs with commands such as:

  pgrep -af python
  pgrep -af wsclean
  pgrep -af DP3
  pgrep -af casa

EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --base-image)
            [[ $# -ge 2 ]] || die "--base-image requires a value"
            BASE_IMAGE="$2"
            shift 2
            ;;
        --base-image=*)
            BASE_IMAGE="${1#*=}"
            shift
            ;;
        --profiler-image)
            [[ $# -ge 2 ]] || die "--profiler-image requires a value"
            PROFILER_IMAGE="$2"
            shift 2
            ;;
        --profiler-image=*)
            PROFILER_IMAGE="${1#*=}"
            shift
            ;;
        --no-apt)
            INSTALL_PACKAGES=0
            shift
            ;;
        --no-build)
            BUILD_IMAGES=0
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

check_ubuntu_2404

if [[ "${INSTALL_PACKAGES}" -eq 1 ]]; then
    install_host_packages
else
    log "skipping host package installation"
fi

check_docker_access

if [[ "${BUILD_IMAGES}" -eq 1 ]]; then
    build_images
else
    log "skipping Docker image builds"
fi

print_next_steps
