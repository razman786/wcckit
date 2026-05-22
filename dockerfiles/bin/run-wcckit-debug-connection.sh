#!/usr/bin/env bash
# Copyright (c) 2026, Raz.
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
IFS=$'\n\t'

ROLE="auto"
INFLUX_URL="${WCCKIT_DEBUG_INFLUX_URL:-http://127.0.0.1:18086}"
PYROSCOPE_URL="${WCCKIT_DEBUG_PYROSCOPE_URL:-http://127.0.0.1:14040}"
GRAFANA_URL="${WCCKIT_DEBUG_GRAFANA_URL:-http://127.0.0.1:3000}"
PCM_URL="${WCCKIT_DEBUG_PCM_URL:-http://127.0.0.1:9738/persecond/}"
TELEGRAF_PCM_URL="${WCCKIT_PCM_SENSOR_URL:-http://host.docker.internal:9738/persecond/}"
TELEGRAF_CONTAINER="${WCCKIT_TELEGRAF_CONTAINER:-wcckit-telegraf-pcm}"
SHOW_LOGS=0
FAILURES=0
WARNINGS=0

usage() {
    cat <<EOF
Debug WCCKIT viewer, SSH tunnel, and Intel PCM connectivity.

Run on the laptop/desktop viewer or on the compute-node collector. The checks are
read-only and do not start profilers, change system settings, or require root.

Usage:
  ${0##*/} [options]

Options:
  --role viewer|collector|auto   Which side to test. Default: ${ROLE}
  --influx-url URL               Collector-side Influx URL. Default: ${INFLUX_URL}
  --pyroscope-url URL            Collector-side Pyroscope URL. Default: ${PYROSCOPE_URL}
  --grafana-url URL              Viewer-side Grafana URL. Default: ${GRAFANA_URL}
  --pcm-url URL                  PCM sensor URL to test. Default: ${PCM_URL}
  --telegraf-pcm-url URL         URL Telegraf should scrape. Default: ${TELEGRAF_PCM_URL}
  --telegraf-container NAME      Telegraf container name. Default: ${TELEGRAF_CONTAINER}
  --show-logs                    Show recent Telegraf logs when running viewer checks.
  -h, --help                     Print this help.

Typical collector-side tunnel endpoints:
  --influx-url http://127.0.0.1:18086
  --pyroscope-url http://127.0.0.1:14040

Typical Intel PCM endpoint on the compute node or laptop PCM forward:
  --pcm-url http://127.0.0.1:9738/persecond/
EOF
}

note() { printf '\n== %s ==\n' "$*"; }
ok() { printf '[ OK ] %s\n' "$*"; }
warn() { WARNINGS=$((WARNINGS + 1)); printf '[WARN] %s\n' "$*"; }
fail() { FAILURES=$((FAILURES + 1)); printf '[FAIL] %s\n' "$*"; }
info() { printf '[INFO] %s\n' "$*"; }

url_port() {
    local url="$1" rest port
    rest="${url#*://}"
    rest="${rest%%/*}"
    port="${rest##*:}"
    if [[ "${port}" == "${rest}" ]]; then
        case "${url}" in
            http://*) port=80 ;;
            https://*) port=443 ;;
            *) port="" ;;
        esac
    fi
    printf '%s' "${port}"
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || { fail "$1 is not installed or not on PATH"; return 1; }
}

http_code() {
    local url="$1" accept="${2:-}" out code
    out="$(mktemp 2>/dev/null || printf '/tmp/wcckit-debug-http.%s' "$$")"
    if [[ -n "${accept}" ]]; then
        code="$(curl -sS -m 4 -H "Accept: ${accept}" -o "${out}" -w '%{http_code}' "${url}" 2>/tmp/wcckit-debug-curl.err || true)"
    else
        code="$(curl -sS -m 4 -o "${out}" -w '%{http_code}' "${url}" 2>/tmp/wcckit-debug-curl.err || true)"
    fi
    printf '%s\n' "${code:-000}"
    rm -f "${out}" /tmp/wcckit-debug-curl.err 2>/dev/null || true
}

check_http_ok() {
    local label="$1" url="$2" accept="${3:-}" code
    if ! need_cmd curl; then return; fi
    code="$(http_code "${url}" "${accept}")"
    case "${code}" in
        200|204) ok "${label}: ${url} returned HTTP ${code}" ;;
        000) fail "${label}: ${url} is not reachable" ;;
        *) fail "${label}: ${url} returned HTTP ${code}" ;;
    esac
}

