#!/usr/bin/env bash
# Copyright (c) 2026, Raz.
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
IFS=$'\n\t'

OUT_DIR="/out"
RUN_ID=""
PID=""
DURATION="60"
DURATION_SET=0
UNTIL_EXIT=0
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
PROCESS_MEMORY=1
BPF_IO=1
APP_STAT=1
APP_CALLS=1
APP_FLOW_SUMMARY=1
APP_FLOW_RAW=0
FLAMEGRAPH=1
CPU_PROFILE=1
PYROSCOPE_URL="${WCCKIT_PYROSCOPE_URL:-}"
PYROSCOPE_APP="${WCCKIT_PYROSCOPE_APP:-}"
PUSH_PROFILES="auto"
PROFILE_START_NS=""
PROFILE_END_NS=""
RUN_START_MARKER_NS=""
RUN_END_MARKER_NS=""
INTERVAL=1
TOP_CALLS=20
JOB_LANE=1

RUN_DIR=""
EVENTS_DIR=""
METRICS_DIR=""
FLAMEGRAPHS_DIR=""
PROFILES_DIR=""
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
  --until-exit                Collect until the target PID exits. --duration becomes
                              the safety cap. If omitted, default cap is 86400 seconds.
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
  --process-memory / --no-process-memory
                              Sample target process RSS/VMS and page-fault rates. Default: on.
  --bpf-io / --no-bpf-io
  --app-stat / --no-app-stat
  --app-calls / --no-app-calls
  --app-flow-summary / --no-app-flow-summary
  --app-flow-raw / --no-app-flow-raw
  --flamegraph / --no-flamegraph
  --cpu-profile / --no-cpu-profile
                              Compatibility aliases for --flamegraph.
  --pyroscope-url URL         Optional Pyroscope URL, e.g. http://127.0.0.1:4040.
  --pyroscope-app NAME        Pyroscope application name. Default: pipeline name.
  --push-profiles             Push folded CPU/uflow profiles to Pyroscope.
  --no-push-profiles          Never push folded profiles.
  --job-lane N                Dashboard lane/counter for this run. Default: 1.
  -h, --help                  Print this help.

Raw uflow can be dense. When --app-flow-raw is enabled, WCCKIT preserves every
emitted uflow line in the run artifacts and only exports summaries to InfluxDB.
CPU flame graphs are sampled profiles, not complete call traces.
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
        JOB_LANE="${JOB_LANE}" OUT_DIR="${OUT_DIR}" RUN_DIR="${RUN_DIR}" INFLUX_URL="${INFLUX_URL}" INFLUX_ORG="${INFLUX_ORG}" \
        INFLUX_BUCKET="${INFLUX_BUCKET}" INFLUX_TOKEN="${INFLUX_TOKEN}" PYROSCOPE_URL="${PYROSCOPE_URL}" \
        PYROSCOPE_APP="${PYROSCOPE_APP}" PUSH_PROFILES="$(profile_push_enabled && printf true || printf false)" \
        BPF_IO="${BPF_IO}" APP_STAT="${APP_STAT}" UNTIL_EXIT="${UNTIL_EXIT}" \
        APP_CALLS="${APP_CALLS}" APP_FLOW_SUMMARY="${APP_FLOW_SUMMARY}" APP_FLOW_RAW="${APP_FLOW_RAW}" \
        FLAMEGRAPH="${FLAMEGRAPH}" AMD_UPROF_MEMORY="${AMD_UPROF_MEMORY}" AMD_UPROF_POWER="${AMD_UPROF_POWER}" \
        PROCESS_MEMORY="${PROCESS_MEMORY}" CPU_VENDOR="${CPU_VENDOR}" \
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
    "until_exit": os.environ.get("UNTIL_EXIT") == "1",
    "pipeline": os.environ["PIPELINE"],
    "language": os.environ["LANGUAGE"],
    "job_lane": int(os.environ["JOB_LANE"]),
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
    "profiles": {
        "cpu_profile_is_sampled": True,
        "pyroscope_url": os.environ["PYROSCOPE_URL"],
        "pyroscope_app": os.environ["PYROSCOPE_APP"],
        "push_profiles": os.environ["PUSH_PROFILES"] == "true",
        "cpu_profile_artifacts": ["profiles/cpu.folded", "flamegraphs/cpu.svg"],
        "app_uflow_artifacts": ["events/app-uflow.raw.log", "events/app-uflow.jsonl", "profiles/app-uflow.folded", "flamegraphs/app-uflow.svg"],
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
        "process_memory": flag("PROCESS_MEMORY"),
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
    case "${phase}" in
        start) RUN_START_MARKER_NS="${ts}" ;;
        end) RUN_END_MARKER_NS="${ts}" ;;
    esac
    printf 'wcckit_run_marker,run_id=%s,pipeline=%s,phase=%s value=1i,job_lane=%si %s\n' \
        "$(lp_tag "${RUN_ID}")" "$(lp_tag "${PIPELINE}")" "$(lp_tag "${phase}")" "${JOB_LANE}" "${ts}" >> "${METRICS_DIR}/influx.lp"
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

