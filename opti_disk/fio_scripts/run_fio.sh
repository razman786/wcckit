#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"

run_test="all"
timeouts=10
nvme_dev="/dev/nvme0n1"
dry_run=0
json_output=1
run_root=""
steps_file=""
first_temp=""
second_temp=""
first_cpu_temp=""
cpu_list=""
target_dir=""

# opti_disk is the disk-focused WCF subset: it characterises NVMe speed and
# efficiency settings that can support radio-astronomy processing pipelines.

die() {
    echo "Error: $*" >&2
    exit 1
}

warn() {
    echo "Warning: $*" >&2
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

have_cmd() {
    command -v "$1" >/dev/null 2>&1
}

normalize_device() {
    local dev="$1"
    [[ -n "${dev}" ]] || die "device cannot be empty"
    if [[ "${dev}" == /dev/* ]]; then
        printf '%s\n' "${dev}"
    else
        printf '/dev/%s\n' "${dev}"
    fi
}

block_name_from_device() {
    basename "$1"
}

discover_target_dir() {
    local dev="$1"
    local mountpoints=()

    if [[ "${dry_run}" -eq 1 ]]; then
        if mapfile -t mountpoints < <(lsblk -nr -o TYPE,MOUNTPOINT "${dev}" 2>/dev/null | awk '$1 == "part" && $2 != "" {print $2}'); then
            :
        fi
        if [[ "${#mountpoints[@]}" -eq 1 ]]; then
            printf '%s\n' "${mountpoints[0]}"
        else
            printf '/mnt/nvme\n'
        fi
        return
    fi

    mapfile -t mountpoints < <(lsblk -nr -o TYPE,MOUNTPOINT "${dev}" | awk '$1 == "part" && $2 != "" {print $2}')
    [[ "${#mountpoints[@]}" -eq 1 ]] || die "expected exactly one mounted partition for ${dev}; found ${#mountpoints[@]}. Pass --target-dir explicitly if needed"
    printf '%s\n' "${mountpoints[0]}"
}

validate_target_dir() {
    if [[ -z "${target_dir}" ]]; then
        target_dir="$(discover_target_dir "${nvme_dev}")"
    fi

    if [[ "${dry_run}" -eq 1 ]]; then
        return
    fi

    [[ -b "${nvme_dev}" ]] || die "target device does not exist or is not a block device: ${nvme_dev}"
    [[ -d "${target_dir}" ]] || die "fio target directory does not exist: ${target_dir}"
    [[ -w "${target_dir}" ]] || die "fio target directory is not writable: ${target_dir}"
}

usage() {
    cat <<'EOF'
Run fio workloads for opti_disk radio-astronomy disk speed and efficiency characterisation.

Syntax: run_fio.sh [options]

Options:
  -h, --help              Print this help.
  -t, --test TEST         Select test: all|seq|rand|writes|reads.
  -d, --device DEVICE     Target NVMe namespace or path (default: /dev/nvme0n1).
      --target-dir DIR    Mounted directory where fio creates its test file.
      --dry-run           Create manifest and print commands without running fio or flushing caches.
      --text-output       Disable fio JSON output.
EOF
}

format_command() {
    printf '%q ' "$@"
}

run_or_dry() {
    if [[ "${dry_run}" -eq 1 ]]; then
        printf '[dry-run] '
        format_command "$@"
        printf '\n'
    else
        "$@"
    fi
}

capture_or_na() {
    local label="$1"
    shift
    if "$@" >/tmp/wcckit_capture.$$ 2>/tmp/wcckit_capture_err.$$; then
        sed 's/[[:space:]]*$//' /tmp/wcckit_capture.$$
    else
        printf 'unavailable (%s)' "${label}"
    fi
    rm -f /tmp/wcckit_capture.$$ /tmp/wcckit_capture_err.$$
}

append_section() {
    local title="$1"
    local file="$2"
    {
        echo
        echo "[${title}]"
        if [[ -s "${file}" ]]; then
            cat "${file}"
        else
            echo "unavailable"
        fi
    } >> "${run_root}/manifest.txt"
}

init_run_dir() {
    local timestamp
    timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
    local run_parent
    run_parent="${WCCKIT_OPTI_DISK_RUN_PARENT:-${repo_root}/runs}"
    run_root="${run_parent}/${timestamp}"
    mkdir -p "${run_root}/fio" "${run_root}/logs"
    steps_file="${run_root}/steps.tsv"
    printf 'step\tstart_utc\tend_utc\tstatus\tcommand\n' > "${steps_file}"
}

write_manifest() {
    local device_name
    local tmp_file
    device_name="$(block_name_from_device "${nvme_dev}")"

    cat > "${run_root}/manifest.txt" <<EOF
WCCKIT opti_disk run manifest

Scope: opti_disk subset for NVMe disk speed and efficiency characterisation for radio-astronomy style processing pipelines.
Dry run: ${dry_run}
Timestamp UTC: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Hostname: $(hostname 2>/dev/null || echo unavailable)
User: $(id -un 2>/dev/null || echo unavailable)
Working directory: $(pwd)
Repository root: ${repo_root}
Git commit: $(git -C "${repo_root}" rev-parse --short HEAD 2>/dev/null || echo unavailable)
Kernel: $(uname -a 2>/dev/null || echo unavailable)
OS release: $(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-unavailable}" || echo unavailable)
CPU model: $(awk -F: '/model name/ {sub(/^ /, "", $2); print $2; exit}' /proc/cpuinfo 2>/dev/null || echo unavailable)
Online CPU list: $(lscpu 2>/dev/null | awk -F: '/On-line CPU/ {gsub(/^ +/, "", $2); print $2; exit}' || echo unavailable)
CPU governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo unavailable)
cpuidle governor: $(cat /sys/devices/system/cpu/cpuidle/current_governor 2>/dev/null || echo unavailable)
fio version: $(fio --version 2>/dev/null || echo unavailable)
nvme-cli version: $(nvme version 2>/dev/null | head -n 1 || echo unavailable)
Target device: ${nvme_dev}
Target block name: ${device_name}
Script path: ${BASH_SOURCE[0]}
Selected test: ${run_test}
JSON output: ${json_output}
Fio target directory: ${target_dir}
Fio target file: ${target_dir}/test
EOF

    tmp_file="${run_root}/logs/lsblk.txt"
    lsblk -o NAME,TYPE,SIZE,MODEL,FSTYPE,MOUNTPOINTS "${nvme_dev}" > "${tmp_file}" 2>&1 || true
    append_section "lsblk" "${tmp_file}"

    tmp_file="${run_root}/logs/mounts.txt"
    findmnt -rn -T "${target_dir}" > "${tmp_file}" 2>&1 || true
    append_section "mounts" "${tmp_file}"

    tmp_file="${run_root}/logs/nvme_id_ctrl.txt"
    nvme id-ctrl "${nvme_dev}" > "${tmp_file}" 2>&1 || true
    append_section "nvme id-ctrl" "${tmp_file}"

    tmp_file="${run_root}/logs/nvme_module_params.txt"
    {
        echo "poll_queues=$(cat /sys/module/nvme/parameters/poll_queues 2>/dev/null || echo unavailable)"
        echo "write_queues=$(cat /sys/module/nvme/parameters/write_queues 2>/dev/null || echo unavailable)"
        echo "io_queue_depth=$(cat /sys/module/nvme/parameters/io_queue_depth 2>/dev/null || echo unavailable)"
    } > "${tmp_file}"
    append_section "nvme module parameters" "${tmp_file}"
}

record_step() {
    local step="$1"
    local start="$2"
    local end="$3"
    local status="$4"
    shift 4
    printf '%s\t%s\t%s\t%s\t' "${step}" "${start}" "${end}" "${status}" >> "${steps_file}"
    printf '%q ' "$@" >> "${steps_file}"
    printf '\n' >> "${steps_file}"
}

run_fio_job() {
    local step="$1"
    local job_file="$2"
    local output_file="$3"
    local start
    local end
    local status="ok"
    local cmd=(fio "${script_dir}/${job_file}" "--directory=${target_dir}" "--output=${run_root}/fio/${output_file}")

    if [[ "${json_output}" -eq 1 ]]; then
        cmd+=(--output-format=json)
    fi

    start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "${step}"
    printf 'Command: '
    format_command env "CPULIST=${cpu_list}" "${cmd[@]}"
    printf '\n'

    if [[ "${dry_run}" -eq 1 ]]; then
        printf '[dry-run] '
        format_command env "CPULIST=${cpu_list}" "${cmd[@]}"
        printf '\n'
    else
        if ! CPULIST="${cpu_list}" "${cmd[@]}"; then
            status="failed"
        fi
    fi

    end="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    record_step "${step}" "${start}" "${end}" "${status}" env "CPULIST=${cpu_list}" "${cmd[@]}"
    [[ "${status}" == ok ]] || die "fio job failed: ${step}"
}

exec_temp_1() {
    if [[ -n "${second_temp}" ]]; then
        nvme smart-log "${nvme_dev}" | awk '/Temperature Sensor 1/ {print $5; exit}'
    else
        nvme smart-log "${nvme_dev}" | awk '/temperature/ {print $3; exit}'
    fi
}

exec_temp_2() {
    nvme smart-log "${nvme_dev}" | awk '/Temperature Sensor 2/ {print $5; exit}'
}

exec_cpu_temp() {
    sensors -u | awk '/Package id 0/ {pkg=1} pkg && /temp1_input/ {printf "%d\n", $2; exit}'
}

check_temp() {
    if [[ "${dry_run}" -eq 1 || -z "${first_temp}" || -z "${first_cpu_temp}" ]]; then
        echo "Temperature gate skipped."
        return
    fi

    while [[ "${first_temp}" -lt "$(exec_temp_1)" ]]; do
        echo -ne "Waiting for NVMe temp $(exec_temp_1)C <= ${first_temp}C and CPU temp $(exec_cpu_temp)C <= ${first_cpu_temp}C\r"
        sleep 3
    done

    if [[ -n "${second_temp}" ]]; then
        while [[ "${second_temp}" -lt "$(exec_temp_2)" ]]; do
            echo -ne "Waiting for second NVMe temp $(exec_temp_2)C <= ${second_temp}C and CPU temp $(exec_cpu_temp)C <= ${first_cpu_temp}C\r"
            sleep 3
        done
    fi

    while [[ "${first_cpu_temp}" -lt "$(exec_cpu_temp)" ]]; do
        echo -ne "Waiting for NVMe temp $(exec_temp_1)C <= ${first_temp}C and CPU temp $(exec_cpu_temp)C <= ${first_cpu_temp}C\r"
        sleep 3
    done
    echo
}

flush_disk() {
    echo
    echo "Flushing disk caches and target device."
    if [[ "${dry_run}" -eq 1 ]]; then
        echo "[dry-run] sync"
        echo "[dry-run] printf 3 > /proc/sys/vm/drop_caches"
        echo "[dry-run] hdparm -f ${nvme_dev}"
        echo "[dry-run] nvme flush ${nvme_dev}"
        return
    fi

    sync
    printf 3 > /proc/sys/vm/drop_caches
    hdparm -f "${nvme_dev}"
    nvme flush "${nvme_dev}"
}

collect_baseline() {
    local online
    online="$(lscpu | awk -F: '/On-line CPU/ {gsub(/^ +/, "", $2); print $2; exit}')"
    cpu_list="${WCCKIT_CPULIST:-${online}}"

    echo "Gathering CPU and NVMe temperatures."
    if [[ "${dry_run}" -eq 1 ]]; then
        echo "[dry-run] temperature collection skipped"
        return
    fi

    if have_cmd nvme; then
        second_temp="$(nvme smart-log "${nvme_dev}" | awk '/Temperature Sensor 2/ {print $5; exit}' || true)"
        if [[ -n "${second_temp}" ]]; then
            first_temp="$(nvme smart-log "${nvme_dev}" | awk '/Temperature Sensor 1/ {print $5; exit}' || true)"
        else
            first_temp="$(nvme smart-log "${nvme_dev}" | awk '/temperature/ {print $3; exit}' || true)"
        fi
    fi

    if have_cmd sensors; then
        first_cpu_temp="$(exec_cpu_temp || true)"
    fi

    if [[ -n "${first_cpu_temp}" ]]; then
        first_cpu_temp="$((first_cpu_temp + 2))"
    else
        warn "CPU temperature unavailable; CPU temperature gate disabled"
    fi

    if [[ -n "${first_temp}" ]]; then
        first_temp="$((first_temp + 2))"
    else
        warn "NVMe temperature unavailable; NVMe temperature gate disabled"
    fi

    if [[ -n "${second_temp}" ]]; then
        second_temp="$((second_temp + 2))"
    fi
}

setup_test() {
    local start
    local end
    local status="ok"
    local cmd=(fio "${script_dir}/write.fio" "--directory=${target_dir}" --create_only=1)

    echo "Creating test file."
    start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    if [[ "${dry_run}" -eq 1 ]]; then
        printf '[dry-run] '
        format_command env "CPULIST=${cpu_list}" "${cmd[@]}"
        printf '\n'
    else
        if ! CPULIST="${cpu_list}" "${cmd[@]}"; then
            status="failed"
        fi
    fi
    end="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    record_step "create-test-file" "${start}" "${end}" "${status}" env "CPULIST=${cpu_list}" "${cmd[@]}"
    [[ "${status}" == ok ]] || die "failed creating fio test file"

    flush_disk
    check_temp
    echo "Pausing for 30 secs."
    if [[ "${dry_run}" -eq 1 ]]; then
        echo "[dry-run] sleep 30"
    else
        sleep 30
    fi
}

seq_write() {
    run_fio_job "sequential-write-2048k" write.fio opti_write.json
    flush_disk
    check_temp
    pause_between_tests
}

seq_read() {
    run_fio_job "sequential-read-2048k" read.fio opti_read.json
    flush_disk
    check_temp
    pause_between_tests
}

rand_write() {
    run_fio_job "random-write-4k" randomwrite.fio opti_randwrite.json
    flush_disk
    check_temp
    pause_between_tests
}

rand_read() {
    run_fio_job "random-read-4k" randomread.fio opti_randread.json
    flush_disk
    check_temp
    pause_between_tests
}

rand_rw() {
    run_fio_job "random-read-write-4k" randomrw.fio opti_randrw.json
    flush_disk
    check_temp
    pause_between_tests
}

pause_between_tests() {
    echo "Pausing for ${timeouts} secs."
    if [[ "${dry_run}" -eq 1 ]]; then
        echo "[dry-run] sleep ${timeouts}"
    else
        sleep "${timeouts}"
    fi
}

exec_seq() {
    seq_write
    seq_read
}

exec_rand() {
    rand_write
    rand_read
    rand_rw
}

run_selected() {
    collect_baseline
    setup_test

    case "${run_test}" in
        all)
            exec_seq
            exec_rand
            ;;
        seq)
            exec_seq
            ;;
        rand)
            exec_rand
            ;;
        writes)
            seq_write
            rand_write
            ;;
        reads)
            seq_read
            rand_read
            ;;
        *)
            die "invalid test '${run_test}'; expected all, seq, rand, writes, or reads"
            ;;
    esac
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -t|--test)
            [[ $# -ge 2 ]] || die "$1 requires a value"
            run_test="$2"
            shift 2
            ;;
        --test=*)
            run_test="${1#*=}"
            shift
            ;;
        -d|--device)
            [[ $# -ge 2 ]] || die "$1 requires a value"
            nvme_dev="$2"
            shift 2
            ;;
        --device=*)
            nvme_dev="${1#*=}"
            shift
            ;;
        --target-dir)
            [[ $# -ge 2 ]] || die "$1 requires a value"
            target_dir="$2"
            shift 2
            ;;
        --target-dir=*)
            target_dir="${1#*=}"
            shift
            ;;
        --dry-run)
            dry_run=1
            shift
            ;;
        --text-output)
            json_output=0
            shift
            ;;
        *)
            die "unknown option: $1"
            ;;
    esac
done

case "${run_test}" in
    all|seq|rand|writes|reads) ;;
    *) die "invalid test '${run_test}'; expected all, seq, rand, writes, or reads" ;;
esac

nvme_dev="$(normalize_device "${nvme_dev}")"

require_cmd lsblk
require_cmd awk
validate_target_dir

require_cmd lscpu
if [[ "${dry_run}" -eq 0 ]]; then
    require_cmd fio
    require_cmd nvme
    require_cmd hdparm
fi

init_run_dir
write_manifest

{
    echo "Starting fio tests."
    echo "Run directory: ${run_root}"
    echo "Target device: ${nvme_dev}"
    echo "fio target directory: ${target_dir}"
    echo "Selected test: ${run_test}"
    echo "Dry run: ${dry_run}"
} | tee "${run_root}/logs/run.log"

run_selected | tee -a "${run_root}/logs/run.log"

echo "Finished fio test workflow."
echo "Run directory: ${run_root}"
