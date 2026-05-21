#!/usr/bin/env bash
# Copyright (c) 2026, Raz.
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
IFS=$'\n\t'

OUT_DIR="/out"
RUN_ID=""
PID=""
DURATION="60"
PIPELINE="unknown"
LANGUAGE="python"
INFLUX_URL="${WCCKIT_INFLUX_URL:-}"
INFLUX_ORG="${WCCKIT_INFLUX_ORG:-wcckit}"
INFLUX_BUCKET="${WCCKIT_INFLUX_BUCKET:-wcckit}"
INFLUX_TOKEN="${WCCKIT_INFLUX_TOKEN:-}"
HARDWARE_COUNTERS_REQUESTED="auto"
HARDWARE_COUNTERS_SELECTED=""
CPU_VENDOR=""
INTEL_PCM_AVAILABLE=0
AMD_UPROF_AVAILABLE=0
AMD_UPROF_PCM_PATH=""
AMD_UPROF_MEMORY=0
AMD_UPROF_POWER=0
BPF_IO=1
APP_STAT=1
APP_CALLS=1
APP_FLOW_SUMMARY=1
APP_FLOW_RAW=0
FLAMEGRAPH=1
INTERVAL=1
TOP_CALLS=20

RUN_DIR=""
EVENTS_DIR=""
METRICS_DIR=""
FLAMEGRAPHS_DIR=""
LOGS_DIR=""
PIDS=()

usage() {
    cat <<'EOF'
Collect first-round WCCKIT pipeline telemetry with BCC/eBPF, Intel PCM or AMD
uProf, and application runtime tools.

Usage:
  wcckit_profile_pipeline.sh --pid PID [options]

Options:
  --pid PID                   Target host process ID. Required.
  --duration SECONDS          Collection duration. Default: 60.
  --pipeline NAME             Pipeline/application name. Default: unknown.
  --language LANGUAGE         python|java|perl|php|ruby|tcl. Default: python.
  --run-id RUN_ID             Run identifier. Default: UTC timestamp.
  --out DIR                   Output root mounted in the container. Default: /out.
  --influx-url URL            Optional InfluxDB URL, e.g. http://127.0.0.1:8086.
  --influx-org ORG            InfluxDB org. Default: wcckit.
  --influx-bucket BUCKET      InfluxDB bucket. Default: wcckit.
  --influx-token TOKEN        InfluxDB API token.
  --hardware-counters MODE    auto|intel-pcm|amd-uprof|none. Default: auto.
  --pcm / --no-pcm            Compatibility aliases for intel-pcm / none.
  --amd-uprof-memory / --no-amd-uprof-memory
                              Attempt system-level AMD memory metrics. Default: off.
  --amd-uprof-power / --no-amd-uprof-power
                              Attempt system-level AMD power metrics. Default: off.
  --bpf-io / --no-bpf-io
  --app-stat / --no-app-stat
  --app-calls / --no-app-calls
  --app-flow-summary / --no-app-flow-summary
  --app-flow-raw / --no-app-flow-raw
  --flamegraph / --no-flamegraph
  -h, --help                  Print this help.

Raw uflow can be dense. Keep --app-flow-raw disabled for longer runs unless you
explicitly need method-flow traces.
EOF
}

die() { printf '[wcckit-pipeline] error: %s\n' "$*" >&2; exit 1; }
warn() {
    local line
    line="[wcckit-pipeline] warning: $*"
    printf '%s\n' "${line}" >&2
    if [[ -n "${LOGS_DIR:-}" ]]; then
        printf '%s\n' "${line}" >> "${LOGS_DIR}/collector.log"
    fi
}
log() { printf '[wcckit-pipeline] %s\n' "$*" | tee -a "${LOGS_DIR:-/dev/null}/collector.log" >&2; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"; }
positive_int() { [[ "$1" =~ ^[1-9][0-9]*$ ]]; }

lp_tag() {
    python3 -c 'import sys; value = sys.argv[1]; print(value.replace("\\", "\\\\").replace(" ", "\\ ").replace(",", "\\,").replace("=", "\\="), end="")' "$1"
}

language_tool_prefix() {
    case "$1" in
        python|java|perl|php|ruby|tcl) printf '%s' "$1" ;;
        *) die "unsupported language: $1" ;;
    esac
}