append_profile_status() {
    local profile_type="$1" status="$2" pushed="$3" ts
    ts="$(date +%s%N)"
    printf 'wcckit_profile_status,run_id=%s,pipeline=%s,pid=%s,profile_type=%s,tool=pyroscope exit_code=%si,pushed=%s %s\n' \
        "$(lp_tag "${RUN_ID}")" "$(lp_tag "${PIPELINE}")" "${PID}" "$(lp_tag "${profile_type}")" "${status}" "${pushed}" "${ts}" >> "${METRICS_DIR}/influx.lp"
}

profile_push_enabled() {
    case "${PUSH_PROFILES}" in
        1|true|yes) return 0 ;;
        0|false|no) return 1 ;;
        auto) [[ -n "${PYROSCOPE_URL}" ]] ;;
        *) return 1 ;;
    esac
}

target_is_running() {
    local stat rest state
    [[ -r "/proc/${PID}/stat" ]] || return 1
    stat="$(<"/proc/${PID}/stat")"
    rest="${stat#*) }"
    state="${rest%% *}"
    [[ "${state}" != "Z" && "${state}" != "X" ]]
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
        if kill -0 "${pid}" >/dev/null 2>&1; then kill -INT "${pid}" >/dev/null 2>&1 || true; fi
    done
    sleep 1
    for pid in "${PIDS[@]:-}"; do
        if kill -0 "${pid}" >/dev/null 2>&1; then kill "${pid}" >/dev/null 2>&1 || true; fi
    done
    wait || true
}

