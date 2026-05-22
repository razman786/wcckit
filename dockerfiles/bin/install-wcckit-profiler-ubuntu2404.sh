#!/usr/bin/env bash
# Copyright (c) 2026, Raz.
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
IFS=$'\n\t'

BASE_IMAGE="${WCCKIT_BASE_IMAGE:-wcckit/ubuntu-profiling-base:24.04}"
PROFILER_IMAGE="${WCCKIT_PROFILER_IMAGE:-wcckit/bcc-profiler:24.04}"
PIPELINE_IMAGE="${WCCKIT_PIPELINE_IMAGE:-wcckit/pipeline-profiler:24.04}"
INSTALL_PACKAGES=1
BUILD_IMAGES=1
INCLUDE_AMD_UPROF="${WCCKIT_INCLUDE_AMD_UPROF:-auto}"
AMD_UPROF_DEB="${WCCKIT_AMD_UPROF_DEB:-}"
AMD_UPROF_URL="${WCCKIT_AMD_UPROF_URL:-}"
AMD_UPROF_MD5="${WCCKIT_AMD_UPROF_MD5:-32ab052e45b8c5ffebc8bda901baef02}"
INCLUDE_AMD_ESMI="${WCCKIT_INCLUDE_AMD_ESMI:-1}"
AMD_ESMI_URL="${WCCKIT_AMD_ESMI_URL:-https://download.amd.com/developer/eula/e-smi/e-smi-tool-5.2.1.deb}"
AMD_ESMI_SHA256="${WCCKIT_AMD_ESMI_SHA256:-60fd82816e82605619f58f1825829c3e1e30be27de8bc2e884016893c298cf5b}"
USE_SUDO=""
DEPLOYMENT_MODE="${WCCKIT_DEPLOYMENT_MODE:-all}"