validate_hardware_counters() {
    case "$1" in
        auto|intel-pcm|amd-uprof|none) ;;
        *) die "unsupported hardware-counter backend: $1" ;;
    esac
}

detect_cpu_vendor() {
    awk -F: '/vendor_id/ { gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit }' /proc/cpuinfo 2>/dev/null || true
}

find_amd_uprof_pcm() {
    local candidate
    if command -v AMDuProfPcm >/dev/null 2>&1; then
        command -v AMDuProfPcm
        return 0
    fi
    for candidate in \
        /opt/AMDuProf*/bin/AMDuProfPcm \
        /opt/AMD/AMDuProf*/bin/AMDuProfPcm \
        /usr/local/AMDuProf*/bin/AMDuProfPcm \
        /usr/bin/AMDuProfPcm; do
        if [[ -x "${candidate}" ]]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done
    return 1
}

select_hardware_counter_backend() {
    CPU_VENDOR="$(detect_cpu_vendor)"
    if command -v pcm-sensor-server >/dev/null 2>&1; then INTEL_PCM_AVAILABLE=1; else INTEL_PCM_AVAILABLE=0; fi
    if AMD_UPROF_PCM_PATH="$(find_amd_uprof_pcm 2>/dev/null)"; then AMD_UPROF_AVAILABLE=1; else AMD_UPROF_AVAILABLE=0; AMD_UPROF_PCM_PATH=""; fi

    case "${HARDWARE_COUNTERS_REQUESTED}" in
        auto)
            case "${CPU_VENDOR}" in
                GenuineIntel) HARDWARE_COUNTERS_SELECTED="intel-pcm" ;;
                AuthenticAMD) HARDWARE_COUNTERS_SELECTED="amd-uprof" ;;
                *) HARDWARE_COUNTERS_SELECTED="none" ;;
            esac
            ;;
        *) HARDWARE_COUNTERS_SELECTED="${HARDWARE_COUNTERS_REQUESTED}" ;;
    esac
}

json_manifest() {
    env RUN_ID="${RUN_ID}" PID="${PID}" DURATION="${DURATION}" PIPELINE="${PIPELINE}" LANGUAGE="${LANGUAGE}" \
        OUT_DIR="${OUT_DIR}" RUN_DIR="${RUN_DIR}" INFLUX_URL="${INFLUX_URL}" INFLUX_ORG="${INFLUX_ORG}" \
        INFLUX_BUCKET="${INFLUX_BUCKET}" INFLUX_TOKEN="${INFLUX_TOKEN}" BPF_IO="${BPF_IO}" APP_STAT="${APP_STAT}" \
        APP_CALLS="${APP_CALLS}" APP_FLOW_SUMMARY="${APP_FLOW_SUMMARY}" APP_FLOW_RAW="${APP_FLOW_RAW}" \
        FLAMEGRAPH="${FLAMEGRAPH}" AMD_UPROF_MEMORY="${AMD_UPROF_MEMORY}" AMD_UPROF_POWER="${AMD_UPROF_POWER}" CPU_VENDOR="${CPU_VENDOR}" \
        HARDWARE_COUNTERS_REQUESTED="${HARDWARE_COUNTERS_REQUESTED}" HARDWARE_COUNTERS_SELECTED="${HARDWARE_COUNTERS_SELECTED}" \
        INTEL_PCM_AVAILABLE="${INTEL_PCM_AVAILABLE}" AMD_UPROF_AVAILABLE="${AMD_UPROF_AVAILABLE}" \
        AMD_UPROF_PCM_PATH="${AMD_UPROF_PCM_PATH}" python3 - <<'PYMANIFEST' > "${RUN_DIR}/manifest.json"
import json, os, platform, socket, subprocess, time

def cmd(args):
    try:
        return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT).strip()
    except Exception as exc:
        return f"unavailable ({exc})"

def flag(name):
    return os.environ.get(name) == "1"