wait_for_collectors() {
    local pid alive end
    if [[ "${UNTIL_EXIT}" -eq 0 ]]; then
        wait || true
        return 0
    fi

    end=$((SECONDS + DURATION))
    while (( SECONDS < end )); do
        if ! target_is_running; then
            log "target PID ${PID} exited; stopping collectors"
            stop_children
            return 0
        fi
        alive=0
        for pid in "${PIDS[@]:-}"; do
            if kill -0 "${pid}" >/dev/null 2>&1; then
                alive=1
                break
            fi
        done
        if [[ "${alive}" -eq 0 ]]; then
            return 0
        fi
        sleep 1
    done
    warn "maximum collection duration reached while target PID ${PID} was still running"
    stop_children
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
    local amd_tool jsonl_path parse_tool parse_language tool
    for amd_tool in amd-uprof-pcm amd-uprof-memory amd-uprof-power; do
        if [[ -s "${EVENTS_DIR}/${amd_tool}.csv" ]]; then
            wcckit_parse_amd_uprof_pcm.py --input "${EVENTS_DIR}/${amd_tool}.csv" --jsonl "${EVENTS_DIR}/${amd_tool}.jsonl" \
                --line-protocol "${METRICS_DIR}/${amd_tool}.lp" --run-id "${RUN_ID}" --pipeline "${PIPELINE}" \
                --pid "${PID}" --vendor "${CPU_VENDOR:-AuthenticAMD}" --tool "${amd_tool}" \
                --start-timestamp-ns "${RUN_START_MARKER_NS:-${PROFILE_START_NS:-0}}" \
                || warn "failed parsing AMD uProf output for ${amd_tool}"
            cat "${METRICS_DIR}/${amd_tool}.lp" >> "${METRICS_DIR}/influx.lp" 2>/dev/null || true
        fi
    done
    if [[ -e "${LOGS_DIR}/app-uflow.log" && "${APP_FLOW_RAW}" -eq 1 ]]; then
        cp "${LOGS_DIR}/app-uflow.log" "${EVENTS_DIR}/app-uflow.raw.log"
        wcckit_parse_uflow.py --input "${EVENTS_DIR}/app-uflow.raw.log" \
            --jsonl "${EVENTS_DIR}/app-uflow.jsonl" --folded "${PROFILES_DIR}/app-uflow.folded" \
            --line-protocol "${METRICS_DIR}/app-uflow.lp" --run-id "${RUN_ID}" \
            --pipeline "${PIPELINE}" --pid "${PID}" --language "${LANGUAGE}" \
            || warn "failed parsing raw uflow output"
        cat "${METRICS_DIR}/app-uflow.lp" >> "${METRICS_DIR}/influx.lp" 2>/dev/null || true
        if [[ -s "${PROFILES_DIR}/app-uflow.folded" && -f /src/FlameGraph/flamegraph.pl ]]; then
            perl /src/FlameGraph/flamegraph.pl --title "WCCKIT uflow Call Flow" \
                --subtitle "run_id=${RUN_ID} pipeline=${PIPELINE} pid=${PID}" \
                < "${PROFILES_DIR}/app-uflow.folded" > "${FLAMEGRAPHS_DIR}/app-uflow.svg" \
                || warn "failed generating app uflow SVG flame graph"
        fi
    fi
    for tool in app-ustat app-ucalls app-syscalls app-uflow; do
        if [[ "${tool}" == "app-uflow" && "${APP_FLOW_RAW}" -eq 1 ]]; then
            continue
        fi
        if [[ -e "${LOGS_DIR}/${tool}.log" ]]; then
            jsonl_path="${EVENTS_DIR}/${tool}.jsonl"
            if [[ "${tool}" == "app-uflow" && "${APP_FLOW_RAW}" -eq 0 ]]; then
                jsonl_path="${LOGS_DIR}/app-uflow.summary-only.jsonl"
            fi
            parse_tool="${tool#app-}"
            parse_language="${LANGUAGE}"
            if [[ "${tool}" == "app-syscalls" ]]; then parse_tool="ucalls"; parse_language="syscall"; fi
            wcckit_parse_app_tools.py --tool "${parse_tool}" --language "${parse_language}" --pid "${PID}" \
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

push_profile_artifacts() {
    local status
    if ! profile_push_enabled; then
        return 0
    fi
    if [[ -z "${PYROSCOPE_URL}" ]]; then
        warn "profile push requested but --pyroscope-url is empty"
        append_profile_status cpu 2 false
        append_profile_status uflow 2 false
        return 0
    fi
    if [[ -z "${PYROSCOPE_APP}" ]]; then PYROSCOPE_APP="${PIPELINE}"; fi
    if [[ -s "${PROFILES_DIR}/cpu.folded" ]]; then
        if wcckit_push_pyroscope.py --url "${PYROSCOPE_URL}" --app-name "${PYROSCOPE_APP}" \
            --profile-type cpu --input "${PROFILES_DIR}/cpu.folded" --run-id "${RUN_ID}" \
            --pipeline "${PIPELINE}" --pid "${PID}" --from-timestamp-ns "${PROFILE_START_NS}" \
            --until-timestamp-ns "${PROFILE_END_NS}" >> "${LOGS_DIR}/pyroscope.log" 2>&1; then
            append_profile_status cpu 0 true
        else
            status=$?
            warn "failed pushing CPU folded profile to Pyroscope"
            append_profile_status cpu "${status}" false
        fi
    fi
    if [[ -s "${PROFILES_DIR}/app-uflow.folded" ]]; then
        if wcckit_push_pyroscope.py --url "${PYROSCOPE_URL}" --app-name "${PYROSCOPE_APP}" \
            --profile-type uflow --input "${PROFILES_DIR}/app-uflow.folded" --run-id "${RUN_ID}" \
            --pipeline "${PIPELINE}" --pid "${PID}" --from-timestamp-ns "${PROFILE_START_NS}" \
            --until-timestamp-ns "${PROFILE_END_NS}" >> "${LOGS_DIR}/pyroscope.log" 2>&1; then
            append_profile_status uflow 0 true
        else
            status=$?
            warn "failed pushing uflow folded profile to Pyroscope"
            append_profile_status uflow "${status}" false
        fi
    fi
}

sample_process_memory() {
    local end now status_file stat_file rss_kb vms_kb data_kb swap_kb stat rest
    local minflt majflt prev_minflt="" prev_majflt="" prev_ts="" delta_min delta_maj elapsed_ns
    local minor_rate major_rate fields
    status_file="/proc/${PID}/status"
    stat_file="/proc/${PID}/stat"
    end=$((SECONDS + DURATION))
    while (( SECONDS < end )); do
        now="$(date +%s%N)"
        if ! target_is_running || [[ ! -r "${status_file}" || ! -r "${stat_file}" ]]; then
            printf 'wcckit_process_memory,run_id=%s,pipeline=%s,pid=%s,tool=procfs available=false %s\n' \
                "$(lp_tag "${RUN_ID}")" "$(lp_tag "${PIPELINE}")" "${PID}" "${now}" >> "${METRICS_DIR}/influx.lp"
            return 0
        fi
        rss_kb="$(awk '/^VmRSS:/ {print $2; found=1} END {if (!found) print 0}' "${status_file}")"
        vms_kb="$(awk '/^VmSize:/ {print $2; found=1} END {if (!found) print 0}' "${status_file}")"
        data_kb="$(awk '/^VmData:/ {print $2; found=1} END {if (!found) print 0}' "${status_file}")"
        swap_kb="$(awk '/^VmSwap:/ {print $2; found=1} END {if (!found) print 0}' "${status_file}")"
        stat="$(<"${stat_file}")"
        rest="${stat#*) }"
        local IFS=' '
        read -r -a fields <<< "${rest}"
        minflt="${fields[7]:-0}"
        majflt="${fields[9]:-0}"
        minor_rate="0.000000"
        major_rate="0.000000"
        if [[ -n "${prev_ts}" ]]; then
            delta_min=$((minflt - prev_minflt))
            delta_maj=$((majflt - prev_majflt))
            elapsed_ns=$((now - prev_ts))
            minor_rate="$(awk -v d="${delta_min}" -v ns="${elapsed_ns}" 'BEGIN { if (ns > 0) printf "%.6f", d / (ns / 1000000000.0); else printf "0.000000" }')"
            major_rate="$(awk -v d="${delta_maj}" -v ns="${elapsed_ns}" 'BEGIN { if (ns > 0) printf "%.6f", d / (ns / 1000000000.0); else printf "0.000000" }')"
        fi
        prev_minflt="${minflt}"
        prev_majflt="${majflt}"
        prev_ts="${now}"
        printf '{"ts_ns":%s,"run_id":"%s","pipeline":"%s","pid":%s,"tool":"procfs","rss_bytes":%s,"vms_bytes":%s,"data_bytes":%s,"swap_bytes":%s,"minor_faults_total":%s,"major_faults_total":%s,"minor_faults_s":%s,"major_faults_s":%s}\n' \
            "${now}" "${RUN_ID}" "${PIPELINE}" "${PID}" "$((rss_kb * 1024))" "$((vms_kb * 1024))" \
            "$((data_kb * 1024))" "$((swap_kb * 1024))" "${minflt}" "${majflt}" "${minor_rate}" "${major_rate}" >> "${EVENTS_DIR}/process-memory.jsonl"
        printf 'wcckit_process_memory,run_id=%s,pipeline=%s,pid=%s,tool=procfs available=true,rss_bytes=%si,vms_bytes=%si,data_bytes=%si,swap_bytes=%si,minor_faults_total=%si,major_faults_total=%si,minor_faults_s=%s,major_faults_s=%s %s\n' \
            "$(lp_tag "${RUN_ID}")" "$(lp_tag "${PIPELINE}")" "${PID}" "$((rss_kb * 1024))" "$((vms_kb * 1024))" \
            "$((data_kb * 1024))" "$((swap_kb * 1024))" "${minflt}" "${majflt}" "${minor_rate}" "${major_rate}" "${now}" >> "${METRICS_DIR}/influx.lp"
        sleep "${INTERVAL}"
    done
}

sample_pcm_server() {
    local end now body endpoint path url ok=0 errors=0 scraped=0
    end=$((SECONDS + DURATION))
    while (( SECONDS < end )); do
        now="$(date +%s%N)"
        endpoint=""
        for path in persecond metrics; do
            if [[ "${path}" == "persecond" ]]; then
                url="http://127.0.0.1:9738/persecond/"
            else
                url="http://127.0.0.1:9738/metrics"
            fi
            if body="$(curl --silent --show-error --max-time 2 "${url}" 2>/dev/null)"; then
                endpoint="${path}"
                ok=1
                scraped=1
                break
            fi
        done
        if [[ "${scraped}" -eq 1 ]]; then
            printf '{"ts_ns":%s,"run_id":"%s","tool":"pcm-sensor-server","endpoint":"%s","format":"prometheus_text","bytes":%s}\n' "${now}" "${RUN_ID}" "${endpoint}" "${#body}" >> "${EVENTS_DIR}/pcm.jsonl"
            printf 'wcckit_pcm_cpu,run_id=%s,pipeline=%s,tool=pcm-sensor-server,endpoint=%s scrape_bytes=%si,scrape_ok=true,errors_total=%si %s\n' "$(lp_tag "${RUN_ID}")" "$(lp_tag "${PIPELINE}")" "$(lp_tag "${endpoint}")" "${#body}" "${errors}" "${now}" >> "${METRICS_DIR}/influx.lp"
        else
            errors=$((errors + 1))
        fi
        scraped=0
        sleep "${INTERVAL}"
    done
    if [[ "${ok}" -eq 0 ]]; then
        now="$(date +%s%N)"
        printf 'wcckit_pcm_cpu,run_id=%s,pipeline=%s,tool=pcm-sensor-server,endpoint=none scrape_bytes=0i,scrape_ok=false,errors_total=%si %s\n' "$(lp_tag "${RUN_ID}")" "$(lp_tag "${PIPELINE}")" "${errors}" "${now}" >> "${METRICS_DIR}/influx.lp"
    fi
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
        --duration) [[ $# -ge 2 ]] || die "--duration requires a value"; DURATION="$2"; DURATION_SET=1; shift 2 ;;
        --duration=*) DURATION="${1#*=}"; DURATION_SET=1; shift ;;
        --until-exit) UNTIL_EXIT=1; shift ;;
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
        --pyroscope-url) [[ $# -ge 2 ]] || die "--pyroscope-url requires a value"; PYROSCOPE_URL="$2"; shift 2 ;;
        --pyroscope-url=*) PYROSCOPE_URL="${1#*=}"; shift ;;
        --pyroscope-app) [[ $# -ge 2 ]] || die "--pyroscope-app requires a value"; PYROSCOPE_APP="$2"; shift 2 ;;
        --pyroscope-app=*) PYROSCOPE_APP="${1#*=}"; shift ;;
        --push-profiles) PUSH_PROFILES=1; shift ;;
        --no-push-profiles) PUSH_PROFILES=0; shift ;;
        --job-lane) [[ $# -ge 2 ]] || die "--job-lane requires a value"; JOB_LANE="$2"; shift 2 ;;
        --job-lane=*) JOB_LANE="${1#*=}"; shift ;;
        --hardware-counters) [[ $# -ge 2 ]] || die "--hardware-counters requires a value"; HARDWARE_COUNTERS_REQUESTED="$2"; shift 2 ;;
        --hardware-counters=*) HARDWARE_COUNTERS_REQUESTED="${1#*=}"; shift ;;
        --pcm) HARDWARE_COUNTERS_REQUESTED="intel-pcm"; shift ;;
        --no-pcm) HARDWARE_COUNTERS_REQUESTED="none"; shift ;;
        --amd-uprof-memory) AMD_UPROF_MEMORY=1; shift ;;
        --no-amd-uprof-memory) AMD_UPROF_MEMORY=0; shift ;;
        --amd-uprof-power) AMD_UPROF_POWER=1; shift ;;
        --no-amd-uprof-power) AMD_UPROF_POWER=0; shift ;;
        --process-memory) PROCESS_MEMORY=1; shift ;;
        --no-process-memory) PROCESS_MEMORY=0; shift ;;
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
        --flamegraph|--cpu-profile) FLAMEGRAPH=1; CPU_PROFILE=1; shift ;;
        --no-flamegraph|--no-cpu-profile) FLAMEGRAPH=0; CPU_PROFILE=0; shift ;;
        *) die "unknown option: $1" ;;
    esac