usage() {
    cat <<EOF
Install host dependencies and build WCCKIT profiler Docker images on Ubuntu 24.04.

Usage:
  ${0##*/} [options]

Options:
  --all                    Install/build both viewer support and collector images. Default.
  --viewer-only            Install host Docker support only; do not build collector images.
  --collector-only         Install host Docker support and build collector images only.
  --base-image IMAGE       Base image tag. Default: ${BASE_IMAGE}
  --profiler-image IMAGE   BCC profiler image tag. Default: ${PROFILER_IMAGE}
  --pipeline-image IMAGE   Combined pipeline profiler image tag. Default: ${PIPELINE_IMAGE}
  --amd-uprof-deb PATH     AMD μProf .deb to install into the pipeline image.
  --amd-uprof-url URL      AMD μProf .deb URL to download during the Docker build.
  --amd-uprof-md5 MD5      AMD μProf .deb MD5 checksum. Defaults to AMD μProf 5.3 MD5.
  --no-amd-uprof           Build the pipeline image without AMD μProf, even if a local .deb is present.
  --amd-esmi-url URL       AMD e-smi .deb URL. Default: official AMD e-smi 5.2.1 URL.
  --amd-esmi-sha256 SHA    AMD e-smi .deb SHA256 checksum.
  --no-amd-esmi            Build the pipeline image without downloading AMD e-smi.
  --no-apt                 Skip host package installation.
  --no-build               Skip Docker image builds.
  -h, --help               Print this help.

Environment:
  WCCKIT_BASE_IMAGE         Base image tag override.
  WCCKIT_PROFILER_IMAGE     BCC profiler image tag override.
  WCCKIT_PIPELINE_IMAGE     Combined pipeline profiler image tag override.
  WCCKIT_INCLUDE_AMD_UPROF  auto, 1, or 0. Default: auto-detect local AMD μProf .deb.
  WCCKIT_AMD_UPROF_DEB      AMD μProf .deb path.
  WCCKIT_AMD_UPROF_URL      AMD μProf .deb URL.
  WCCKIT_AMD_UPROF_MD5      AMD μProf .deb MD5 checksum. Defaults to AMD μProf 5.3 MD5.
  WCCKIT_INCLUDE_AMD_ESMI   1 or 0. Default: 1 for collector builds.
  WCCKIT_AMD_ESMI_URL       AMD e-smi .deb URL.
  WCCKIT_AMD_ESMI_SHA256    AMD e-smi .deb SHA256 checksum.
  WCCKIT_DEPLOYMENT_MODE    all, viewer, or collector. Default: all.

This script installs host-side dependencies needed to build or run the selected
Docker deployment role. It does not start any privileged profiling container.
Use --viewer-only on a laptop/desktop that only runs Grafana/InfluxDB/Pyroscope.
Use --collector-only on a compute node that only runs the privileged collector.
Default collector builds do not require AMD μProf. To build AMD μProf into the
pipeline image, place the browser-approved AMD μProf .deb in the repo root or
pass --amd-uprof-deb/--amd-uprof-url. A local amduprof_*.deb in the repo root is
auto-detected. Initiating an AMD-enabled build is treated as the user's
instruction to install AMD μProf under AMD's EULA.

AMD e-smi is downloaded into collector images by default from AMD's public .deb
URL and is used for socket-energy based power metrics. Use --no-amd-esmi to skip
that download, for example in offline or CI-style builds.
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

has_dpkg_package() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

explain_containerd_conflict() {
    cat >&2 <<'EOF'
[wcckit-profiler-install] Docker package conflict detected.

Ubuntu's docker.io package uses the Ubuntu containerd package.
Docker CE from download.docker.com uses containerd.io. These two package
families conflict if mixed on the same host.

Choose one Docker packaging path:

  Option A: keep an existing Docker CE install and rerun WCCKIT without apt:
    dockerfiles/bin/install-wcckit-profiler-ubuntu2404.sh --no-apt

  Option B: use Ubuntu docker.io packages for WCCKIT:
    sudo apt-get remove docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo apt-get install docker.io docker-compose-v2 git ca-certificates curl

  Option C: use Docker CE packages:
    sudo apt-get remove docker.io containerd runc
    sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

Do not install docker.io and containerd.io together.
EOF
}

install_host_packages() {
    choose_sudo
    log "installing host packages: git ca-certificates curl"
    ${USE_SUDO} apt-get update
    ${USE_SUDO} apt-get install -y git ca-certificates curl

    if command -v docker >/dev/null 2>&1; then
        log "docker command already exists; leaving the current Docker packaging unchanged"
    else
        if has_dpkg_package containerd.io; then
            explain_containerd_conflict
            die "containerd.io is installed but docker is not on PATH; fix Docker packaging or rerun with --no-apt after Docker works"
        fi
        log "installing Ubuntu Docker package: docker.io"
        if ! ${USE_SUDO} apt-get install -y docker.io; then
            explain_containerd_conflict
            die "failed to install docker.io"
        fi
    fi

    if [[ "${DEPLOYMENT_MODE}" != "collector" ]] && ! docker compose version >/dev/null 2>&1 && ! command -v docker-compose >/dev/null 2>&1; then
        log "installing Docker Compose v2 package if available"
        ${USE_SUDO} apt-get install -y docker-compose-v2 || warn "could not install docker-compose-v2; install Docker Compose before running the viewer stack"
    fi

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
    if [[ "${DEPLOYMENT_MODE}" = "viewer" ]]; then
        log "viewer-only mode selected; skipping collector image builds"
        return
    fi

    local root amd_deb_arg
    root="$(repo_root)"
    cd "${root}"
    amd_deb_arg="${AMD_UPROF_DEB}"
    if [[ "${INCLUDE_AMD_UPROF}" = "auto" ]]; then
        if [[ -n "${amd_deb_arg}" || -n "${AMD_UPROF_URL}" ]]; then
            INCLUDE_AMD_UPROF=1
        elif [[ -f amduprof_5.3-518_amd64.deb ]]; then
            amd_deb_arg="amduprof_5.3-518_amd64.deb"
            AMD_UPROF_DEB="${amd_deb_arg}"
            INCLUDE_AMD_UPROF=1
            log "auto-detected local AMD μProf package: ${amd_deb_arg}"
        else
            INCLUDE_AMD_UPROF=0
            log "AMD μProf package not found; building collector without AMD μProf"
        fi
    fi

    if [[ "${INCLUDE_AMD_UPROF}" = "1" && -n "${AMD_UPROF_DEB}" ]]; then
        local amd_deb_abs amd_deb_name
        [[ -f "${AMD_UPROF_DEB}" ]] || die "AMD μProf .deb not found: ${AMD_UPROF_DEB}"
        amd_deb_abs="$(cd "$(dirname "${AMD_UPROF_DEB}")" && pwd)/$(basename "${AMD_UPROF_DEB}")"
        amd_deb_name="$(basename "${AMD_UPROF_DEB}")"
        if [[ "${amd_deb_abs}" == "${root}/"* ]]; then
            amd_deb_arg="${amd_deb_abs#${root}/}"
        else
            mkdir -p third_party
            cp "${amd_deb_abs}" "third_party/${amd_deb_name}"
            amd_deb_arg="third_party/${amd_deb_name}"
            log "staged AMD μProf package into build context: ${amd_deb_arg}"
        fi
    fi

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

    local amd_build_args=()
    amd_build_args+=(--build-arg "INCLUDE_AMD_UPROF=${INCLUDE_AMD_UPROF}")
    amd_build_args+=(--build-arg "INCLUDE_AMD_ESMI=${INCLUDE_AMD_ESMI}")
    if [[ -n "${AMD_ESMI_URL}" ]]; then
        amd_build_args+=(--build-arg "AMD_ESMI_URL=${AMD_ESMI_URL}")
    fi
    if [[ -n "${AMD_ESMI_SHA256}" ]]; then
        amd_build_args+=(--build-arg "AMD_ESMI_SHA256=${AMD_ESMI_SHA256}")
    fi
    if [[ -n "${amd_deb_arg}" ]]; then
        amd_build_args+=(--build-arg "AMD_UPROF_DEB=${amd_deb_arg}")
    fi
    if [[ -n "${AMD_UPROF_URL}" ]]; then
        amd_build_args+=(--build-arg "AMD_UPROF_URL=${AMD_UPROF_URL}")
    fi
    if [[ -n "${AMD_UPROF_MD5}" ]]; then
        amd_build_args+=(--build-arg "AMD_UPROF_MD5=${AMD_UPROF_MD5}")
    fi

    if [[ "${INCLUDE_AMD_UPROF}" = "1" && -z "${amd_deb_arg}" && -z "${AMD_UPROF_URL}" ]]; then
        die "AMD μProf was requested but no package source was provided. Place amduprof_5.3-518_amd64.deb in the repo root, pass --amd-uprof-deb, pass --amd-uprof-url, or use --no-amd-uprof."
    fi

    if [[ "${INCLUDE_AMD_UPROF}" = "1" ]]; then
        log "AMD μProf is enabled; the Docker build will use the supplied or auto-detected .deb/URL."
        log "Initiating this AMD-enabled build is treated as acceptance of AMD's EULA by instruction of the build operator."
    fi

    log "building pipeline profiler image: ${PIPELINE_IMAGE} (INCLUDE_AMD_UPROF=${INCLUDE_AMD_UPROF}, INCLUDE_AMD_ESMI=${INCLUDE_AMD_ESMI})"
    docker build \
        -t "${PIPELINE_IMAGE}" \
        -f dockerfiles/profiling/pipeline/Dockerfile \
        --build-arg "BASE_IMAGE=${BASE_IMAGE}" \
        "${amd_build_args[@]}" \
        .
}

print_next_steps() {
    cat <<EOF

WCCKIT setup is ready for deployment mode: ${DEPLOYMENT_MODE}.
EOF

    if [[ "${DEPLOYMENT_MODE}" = "all" || "${DEPLOYMENT_MODE}" = "viewer" ]]; then
        cat <<EOF

Viewer laptop/desktop role:

  dockerfiles/bin/run-wcckit-viewer.sh up
  dockerfiles/bin/run-wcckit-ssh-tunnel.sh user@compute-node

For an Intel compute node where Grafana should read pcm-sensor-server through
SSH, start the tunnel from the laptop with:

  dockerfiles/bin/run-wcckit-ssh-tunnel.sh --pcm-sensor user@intel-compute-node
EOF
    fi

    if [[ "${DEPLOYMENT_MODE}" = "all" || "${DEPLOYMENT_MODE}" = "collector" ]]; then
        cat <<EOF

Collector compute-node role:

  dockerfiles/bin/run-wcckit-pipeline-overview.sh \\
    --pid <PID> --pipeline DDFacet --language python \\
    --hardware-counters none --influx-url http://127.0.0.1:18086

Example: profile a host pipeline PID and write an SVG flame graph to ./profile-output/perf.svg

  mkdir -p profile-output
  dockerfiles/bin/run-wcckit-profiler.sh --image ${PROFILER_IMAGE} --out ./profile-output -- \\
    wcckit_profile_cpu.sh --pid <PID> --duration 15 --frequency 99 --output /out/perf.svg

Find likely pipeline PIDs with commands such as:

  pgrep -af python
  pgrep -af DDFacet
  pgrep -af wsclean
  pgrep -af DP3
  pgrep -af casa
EOF
    fi

    printf '\n'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)
            DEPLOYMENT_MODE="all"
            BUILD_IMAGES=1
            shift
            ;;
        --viewer-only)
            DEPLOYMENT_MODE="viewer"
            BUILD_IMAGES=0
            INCLUDE_AMD_UPROF=0
            shift
            ;;
        --collector-only)
            DEPLOYMENT_MODE="collector"
            BUILD_IMAGES=1
            shift
            ;;
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
        --pipeline-image)
            [[ $# -ge 2 ]] || die "--pipeline-image requires a value"
            PIPELINE_IMAGE="$2"
            shift 2
            ;;
        --pipeline-image=*)
            PIPELINE_IMAGE="${1#*=}"
            shift
            ;;
        --amd-uprof-deb)
            [[ $# -ge 2 ]] || die "--amd-uprof-deb requires a value"
            AMD_UPROF_DEB="$2"
            INCLUDE_AMD_UPROF=1
            shift 2
            ;;
        --amd-uprof-deb=*)
            AMD_UPROF_DEB="${1#*=}"
            INCLUDE_AMD_UPROF=1
            shift
            ;;
        --amd-uprof-url)
            [[ $# -ge 2 ]] || die "--amd-uprof-url requires a value"
            AMD_UPROF_URL="$2"
            INCLUDE_AMD_UPROF=1
            shift 2
            ;;
        --amd-uprof-url=*)
            AMD_UPROF_URL="${1#*=}"
            INCLUDE_AMD_UPROF=1
            shift
            ;;
        --amd-uprof-md5)
            [[ $# -ge 2 ]] || die "--amd-uprof-md5 requires a value"
            AMD_UPROF_MD5="$2"
            shift 2
            ;;
        --amd-uprof-md5=*)
            AMD_UPROF_MD5="${1#*=}"
            shift
            ;;
        --no-amd-uprof)
            INCLUDE_AMD_UPROF=0
            shift
            ;;
        --amd-esmi-url)
            [[ $# -ge 2 ]] || die "--amd-esmi-url requires a value"
            AMD_ESMI_URL="$2"
            INCLUDE_AMD_ESMI=1
            shift 2
            ;;
        --amd-esmi-url=*)
            AMD_ESMI_URL="${1#*=}"
            INCLUDE_AMD_ESMI=1
            shift
            ;;
        --amd-esmi-sha256)
            [[ $# -ge 2 ]] || die "--amd-esmi-sha256 requires a value"
            AMD_ESMI_SHA256="$2"
            shift 2
            ;;
        --amd-esmi-sha256=*)
            AMD_ESMI_SHA256="${1#*=}"
            shift
            ;;
        --no-amd-esmi)
            INCLUDE_AMD_ESMI=0
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

case "${DEPLOYMENT_MODE}" in
    all|viewer|collector) ;;
    *) die "invalid deployment mode: ${DEPLOYMENT_MODE}; expected all, viewer, or collector" ;;
esac

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
