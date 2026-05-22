#!/usr/bin/env bash
# Copyright (c) 2026, Raz.
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
IFS=$'\n\t'

REMOTE=""
INFLUX_REMOTE_PORT="${WCCKIT_TUNNEL_INFLUX_PORT:-18086}"
PYROSCOPE_REMOTE_PORT="${WCCKIT_TUNNEL_PYROSCOPE_PORT:-14040}"
GRAFANA_REMOTE_PORT="${WCCKIT_TUNNEL_GRAFANA_PORT:-13000}"
LOCAL_INFLUX_PORT="${WCCKIT_LOCAL_INFLUX_PORT:-8086}"
LOCAL_PYROSCOPE_PORT="${WCCKIT_LOCAL_PYROSCOPE_PORT:-4040}"
LOCAL_GRAFANA_PORT="${WCCKIT_LOCAL_GRAFANA_PORT:-3000}"
PCM_SENSOR_FORWARD=0
PCM_LOCAL_PORT="${WCCKIT_TUNNEL_PCM_LOCAL_PORT:-9738}"
PCM_REMOTE_PORT="${WCCKIT_TUNNEL_PCM_REMOTE_PORT:-9738}"
PCM_BIND_ADDRESS="${WCCKIT_TUNNEL_PCM_BIND_ADDRESS:-auto}"
FORWARD_GRAFANA=0
SSH_ARGS=()