done

[[ -n "${PID}" ]] || die "--pid is required"
positive_int "${PID}" || die "PID must be a positive integer: ${PID}"
if [[ "${UNTIL_EXIT}" -eq 1 && "${DURATION_SET}" -eq 0 ]]; then DURATION=86400; fi
positive_int "${DURATION}" || die "duration must be a positive integer: ${DURATION}"
positive_int "${JOB_LANE}" || die "job-lane must be a positive integer: ${JOB_LANE}"
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
if [[ "${APP_FLOW_RAW}" -eq 1 ]]; then require_cmd wcckit_parse_uflow.py; fi
if profile_push_enabled; then require_cmd wcckit_push_pyroscope.py; fi

if [[ -z "${RUN_ID}" ]]; then RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"; fi
[[ "${RUN_ID}" =~ ^[A-Za-z0-9._:-]+$ ]] || die "run-id must contain only letters, numbers, dot, underscore, colon, or dash"
RUN_DIR="${OUT_DIR%/}/${RUN_ID}"
EVENTS_DIR="${RUN_DIR}/events"
METRICS_DIR="${RUN_DIR}/metrics"
FLAMEGRAPHS_DIR="${RUN_DIR}/flamegraphs"
PROFILES_DIR="${RUN_DIR}/profiles"
LOGS_DIR="${RUN_DIR}/logs"
mkdir -p "${EVENTS_DIR}" "${METRICS_DIR}" "${FLAMEGRAPHS_DIR}" "${PROFILES_DIR}" "${LOGS_DIR}"
: > "${METRICS_DIR}/influx.lp"
: > "${LOGS_DIR}/collector.log"
trap 'stop_children' EXIT INT TERM