check_pcm_endpoint() {
    local label="$1" url="$2" code_json code_prom code_plain
    if ! need_cmd curl; then return; fi

    code_plain="$(http_code "${url}")"
    code_json="$(http_code "${url}" 'application/json')"
    code_prom="$(http_code "${url}" 'text/plain; version=0.0.4')"

    if [[ "${code_json}" == "200" ]]; then
        ok "${label}: ${url} serves JSON with Accept: application/json"
    elif [[ "${code_prom}" == "200" ]]; then
        ok "${label}: ${url} serves Prometheus text with Accept: text/plain; version=0.0.4"
    elif [[ "${code_plain}" == "406" ]]; then
        fail "${label}: ${url} is reachable but returned 406 without a supported Accept header; JSON/Prometheus Accept checks also failed"
    elif [[ "${code_plain}" == "000" && "${code_json}" == "000" && "${code_prom}" == "000" ]]; then
        fail "${label}: ${url} is not reachable; pcm-sensor-server or SSH PCM forward is probably not listening"
    else
        fail "${label}: unexpected HTTP statuses plain=${code_plain} json=${code_json} prometheus=${code_prom}"
    fi
}

check_port_listener() {
    local port="$1" label="$2"
    if command -v ss >/dev/null 2>&1; then
        if ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)${port}$"; then
            ok "${label}: TCP port ${port} is listening"
        else
            warn "${label}: no listener found on TCP port ${port}"
        fi
    else
        warn "ss is not installed; skipping local listener check for port ${port}"
    fi
}

check_latest_pcm_logs() {
    local run_dir log status code
    run_dir="$(find runs -path '*/logs/pcm.log' -print 2>/dev/null | sort | tail -1)"
    if [[ -n "${run_dir}" ]]; then
        run_dir="$(dirname "$(dirname "${run_dir}")")"
        log="${run_dir}/logs/pcm.log"
        status="${run_dir}/logs/pcm.status"
        info "latest PCM run directory: ${run_dir}"
    else
        warn "no runs/*/logs/pcm.log file found yet"
        return
    fi

    if [[ -r "${status}" ]]; then
        code="$(tr -cd '0-9' < "${status}" 2>/dev/null || true)"
        info "PCM status file: ${status} -> ${code:-unknown}"
        if [[ "${code}" == "124" ]]; then
            info "status 124 usually means timeout stopped pcm-sensor-server at the end of a bounded run"
        fi
    else
        warn "no PCM status file for latest PCM run: ${status}"
    fi

    info "PCM log: ${log}"
    tail -20 "${log}" 2>/dev/null | sed 's/^/       /'
    if grep -q 'Starting plain HTTP server' "${log}" 2>/dev/null && grep -Eq 'signal 15|Stopping HTTPServer|exiting with exit code' "${log}" 2>/dev/null; then
        info "PCM server started, then stopped. If no port is listening now, run the debugger while the collector is still active."
    fi
}

viewer_checks() {
    note "Viewer-side checks"
    check_http_ok "Grafana" "${GRAFANA_URL}/api/health"
    check_http_ok "InfluxDB" "http://127.0.0.1:8086/health"
    check_http_ok "Pyroscope" "http://127.0.0.1:4040/ready"

    if command -v docker >/dev/null 2>&1; then
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "${TELEGRAF_CONTAINER}"; then
            ok "Telegraf PCM container is running: ${TELEGRAF_CONTAINER}"
            info "Telegraf PCM URL should be: ${TELEGRAF_PCM_URL}"
            if docker exec "${TELEGRAF_CONTAINER}" sh -lc 'command -v wget >/dev/null 2>&1 || command -v curl >/dev/null 2>&1' >/dev/null 2>&1; then
                if docker exec "${TELEGRAF_CONTAINER}" sh -lc "if command -v wget >/dev/null 2>&1; then wget -q -T 4 -O /dev/null --header='Accept: application/json' '${TELEGRAF_PCM_URL}'; else curl -fsS -m 4 -H 'Accept: application/json' -o /dev/null '${TELEGRAF_PCM_URL}'; fi" >/dev/null 2>&1; then
                    ok "Telegraf container can reach PCM URL: ${TELEGRAF_PCM_URL}"
                else
                    fail "Telegraf container cannot reach PCM URL: ${TELEGRAF_PCM_URL}"
                    info "If using an SSH PCM forward, confirm the laptop can curl ${PCM_URL} with Accept: application/json."
                    info "If host.docker.internal fails, restart viewer with WCCKIT_PCM_SENSOR_URL=http://<laptop-ip>:9738/persecond/ or a Docker bridge gateway URL."
                fi
            else
                warn "Telegraf container has neither wget nor curl; cannot test PCM URL from inside the container"
            fi
            if [[ "${SHOW_LOGS}" -eq 1 ]]; then
                info "recent Telegraf logs:"
                docker logs --tail 80 "${TELEGRAF_CONTAINER}" 2>&1 | sed 's/^/       /'
            fi
        else
            warn "Telegraf PCM container is not running: ${TELEGRAF_CONTAINER}"
        fi
    else
        warn "docker is not installed or not on PATH; skipping viewer container checks"
    fi

    note "Viewer-side PCM forward check"
    check_port_listener "$(url_port "${PCM_URL}")" "Laptop PCM forward"
    check_pcm_endpoint "Laptop PCM endpoint" "${PCM_URL}"
}

