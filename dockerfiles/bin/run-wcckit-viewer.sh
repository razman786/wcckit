#!/usr/bin/env bash
# Copyright (c) 2026, Raz.
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
IFS=$'\n\t'

COMPOSE_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/viewer/influxdb-grafana/docker-compose.yml"
ACTION="up"

usage() {
    cat <<EOF
Run the WCCKIT InfluxDB + Grafana + Pyroscope viewer stack.

Usage:
  ${0##*/} [up|stop|status|logs|config]

Default action is up.

Development defaults:
  Grafana:  http://localhost:3000  admin / wcckit
  InfluxDB:  http://localhost:8086
  Pyroscope: http://localhost:4040
  Org:       wcckit
  Bucket:   wcckit
  Token:    wcckit-dev-token

PCM sensor bridge:
  WCCKIT_PCM_SENSOR_URL defaults to http://host.docker.internal:9738/persecond/
  Override it when scraping a remote Intel pcm-sensor-server.

These are local development defaults, not production secrets.
EOF
}

die() { printf '[wcckit-viewer] error: %s\n' "$*" >&2; exit 1; }
warn() { printf '[wcckit-viewer] warning: %s\n' "$*" >&2; }

wait_for_pyroscope() {
    command -v curl >/dev/null 2>&1 || { warn "curl not found; skipping Pyroscope readiness wait"; return 0; }
    printf 'Waiting for Pyroscope readiness'
    for _ in $(seq 1 90); do
        if [[ "$(curl -fsS http://127.0.0.1:4040/ready 2>/dev/null || true)" == "ready" ]]; then
            printf '\nPyroscope is ready for profile ingest and queries.\n'
            return 0
        fi
        printf '.'
        sleep 1
    done
    printf '\n'
    warn "Pyroscope did not report ready within 90 seconds; profile pushes may not be queryable yet"
}


if [[ $# -gt 0 ]]; then
    case "$1" in
        -h|--help) usage; exit 0 ;;
        up|start) ACTION="up" ;;
        stop|down) ACTION="stop" ;;
        status|ps) ACTION="status" ;;
        logs) ACTION="logs" ;;
        config) ACTION="config" ;;
        *) die "unknown action: $1" ;;
    esac
fi

command -v docker >/dev/null 2>&1 || die "docker is not installed or not on PATH"
if docker compose version >/dev/null 2>&1; then
    COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE=(docker-compose)
else
    die "docker compose or docker-compose is required"
fi

case "${ACTION}" in
    up)
        "${COMPOSE[@]}" -f "${COMPOSE_FILE}" up -d
        wait_for_pyroscope
        cat <<EOF

WCCKIT viewer stack is starting.

Grafana:   http://localhost:3000  admin / wcckit
InfluxDB:  http://localhost:8086
Pyroscope: http://localhost:4040
Org:       wcckit
Bucket:    wcckit
Token:     wcckit-dev-token

Pass these to the collector when pushing live points:
  --influx-url http://127.0.0.1:8086 --influx-org wcckit --influx-bucket wcckit --influx-token wcckit-dev-token

Pass this to the collector when pushing interactive folded profiles:
  --pyroscope-url http://127.0.0.1:4040 --push-profiles

The viewer also starts a Telegraf PCM bridge. It scrapes:
  ${WCCKIT_PCM_SENSOR_URL:-http://host.docker.internal:9738/persecond/}

To scrape a remote Intel PCM host instead:
  WCCKIT_PCM_SENSOR_URL=http://target-host:9738/persecond/ ${0##*/}
EOF
        ;;
    stop) "${COMPOSE[@]}" -f "${COMPOSE_FILE}" down ;;
    status) "${COMPOSE[@]}" -f "${COMPOSE_FILE}" ps ;;
    logs) "${COMPOSE[@]}" -f "${COMPOSE_FILE}" logs -f ;;
    config) "${COMPOSE[@]}" -f "${COMPOSE_FILE}" config ;;
esac