amd_path = os.environ["AMD_UPROF_PCM_PATH"]
manifest = {
    "schema": "wcckit.pipeline_profile.v1",
    "timestamp_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "run_id": os.environ["RUN_ID"],
    "pid": int(os.environ["PID"]),
    "duration_seconds": int(os.environ["DURATION"]),
    "pipeline": os.environ["PIPELINE"],
    "language": os.environ["LANGUAGE"],
    "hostname": socket.gethostname(),
    "kernel": platform.release(),
    "platform": platform.platform(),
    "cpu_vendor": os.environ["CPU_VENDOR"],
    "output_root": os.environ["OUT_DIR"],
    "run_dir": os.environ["RUN_DIR"],
    "influx": {
        "url": os.environ["INFLUX_URL"],
        "org": os.environ["INFLUX_ORG"],
        "bucket": os.environ["INFLUX_BUCKET"],
        "enabled": bool(os.environ["INFLUX_URL"] and os.environ.get("INFLUX_TOKEN")),
    },
    "hardware_counters": {
        "requested": os.environ["HARDWARE_COUNTERS_REQUESTED"],
        "selected": os.environ["HARDWARE_COUNTERS_SELECTED"],
        "intel_pcm_available": flag("INTEL_PCM_AVAILABLE"),
        "amd_uprof_available": flag("AMD_UPROF_AVAILABLE"),
        "amd_uprof_pcm_path": amd_path,
    },
    "collectors": {
        "hardware_counters": os.environ["HARDWARE_COUNTERS_SELECTED"],
        "bpf_io": flag("BPF_IO"),
        "app_stat": flag("APP_STAT"),
        "app_calls": flag("APP_CALLS"),
        "app_flow_summary": flag("APP_FLOW_SUMMARY"),
        "app_flow_raw": flag("APP_FLOW_RAW"),
        "flamegraph": flag("FLAMEGRAPH"),
        "amd_uprof_memory": flag("AMD_UPROF_MEMORY"),
        "amd_uprof_power": flag("AMD_UPROF_POWER"),
    },
    "versions": {
        "pcm": cmd(["pcm", "--version"]),
        "amd_uprof_pcm": cmd([amd_path, "-v"]) if amd_path else "unavailable",
        "python": cmd(["python3", "--version"]),
        "perf": cmd(["perf", "--version"]),
    },
}
print(json.dumps(manifest, indent=2, sort_keys=True))
PYMANIFEST
}

append_run_marker() {
    local phase="$1" ts
    ts="$(date +%s%N)"
    printf 'wcckit_run_marker,run_id=%s,pipeline=%s,phase=%s value=1i %s\n' \
        "$(lp_tag "${RUN_ID}")" "$(lp_tag "${PIPELINE}")" "$(lp_tag "${phase}")" "${ts}" >> "${METRICS_DIR}/influx.lp"
}

append_collector_status_line() {
    local name="$1" status="$2" ok=false ts
    if [[ "${status}" -eq 0 ]]; then ok=true; fi
    ts="$(date +%s%N)"
    printf 'wcckit_collector_status,run_id=%s,pipeline=%s,tool=%s exit_code=%si,ok=%s %s\n' \
        "$(lp_tag "${RUN_ID}")" "$(lp_tag "${PIPELINE}")" "$(lp_tag "${name}")" "${status}" "${ok}" "${ts}" >> "${METRICS_DIR}/influx.lp"
}

append_hardware_status() {
    local measurement="$1" tool="$2" available="$3" selected="$4" status="$5" ts
    ts="$(date +%s%N)"
    printf '%s,run_id=%s,pipeline=%s,pid=%s,tool=%s,vendor=%s available=%s,selected=%s,exit_code=%si %s\n' \
        "${measurement}" "$(lp_tag "${RUN_ID}")" "$(lp_tag "${PIPELINE}")" "${PID}" "$(lp_tag "${tool}")" \
        "$(lp_tag "${CPU_VENDOR:-unknown}")" "${available}" "${selected}" "${status}" "${ts}" >> "${METRICS_DIR}/influx.lp"
}