usage() {
    cat <<EOF
Open an SSH reverse tunnel from a laptop viewer to a compute node.

Run this on the laptop where dockerfiles/bin/run-wcckit-viewer.sh is running.
It exposes the laptop's InfluxDB and Pyroscope ports on the remote compute node,
so a collector running over SSH can write to localhost on the compute node.

Usage:
  ${0##*/} [options] user@compute-node

Options:
  --remote HOST             SSH target, alternative to positional HOST.
  --influx-remote-port N    Remote compute-node port for InfluxDB. Default: ${INFLUX_REMOTE_PORT}
  --pyroscope-remote-port N Remote compute-node port for Pyroscope. Default: ${PYROSCOPE_REMOTE_PORT}
  --grafana                 Also expose Grafana on the compute node.
  --grafana-remote-port N   Remote compute-node port for Grafana. Default: ${GRAFANA_REMOTE_PORT}
  --pcm-sensor              Forward remote pcm-sensor-server to the laptop for Grafana.
  --pcm-bind-address ADDR   Laptop address for the PCM forward. Default: ${PCM_BIND_ADDRESS}
                            auto detects the Docker bridge gateway for Telegraf.
  --pcm-local-port N        Laptop port for the PCM sensor forward. Default: ${PCM_LOCAL_PORT}
  --pcm-remote-port N       Compute-node pcm-sensor-server port. Default: ${PCM_REMOTE_PORT}
  --ssh-arg ARG             Extra argument passed to ssh. Can be repeated.
  -h, --help                Print this help.

After the tunnel is open, run the collector on the compute node with:
  --influx-url http://127.0.0.1:${INFLUX_REMOTE_PORT}
  --pyroscope-url http://127.0.0.1:${PYROSCOPE_REMOTE_PORT}

Example:
  ${0##*/} user@compute-node
  ${0##*/} --pcm-sensor user@intel-compute-node
  ${0##*/} --pcm-sensor --pcm-bind-address 172.17.0.1 user@intel-compute-node
EOF
}

die() {
    printf '[wcckit-ssh-tunnel] error: %s\n' "$*" >&2
    exit 1
}

positive_port() {
    [[ "$1" =~ ^[1-9][0-9]*$ ]] && (( "$1" <= 65535 ))
}

detect_docker_bridge_gateway() {
    command -v docker >/dev/null 2>&1 || return 1
    docker network inspect bridge --format '{{(index .IPAM.Config 0).Gateway}}' 2>/dev/null | head -n 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --remote) [[ $# -ge 2 ]] || die "--remote requires a value"; REMOTE="$2"; shift 2 ;;
        --remote=*) REMOTE="${1#*=}"; shift ;;
        --influx-remote-port) [[ $# -ge 2 ]] || die "--influx-remote-port requires a value"; INFLUX_REMOTE_PORT="$2"; shift 2 ;;
        --influx-remote-port=*) INFLUX_REMOTE_PORT="${1#*=}"; shift ;;
        --pyroscope-remote-port) [[ $# -ge 2 ]] || die "--pyroscope-remote-port requires a value"; PYROSCOPE_REMOTE_PORT="$2"; shift 2 ;;
        --pyroscope-remote-port=*) PYROSCOPE_REMOTE_PORT="${1#*=}"; shift ;;
        --grafana) FORWARD_GRAFANA=1; shift ;;
        --grafana-remote-port) [[ $# -ge 2 ]] || die "--grafana-remote-port requires a value"; GRAFANA_REMOTE_PORT="$2"; shift 2 ;;
        --grafana-remote-port=*) GRAFANA_REMOTE_PORT="${1#*=}"; shift ;;
        --pcm-sensor) PCM_SENSOR_FORWARD=1; shift ;;
        --pcm-bind-address) [[ $# -ge 2 ]] || die "--pcm-bind-address requires a value"; PCM_BIND_ADDRESS="$2"; shift 2 ;;
        --pcm-bind-address=*) PCM_BIND_ADDRESS="${1#*=}"; shift ;;
        --pcm-local-port) [[ $# -ge 2 ]] || die "--pcm-local-port requires a value"; PCM_LOCAL_PORT="$2"; shift 2 ;;
        --pcm-local-port=*) PCM_LOCAL_PORT="${1#*=}"; shift ;;
        --pcm-remote-port) [[ $# -ge 2 ]] || die "--pcm-remote-port requires a value"; PCM_REMOTE_PORT="$2"; shift 2 ;;
        --pcm-remote-port=*) PCM_REMOTE_PORT="${1#*=}"; shift ;;
        --ssh-arg) [[ $# -ge 2 ]] || die "--ssh-arg requires a value"; SSH_ARGS+=("$2"); shift 2 ;;
        --ssh-arg=*) SSH_ARGS+=("${1#*=}"); shift ;;
        *)
            if [[ -z "${REMOTE}" ]]; then REMOTE="$1"; else SSH_ARGS+=("$1"); fi
            shift
            ;;
    esac
done

[[ -n "${REMOTE}" ]] || die "missing SSH target, for example user@compute-node"
positive_port "${INFLUX_REMOTE_PORT}" || die "invalid Influx remote port: ${INFLUX_REMOTE_PORT}"
positive_port "${PYROSCOPE_REMOTE_PORT}" || die "invalid Pyroscope remote port: ${PYROSCOPE_REMOTE_PORT}"
positive_port "${GRAFANA_REMOTE_PORT}" || die "invalid Grafana remote port: ${GRAFANA_REMOTE_PORT}"
positive_port "${PCM_LOCAL_PORT}" || die "invalid PCM local port: ${PCM_LOCAL_PORT}"
positive_port "${PCM_REMOTE_PORT}" || die "invalid PCM remote port: ${PCM_REMOTE_PORT}"
if [[ "${PCM_SENSOR_FORWARD}" -eq 1 && "${PCM_BIND_ADDRESS}" == "auto" ]]; then
    PCM_BIND_ADDRESS="$(detect_docker_bridge_gateway || true)"
    if [[ -z "${PCM_BIND_ADDRESS}" ]]; then
        PCM_BIND_ADDRESS="127.0.0.1"
        printf '[wcckit-ssh-tunnel] warning: could not detect Docker bridge gateway; using %s for PCM forward\n' "${PCM_BIND_ADDRESS}" >&2
    fi
fi
command -v ssh >/dev/null 2>&1 || die "ssh is not installed or not on PATH"

cmd=(
    ssh
    -N
    -o ExitOnForwardFailure=yes
    -R "${INFLUX_REMOTE_PORT}:127.0.0.1:${LOCAL_INFLUX_PORT}"
    -R "${PYROSCOPE_REMOTE_PORT}:127.0.0.1:${LOCAL_PYROSCOPE_PORT}"
)

if [[ "${FORWARD_GRAFANA}" -eq 1 ]]; then
    cmd+=(-R "${GRAFANA_REMOTE_PORT}:127.0.0.1:${LOCAL_GRAFANA_PORT}")
fi

if [[ "${PCM_SENSOR_FORWARD}" -eq 1 ]]; then
    cmd+=(-L "${PCM_BIND_ADDRESS}:${PCM_LOCAL_PORT}:127.0.0.1:${PCM_REMOTE_PORT}")
fi

cmd+=("${SSH_ARGS[@]}" "${REMOTE}")

cat >&2 <<EOF
[wcckit-ssh-tunnel] opening reverse tunnel to ${REMOTE}
[wcckit-ssh-tunnel] compute node collector endpoints:
  InfluxDB:  http://127.0.0.1:${INFLUX_REMOTE_PORT}
  Pyroscope: http://127.0.0.1:${PYROSCOPE_REMOTE_PORT}
EOF
if [[ "${FORWARD_GRAFANA}" -eq 1 ]]; then
    printf '[wcckit-ssh-tunnel] remote Grafana view: http://127.0.0.1:%s\n' "${GRAFANA_REMOTE_PORT}" >&2
fi
if [[ "${PCM_SENSOR_FORWARD}" -eq 1 ]]; then
    cat >&2 <<EOF
[wcckit-ssh-tunnel] laptop Intel PCM sensor endpoint:
  http://${PCM_BIND_ADDRESS}:${PCM_LOCAL_PORT}/persecond/
[wcckit-ssh-tunnel] Grafana Docker should use:
  WCCKIT_PCM_SENSOR_URL=http://${PCM_BIND_ADDRESS}:${PCM_LOCAL_PORT}/persecond/
EOF
fi

exec "${cmd[@]}"