select_hardware_counter_backend
if [[ -z "${PYROSCOPE_APP}" ]]; then PYROSCOPE_APP="${PIPELINE}"; fi
json_manifest
append_run_marker start
PROFILE_START_NS="$(date +%s%N)"
log "run directory: ${RUN_DIR}"
log "pipeline=${PIPELINE} pid=${PID} language=${LANGUAGE} duration=${DURATION}s until_exit=${UNTIL_EXIT} hardware-counters=${HARDWARE_COUNTERS_SELECTED} vendor=${CPU_VENDOR:-unknown}"
prefix="$(language_tool_prefix "${LANGUAGE}")"

if [[ "${PROCESS_MEMORY}" -eq 1 ]]; then start_bg process-memory sample_process_memory; fi

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
    if command -v "${prefix}stat.sh" >/dev/null 2>&1; then start_bg app-ustat timeout --signal INT --kill-after 5 --foreground "${DURATION}" "${prefix}stat.sh" -C "${INTERVAL}" "${DURATION}"; else warn "${prefix}stat.sh unavailable"; fi
fi
if [[ "${APP_CALLS}" -eq 1 ]]; then
    if command -v "${prefix}calls.sh" >/dev/null 2>&1; then start_bg app-ucalls timeout --signal INT --kill-after 5 --foreground "${DURATION}" "${prefix}calls.sh" -T "${TOP_CALLS}" -L "${PID}" "${INTERVAL}"; else warn "${prefix}calls.sh unavailable"; fi
    if [[ -x /usr/local/bin/lib/ucalls.py ]]; then start_bg app-syscalls timeout --signal INT --kill-after 5 --foreground "${DURATION}" /usr/local/bin/lib/ucalls.py -l none -S -T "${TOP_CALLS}" -L "${PID}" "${INTERVAL}"; else warn "ucalls.py syscall fallback unavailable"; fi
fi
if [[ "${APP_FLOW_RAW}" -eq 1 || "${APP_FLOW_SUMMARY}" -eq 1 ]]; then
    if command -v "${prefix}flow.sh" >/dev/null 2>&1; then start_bg app-uflow timeout --signal INT --kill-after 5 --foreground "${DURATION}" "${prefix}flow.sh" "${PID}"; else warn "${prefix}flow.sh unavailable"; fi
fi
if [[ "${FLAMEGRAPH}" -eq 1 ]]; then
    start_bg flamegraph timeout --foreground "$((DURATION + 30))" wcckit_profile_cpu.sh --pid "${PID}" --duration "${DURATION}" --frequency 99 --output "${FLAMEGRAPHS_DIR}/cpu.svg" --folded-output "${PROFILES_DIR}/cpu.folded" --subtitle "run_id=${RUN_ID} pipeline=${PIPELINE} pid=${PID} sampled_cpu_profile=true"
fi
wait_for_collectors
PROFILE_END_NS="$(date +%s%N)"
PIDS=()
append_collector_status
parse_outputs
push_profile_artifacts
append_run_marker end
push_influx
fix_ownership
log "collection finished: ${RUN_DIR}"
