#!/usr/bin/env bash
# Copyright (c) 2026, Raz.
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
IFS=$'\n\t'

OUT_DIR="/out"
RUN_ID=""
PIPELINE="unknown"
INFLUX_URL="${WCCKIT_INFLUX_URL:-}"
INFLUX_ORG="${WCCKIT_INFLUX_ORG:-wcckit}"
INFLUX_BUCKET="${WCCKIT_INFLUX_BUCKET:-wcckit}"
INFLUX_TOKEN="${WCCKIT_INFLUX_TOKEN:-}"
USE_MSR=0
READ_SMBIOS=0
CMD=()

usage() {
    cat <<'EOF'
Collect an AMD uProf Classic Roofline report for a launched workload.

Usage:
  wcckit_amd_uprof_roofline.sh [options] -- command [args...]

Options:
  --out DIR             Output root mounted in the container. Default: /out.
  --run-id RUN_ID       Run identifier. Default: UTC timestamp.
  --pipeline NAME       Pipeline/application name. Default: unknown.
  --influx-url URL      Optional InfluxDB URL, e.g. http://127.0.0.1:8086.
  --influx-org ORG      InfluxDB org. Default: wcckit.
  --influx-bucket NAME  InfluxDB bucket. Default: wcckit.
  --influx-token TOKEN  InfluxDB API token.
  --msr                 Use AMDuProfPcm roofline --msr mode.
  --read-smbios         Ask AMDuProfPcm to read SMBIOS memory details.
  -h, --help            Print this help.

The command is launched inside the container. Mount the workload directory with
run-wcckit-amd-roofline.sh --workdir DIR when the command lives on the host.
The AMD HTML roofline report remains the canonical artifact under:
  runs/<run_id>/roofline/amd-uprof/
EOF
}

die() { printf '[wcckit-roofline] error: %s\n' "$*" >&2; exit 1; }
warn() { printf '[wcckit-roofline] warning: %s\n' "$*" >&2; }
log() { printf '[wcckit-roofline] %s\n' "$*" >&2; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"; }

lp_tag() {
    python3 -c 'import sys; value = sys.argv[1]; print(value.replace("\\", "\\\\").replace(" ", "\\ ").replace(",", "\\,").replace("=", "\\="), end="")' "$1"
}

lp_string() {
    python3 -c 'import sys; value = sys.argv[1]; print("\"" + value.replace("\\", "\\\\").replace("\"", "\\\"") + "\"", end="")' "$1"
}

push_influx() {
    [[ -n "${INFLUX_URL}" ]] || return 0
    [[ -n "${INFLUX_TOKEN}" ]] || { warn "Influx URL set but token missing; skipping push"; return 0; }
    [[ -s "${METRICS_DIR}/influx.lp" ]] || return 0
    local url
    url="${INFLUX_URL%/}/api/v2/write?org=${INFLUX_ORG}&bucket=${INFLUX_BUCKET}&precision=ns"
    curl --fail --silent --show-error --request POST "${url}" \
        --header "Authorization: Token ${INFLUX_TOKEN}" \
        --header "Content-Type: text/plain; charset=utf-8" \
        --data-binary "@${METRICS_DIR}/influx.lp" >> "${LOGS_DIR}/influx.log" 2>&1 \
        || warn "InfluxDB write failed; artifacts remain in ${RUN_DIR}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --out) [[ $# -ge 2 ]] || die "--out requires a value"; OUT_DIR="$2"; shift 2 ;;
        --out=*) OUT_DIR="${1#*=}"; shift ;;
        --run-id) [[ $# -ge 2 ]] || die "--run-id requires a value"; RUN_ID="$2"; shift 2 ;;
        --run-id=*) RUN_ID="${1#*=}"; shift ;;
        --pipeline) [[ $# -ge 2 ]] || die "--pipeline requires a value"; PIPELINE="$2"; shift 2 ;;
        --pipeline=*) PIPELINE="${1#*=}"; shift ;;
        --influx-url) [[ $# -ge 2 ]] || die "--influx-url requires a value"; INFLUX_URL="$2"; shift 2 ;;
        --influx-url=*) INFLUX_URL="${1#*=}"; shift ;;
        --influx-org) [[ $# -ge 2 ]] || die "--influx-org requires a value"; INFLUX_ORG="$2"; shift 2 ;;
        --influx-org=*) INFLUX_ORG="${1#*=}"; shift ;;
        --influx-bucket) [[ $# -ge 2 ]] || die "--influx-bucket requires a value"; INFLUX_BUCKET="$2"; shift 2 ;;
        --influx-bucket=*) INFLUX_BUCKET="${1#*=}"; shift ;;
        --influx-token) [[ $# -ge 2 ]] || die "--influx-token requires a value"; INFLUX_TOKEN="$2"; shift 2 ;;
        --influx-token=*) INFLUX_TOKEN="${1#*=}"; shift ;;
        --msr) USE_MSR=1; shift ;;
        --read-smbios) READ_SMBIOS=1; shift ;;
        --) shift; CMD=("$@"); break ;;
        *) die "unknown option before --: $1" ;;
    esac
done