start_bg() {
    local name="$1"
    shift
    log "starting ${name}: $*"
    (
        set +e
        "$@"
        status=$?
        printf '%s\n' "${status}" > "${LOGS_DIR}/${name}.status"
        exit "${status}"
    ) > "${LOGS_DIR}/${name}.log" 2>&1 &
    PIDS+=("$!")
}

append_collector_status() {
    local status_file name status
    for status_file in "${LOGS_DIR}"/*.status; do
        [[ -e "${status_file}" ]] || continue
        name="$(basename "${status_file%.status}")"
        status="$(tr -cd '0-9' < "${status_file}")"
        [[ -n "${status}" ]] || status=255
        if [[ "${status}" -ne 0 ]]; then warn "collector ${name} exited with status ${status}"; fi
        append_collector_status_line "${name}" "${status}"
        case "${name}" in
            pcm) append_hardware_status wcckit_intel_pcm_status pcm-sensor-server true true "${status}" ;;
            amd-uprof-*) append_hardware_status wcckit_amd_uprof_status "${name}" true true "${status}" ;;
        esac
    done
}

stop_children() {
    local pid
    for pid in "${PIDS[@]:-}"; do
        if kill -0 "${pid}" >/dev/null 2>&1; then kill "${pid}" >/dev/null 2>&1 || true; fi
    done
    wait || true
}

fix_ownership() {
    if [[ -n "${WCCKIT_HOST_UID:-}" && -n "${WCCKIT_HOST_GID:-}" && -d "${RUN_DIR}" ]]; then
        chown -R "${WCCKIT_HOST_UID}:${WCCKIT_HOST_GID}" "${RUN_DIR}" 2>/dev/null || warn "could not update run artifact ownership"
    fi
}

push_influx() {
    [[ -n "${INFLUX_URL}" ]] || return 0
    [[ -n "${INFLUX_TOKEN}" ]] || { warn "Influx URL set but token missing; skipping push"; return 0; }
    [[ -s "${METRICS_DIR}/influx.lp" ]] || { warn "no line protocol points to push"; return 0; }
    local url
    url="${INFLUX_URL%/}/api/v2/write?org=${INFLUX_ORG}&bucket=${INFLUX_BUCKET}&precision=ns"
    log "pushing line protocol to InfluxDB bucket ${INFLUX_BUCKET}"
    curl --fail --silent --show-error --request POST "${url}" \
        --header "Authorization: Token ${INFLUX_TOKEN}" \
        --header "Content-Type: text/plain; charset=utf-8" \
        --data-binary "@${METRICS_DIR}/influx.lp" >> "${LOGS_DIR}/influx.log" 2>&1 \
        || warn "InfluxDB write failed; artifacts remain in ${RUN_DIR}"
}

parse_outputs() {
    if [[ -s "${LOGS_DIR}/bpf-io.log" ]]; then
        wcckit_parse_bpf_io.py --input "${LOGS_DIR}/bpf-io.log" --jsonl "${EVENTS_DIR}/bpf-io.jsonl" \
            --line-protocol "${METRICS_DIR}/bpf-io.lp" --run-id "${RUN_ID}" --pipeline "${PIPELINE}" \
            || warn "failed parsing BPF I/O output"
        cat "${METRICS_DIR}/bpf-io.lp" >> "${METRICS_DIR}/influx.lp" 2>/dev/null || true
    fi
    local amd_tool
    for amd_tool in amd-uprof-pcm amd-uprof-memory amd-uprof-power; do
        if [[ -s "${EVENTS_DIR}/${amd_tool}.csv" ]]; then
            wcckit_parse_amd_uprof_pcm.py --input "${EVENTS_DIR}/${amd_tool}.csv" --jsonl "${EVENTS_DIR}/${amd_tool}.jsonl" \
                --line-protocol "${METRICS_DIR}/${amd_tool}.lp" --run-id "${RUN_ID}" --pipeline "${PIPELINE}" \
                --pid "${PID}" --vendor "${CPU_VENDOR:-AuthenticAMD}" --tool "${amd_tool}" \
                || warn "failed parsing AMD uProf output for ${amd_tool}"
            cat "${METRICS_DIR}/${amd_tool}.lp" >> "${METRICS_DIR}/influx.lp" 2>/dev/null || true
        fi
    done
    for tool in app-ustat app-ucalls app-uflow; do
        if [[ -s "${LOGS_DIR}/${tool}.log" ]]; then
            jsonl_path="${EVENTS_DIR}/${tool}.jsonl"
            if [[ "${tool}" == "app-uflow" && "${APP_FLOW_RAW}" -eq 0 ]]; then
                jsonl_path="${LOGS_DIR}/app-uflow.summary-only.jsonl"
            fi
            wcckit_parse_app_tools.py --tool "${tool#app-}" --language "${LANGUAGE}" --pid "${PID}" \
                --input "${LOGS_DIR}/${tool}.log" --jsonl "${jsonl_path}" \
                --line-protocol "${METRICS_DIR}/${tool}.lp" --run-id "${RUN_ID}" --pipeline "${PIPELINE}" \
                || warn "failed parsing ${tool} output"
            if [[ "${tool}" == "app-uflow" && "${APP_FLOW_RAW}" -eq 0 ]]; then
                rm -f "${jsonl_path}"
            fi
            cat "${METRICS_DIR}/${tool}.lp" >> "${METRICS_DIR}/influx.lp" 2>/dev/null || true
        fi
    done
}

sample_pcm_server() {
    local end now body
    end=$((SECONDS + DURATION))
    while (( SECONDS < end )); do
        now="$(date +%s%N)"
        if body="$(curl --silent --show-error --max-time 2 http://127.0.0.1:9738/metrics 2>/dev/null)"; then
            printf '{"ts_ns":%s,"run_id":"%s","tool":"pcm-sensor-server","format":"prometheus_text","bytes":%s}\n' "${now}" "${RUN_ID}" "${#body}" >> "${EVENTS_DIR}/pcm.jsonl"
            printf 'wcckit_pcm_cpu,run_id=%s,pipeline=%s,tool=pcm-sensor-server scrape_bytes=%si %s\n' "$(lp_tag "${RUN_ID}")" "$(lp_tag "${PIPELINE}")" "${#body}" "${now}" >> "${METRICS_DIR}/influx.lp"
        fi
        sleep "${INTERVAL}"
    done
}

run_amd_uprof_pcm() {
    local output="${EVENTS_DIR}/amd-uprof-pcm.csv"
    "${AMD_UPROF_PCM_PATH}" -m ipc -a -s -X -p "${PID}" -d "${DURATION}" -I 1000 -o "${output}"
}

run_amd_uprof_memory() {
    local output="${EVENTS_DIR}/amd-uprof-memory.csv"
    "${AMD_UPROF_PCM_PATH}" -m memory -a -A system,package -s -X -d "${DURATION}" -I 1000 -o "${output}"
}

run_amd_uprof_power() {
    local output="${EVENTS_DIR}/amd-uprof-power.csv"
    "${AMD_UPROF_PCM_PATH}" -m ipc -a -A system --collect-power -s -X -d "${DURATION}" -I 1000 -o "${output}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --pid) [[ $# -ge 2 ]] || die "--pid requires a value"; PID="$2"; shift 2 ;;
        --pid=*) PID="${1#*=}"; shift ;;
        --duration) [[ $# -ge 2 ]] || die "--duration requires a value"; DURATION="$2"; shift 2 ;;
        --duration=*) DURATION="${1#*=}"; shift ;;
        --pipeline) [[ $# -ge 2 ]] || die "--pipeline requires a value"; PIPELINE="$2"; shift 2 ;;
        --pipeline=*) PIPELINE="${1#*=}"; shift ;;
        --language) [[ $# -ge 2 ]] || die "--language requires a value"; LANGUAGE="$2"; shift 2 ;;
        --language=*) LANGUAGE="${1#*=}"; shift ;;
        --run-id) [[ $# -ge 2 ]] || die "--run-id requires a value"; RUN_ID="$2"; shift 2 ;;
        --run-id=*) RUN_ID="${1#*=}"; shift ;;
        --out) [[ $# -ge 2 ]] || die "--out requires a value"; OUT_DIR="$2"; shift 2 ;;
        --out=*) OUT_DIR="${1#*=}"; shift ;;
        --influx-url) [[ $# -ge 2 ]] || die "--influx-url requires a value"; INFLUX_URL="$2"; shift 2 ;;
        --influx-url=*) INFLUX_URL="${1#*=}"; shift ;;
        --influx-org) [[ $# -ge 2 ]] || die "--influx-org requires a value"; INFLUX_ORG="$2"; shift 2 ;;
        --influx-org=*) INFLUX_ORG="${1#*=}"; shift ;;
        --influx-bucket) [[ $# -ge 2 ]] || die "--influx-bucket requires a value"; INFLUX_BUCKET="$2"; shift 2 ;;
        --influx-bucket=*) INFLUX_BUCKET="${1#*=}"; shift ;;
        --influx-token) [[ $# -ge 2 ]] || die "--influx-token requires a value"; INFLUX_TOKEN="$2"; shift 2 ;;
        --influx-token=*) INFLUX_TOKEN="${1#*=}"; shift ;;
        --hardware-counters) [[ $# -ge 2 ]] || die "--hardware-counters requires a value"; HARDWARE_COUNTERS_REQUESTED="$2"; shift 2 ;;
        --hardware-counters=*) HARDWARE_COUNTERS_REQUESTED="${1#*=}"; shift ;;
        --pcm) HARDWARE_COUNTERS_REQUESTED="intel-pcm"; shift ;;
        --no-pcm) HARDWARE_COUNTERS_REQUESTED="none"; shift ;;
        --amd-uprof-memory) AMD_UPROF_MEMORY=1; shift ;;
        --no-amd-uprof-memory) AMD_UPROF_MEMORY=0; shift ;;
        --amd-uprof-power) AMD_UPROF_POWER=1; shift ;;
        --no-amd-uprof-power) AMD_UPROF_POWER=0; shift ;;
        --bpf-io) BPF_IO=1; shift ;;
        --no-bpf-io) BPF_IO=0; shift ;;
        --app-stat) APP_STAT=1; shift ;;
        --no-app-stat) APP_STAT=0; shift ;;
        --app-calls) APP_CALLS=1; shift ;;
        --no-app-calls) APP_CALLS=0; shift ;;
        --app-flow-summary) APP_FLOW_SUMMARY=1; shift ;;
        --no-app-flow-summary) APP_FLOW_SUMMARY=0; shift ;;
        --app-flow-raw) APP_FLOW_RAW=1; shift ;;
        --no-app-flow-raw) APP_FLOW_RAW=0; shift ;;
        --flamegraph) FLAMEGRAPH=1; shift ;;
        --no-flamegraph) FLAMEGRAPH=0; shift ;;
        *) die "unknown option: $1" ;;
    esac
done

[[ -n "${PID}" ]] || die "--pid is required"
positive_int "${PID}" || die "PID must be a positive integer: ${PID}"
positive_int "${DURATION}" || die "duration must be a positive integer: ${DURATION}"
language_tool_prefix "${LANGUAGE}" >/dev/null
validate_hardware_counters "${HARDWARE_COUNTERS_REQUESTED}"
[[ -d "${OUT_DIR}" ]] || mkdir -p "${OUT_DIR}"

require_cmd python3
require_cmd timeout
require_cmd curl
if [[ "${BPF_IO}" -eq 1 ]]; then
    require_cmd biolatency-bpfcc
fi
[[ "${FLAMEGRAPH}" -eq 0 ]] || require_cmd wcckit_profile_cpu.sh

if [[ -z "${RUN_ID}" ]]; then RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"; fi
[[ "${RUN_ID}" =~ ^[A-Za-z0-9._:-]+$ ]] || die "run-id must contain only letters, numbers, dot, underscore, colon, or dash"
RUN_DIR="${OUT_DIR%/}/${RUN_ID}"
EVENTS_DIR="${RUN_DIR}/events"
METRICS_DIR="${RUN_DIR}/metrics"
FLAMEGRAPHS_DIR="${RUN_DIR}/flamegraphs"
LOGS_DIR="${RUN_DIR}/logs"
mkdir -p "${EVENTS_DIR}" "${METRICS_DIR}" "${FLAMEGRAPHS_DIR}" "${LOGS_DIR}"
: > "${METRICS_DIR}/influx.lp"
: > "${LOGS_DIR}/collector.log"
trap 'stop_children' EXIT INT TERM

select_hardware_counter_backend
json_manifest
append_run_marker start
log "run directory: ${RUN_DIR}"
log "pipeline=${PIPELINE} pid=${PID} language=${LANGUAGE} duration=${DURATION}s hardware-counters=${HARDWARE_COUNTERS_SELECTED} vendor=${CPU_VENDOR:-unknown}"
prefix="$(language_tool_prefix "${LANGUAGE}")"

case "${HARDWARE_COUNTERS_SELECTED}" in
    intel-pcm)
        if [[ "${INTEL_PCM_AVAILABLE}" -eq 1 ]]; then
            start_bg pcm timeout --foreground "${DURATION}" pcm-sensor-server -p 9738
            start_bg pcm-sampler sample_pcm_server
        else
            warn "pcm-sensor-server unavailable; Intel PCM hardware counters skipped"
            append_collector_status_line pcm 127
            append_hardware_status wcckit_intel_pcm_status pcm-sensor-server false true 127
        fi
        ;;
    amd-uprof)
        if [[ "${AMD_UPROF_AVAILABLE}" -eq 1 ]]; then
            start_bg amd-uprof-pcm run_amd_uprof_pcm
            if [[ "${AMD_UPROF_MEMORY}" -eq 1 ]]; then start_bg amd-uprof-memory run_amd_uprof_memory; fi
            if [[ "${AMD_UPROF_POWER}" -eq 1 ]]; then start_bg amd-uprof-power run_amd_uprof_power; fi
        else
            warn "AMDuProfPcm unavailable; AMD uProf hardware counters skipped"
            append_collector_status_line amd-uprof-pcm 127
            append_hardware_status wcckit_amd_uprof_status amd-uprof-pcm false true 127
        fi
        ;;
    none)
        log "hardware counters disabled"
        append_collector_status_line hardware-counters 0
        ;;
esac

if [[ "${BPF_IO}" -eq 1 ]]; then start_bg bpf-io timeout --foreground "$((DURATION + 10))" biolatency-bpfcc -j 1 "${DURATION}"; fi
if [[ "${APP_STAT}" -eq 1 ]]; then
    if command -v "${prefix}stat.sh" >/dev/null 2>&1; then start_bg app-ustat timeout --foreground "${DURATION}" "${prefix}stat.sh" -l "${LANGUAGE}" -C "${INTERVAL}" "${DURATION}"; else warn "${prefix}stat.sh unavailable"; fi
fi
if [[ "${APP_CALLS}" -eq 1 ]]; then
    if command -v "${prefix}calls.sh" >/dev/null 2>&1; then start_bg app-ucalls timeout --foreground "${DURATION}" "${prefix}calls.sh" -l "${LANGUAGE}" -T "${TOP_CALLS}" -L "${PID}" "${INTERVAL}"; else warn "${prefix}calls.sh unavailable"; fi
fi
if [[ "${APP_FLOW_RAW}" -eq 1 || "${APP_FLOW_SUMMARY}" -eq 1 ]]; then
    if command -v "${prefix}flow.sh" >/dev/null 2>&1; then start_bg app-uflow timeout --foreground "${DURATION}" "${prefix}flow.sh" -l "${LANGUAGE}" "${PID}"; else warn "${prefix}flow.sh unavailable"; fi
fi
if [[ "${FLAMEGRAPH}" -eq 1 ]]; then
    start_bg flamegraph timeout --foreground "${DURATION}" wcckit_profile_cpu.sh --pid "${PID}" --duration "${DURATION}" --frequency 99 --output "${FLAMEGRAPHS_DIR}/cpu.svg" --subtitle "run_id=${RUN_ID} pipeline=${PIPELINE} pid=${PID}"
fi
wait || true
PIDS=()
append_collector_status
parse_outputs
append_run_marker end
push_influx
fix_ownership
log "collection finished: ${RUN_DIR}"