collector_checks() {
    note "Collector-side tunnel checks"
    check_http_ok "InfluxDB reverse tunnel" "${INFLUX_URL%/}/health"
    check_http_ok "Pyroscope reverse tunnel" "${PYROSCOPE_URL%/}/ready"

    note "Collector-side Intel PCM checks"
    check_port_listener "9738" "Compute-node pcm-sensor-server"
    check_pcm_endpoint "Compute-node PCM endpoint" "${PCM_URL}"
    check_latest_pcm_logs

    info "If Influx/Pyroscope pass but PCM fails, the SSH tunnel is working and pcm-sensor-server is the remaining issue."
    info "Start Intel PCM collection with --hardware-counters intel-pcm, or test manually with:"
    info "docker run --rm -it --privileged --pid=host --net=host wcckit/pipeline-profiler:24.04 bash -lc 'pcm-sensor-server -p 9738'"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --role) [[ $# -ge 2 ]] || { fail "--role requires a value"; exit 2; }; ROLE="$2"; shift 2 ;;
        --role=*) ROLE="${1#*=}"; shift ;;
        --influx-url) [[ $# -ge 2 ]] || { fail "--influx-url requires a value"; exit 2; }; INFLUX_URL="$2"; shift 2 ;;
        --influx-url=*) INFLUX_URL="${1#*=}"; shift ;;
        --pyroscope-url) [[ $# -ge 2 ]] || { fail "--pyroscope-url requires a value"; exit 2; }; PYROSCOPE_URL="$2"; shift 2 ;;
        --pyroscope-url=*) PYROSCOPE_URL="${1#*=}"; shift ;;
        --grafana-url) [[ $# -ge 2 ]] || { fail "--grafana-url requires a value"; exit 2; }; GRAFANA_URL="$2"; shift 2 ;;
        --grafana-url=*) GRAFANA_URL="${1#*=}"; shift ;;
        --pcm-url) [[ $# -ge 2 ]] || { fail "--pcm-url requires a value"; exit 2; }; PCM_URL="$2"; shift 2 ;;
        --pcm-url=*) PCM_URL="${1#*=}"; shift ;;
        --telegraf-pcm-url) [[ $# -ge 2 ]] || { fail "--telegraf-pcm-url requires a value"; exit 2; }; TELEGRAF_PCM_URL="$2"; shift 2 ;;
        --telegraf-pcm-url=*) TELEGRAF_PCM_URL="${1#*=}"; shift ;;
        --telegraf-container) [[ $# -ge 2 ]] || { fail "--telegraf-container requires a value"; exit 2; }; TELEGRAF_CONTAINER="$2"; shift 2 ;;
        --telegraf-container=*) TELEGRAF_CONTAINER="${1#*=}"; shift ;;
        --show-logs) SHOW_LOGS=1; shift ;;
        *) fail "unknown option: $1"; usage; exit 2 ;;
    esac
done

case "${ROLE}" in
    viewer) viewer_checks ;;
    collector) collector_checks ;;
    auto)
        if command -v docker >/dev/null 2>&1 && docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "wcckit-grafana"; then
            viewer_checks
        else
            collector_checks
        fi
        ;;
    *) fail "invalid role: ${ROLE}; expected viewer, collector, or auto"; exit 2 ;;
esac

note "Summary"
if [[ "${FAILURES}" -eq 0 && "${WARNINGS}" -eq 0 ]]; then
    ok "all checks passed"
elif [[ "${FAILURES}" -eq 0 ]]; then
    warn "no hard failures, but ${WARNINGS} warning(s) need review"
else
    fail "${FAILURES} failure(s), ${WARNINGS} warning(s)"
fi

[[ "${FAILURES}" -eq 0 ]]