[[ ${#CMD[@]} -gt 0 ]] || die "a workload command is required after --"
require_cmd AMDuProfPcm
require_cmd python3
require_cmd curl

if [[ -z "${RUN_ID}" ]]; then RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"; fi
[[ "${RUN_ID}" =~ ^[A-Za-z0-9._:-]+$ ]] || die "run-id must contain only letters, numbers, dot, underscore, colon, or dash"
RUN_DIR="${OUT_DIR%/}/${RUN_ID}"
ROOFLINE_DIR="${RUN_DIR}/roofline/amd-uprof"
EVENTS_DIR="${RUN_DIR}/events"
METRICS_DIR="${RUN_DIR}/metrics"
LOGS_DIR="${RUN_DIR}/logs"
mkdir -p "${ROOFLINE_DIR}" "${EVENTS_DIR}" "${METRICS_DIR}" "${LOGS_DIR}"
: > "${METRICS_DIR}/influx.lp"

start_ns="$(date +%s%N)"
roofline_cmd=(AMDuProfPcm roofline -O "${ROOFLINE_DIR}")
if [[ "${USE_MSR}" -eq 1 ]]; then roofline_cmd+=(--msr); fi
if [[ "${READ_SMBIOS}" -eq 1 ]]; then roofline_cmd+=(--read-smbios); fi
roofline_cmd+=(-- "${CMD[@]}")

log "run directory: ${RUN_DIR}"
log "running AMD uProf roofline: ${roofline_cmd[*]}"
set +e
"${roofline_cmd[@]}" > "${LOGS_DIR}/amd-uprof-roofline.log" 2>&1
status=$?
set -e
end_ns="$(date +%s%N)"

mapfile -t reports < <(find "${ROOFLINE_DIR}" -type f -name 'report.html' | sort)
mapfile -t csvs < <(find "${ROOFLINE_DIR}" -type f -name '*.csv' | sort)
report_html=""
if [[ ${#reports[@]} -gt 0 ]]; then report_html="${reports[0]}"; fi

cat > "${RUN_DIR}/roofline/amd-uprof/manifest.json" <<EOF_MANIFEST
{
  "schema": "wcckit.amd_uprof_roofline.v1",
  "run_id": "${RUN_ID}",
  "pipeline": "${PIPELINE}",
  "tool": "amd-uprof-roofline",
  "command": $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "${CMD[@]}"),
  "exit_code": ${status},
  "started_ns": ${start_ns},
  "ended_ns": ${end_ns},
  "use_msr": $([[ "${USE_MSR}" -eq 1 ]] && printf true || printf false),
  "read_smbios": $([[ "${READ_SMBIOS}" -eq 1 ]] && printf true || printf false),
  "output_dir": "${ROOFLINE_DIR}",
  "report_html": "${report_html}",
  "report_html_count": ${#reports[@]},
  "csv_count": ${#csvs[@]}
}
EOF_MANIFEST

printf '{"ts_ns":%s,"run_id":"%s","pipeline":"%s","tool":"amd-uprof-roofline","exit_code":%s,"report_html":"%s","report_html_count":%s,"csv_count":%s,"use_msr":%s,"read_smbios":%s}\n' \
    "${end_ns}" "${RUN_ID}" "${PIPELINE}" "${status}" "${report_html}" "${#reports[@]}" "${#csvs[@]}" \
    "$([[ "${USE_MSR}" -eq 1 ]] && printf true || printf false)" "$([[ "${READ_SMBIOS}" -eq 1 ]] && printf true || printf false)" \
    > "${EVENTS_DIR}/amd-uprof-roofline.jsonl"

ok=false
if [[ "${status}" -eq 0 && -n "${report_html}" ]]; then ok=true; fi
printf 'wcckit_roofline_status,run_id=%s,pipeline=%s,tool=amd-uprof-roofline ok=%s,exit_code=%si,report_html_count=%si,csv_count=%si,use_msr=%s,read_smbios=%s,report_html=%s %s\n' \
    "$(lp_tag "${RUN_ID}")" "$(lp_tag "${PIPELINE}")" "${ok}" "${status}" "${#reports[@]}" "${#csvs[@]}" \
    "$([[ "${USE_MSR}" -eq 1 ]] && printf true || printf false)" "$([[ "${READ_SMBIOS}" -eq 1 ]] && printf true || printf false)" \
    "$(lp_string "${report_html}")" "${end_ns}" >> "${METRICS_DIR}/influx.lp"

push_influx
if [[ -n "${WCCKIT_HOST_UID:-}" && -n "${WCCKIT_HOST_GID:-}" ]]; then
    chown -R "${WCCKIT_HOST_UID}:${WCCKIT_HOST_GID}" "${RUN_DIR}" 2>/dev/null || true
fi

if [[ "${status}" -ne 0 ]]; then
    warn "AMDuProfPcm roofline exited with status ${status}; see ${LOGS_DIR}/amd-uprof-roofline.log"
    exit "${status}"
fi
log "roofline collection finished: ${RUN_DIR}"
if [[ -n "${report_html}" ]]; then log "HTML report: ${report_html}"; fi
