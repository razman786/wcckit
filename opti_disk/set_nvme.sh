#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

dry_run=0
mnt_point="nvme"
nvme_dev=""
is_4k_lba=0
override_4k_lba=0
sector_size=2048 # samsung pro 8192

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

require_root() {
    [[ "${EUID}" -eq 0 ]] || die "root privileges are required for destructive NVMe setup"
}

run() {
    if [[ "${dry_run}" -eq 1 ]]; then
        printf '[dry-run] '
        printf '%q ' "$@"
        printf '\n'
    else
        "$@"
    fi
}

usage() {
    cat <<'EOF'
Setup NVMe devices for radio-astronomy disk speed and efficiency testing.

This script is destructive in real mode. It can format an NVMe namespace,
rewrite the partition table, create an ext4 filesystem, set the scheduler,
and mount the resulting partition.

Syntax: set_nvme.sh --device <nvme0n1|/dev/nvme0n1> [options]

Options:
  -h, --help              Print this help.
  -d, --device DEVICE     Target NVMe namespace. Required in real mode.
  -m, --mount NAME        Mount point name under /mnt (default: nvme).
  -l, --lba-override N    Override automatic 4KB LBA detection (default: 0).
  -s, --sector-size N     Partition sector alignment (default: 2048).
      --dry-run           Print planned actions without changing the system.
EOF
}

normalize_device() {
    local dev="$1"
    [[ -n "${dev}" ]] || die "--device is required"

    if [[ "${dev}" == /dev/* ]]; then
        printf '%s\n' "${dev}"
    else
        printf '/dev/%s\n' "${dev}"
    fi
}

block_name_from_device() {
    basename "$1"
}

validate_sector_size() {
    [[ "${sector_size}" =~ ^[0-9]+$ ]] || die "sector size must be numeric"
    (( sector_size >= 2048 && sector_size <= 1048576 )) || die "sector size must be between 2048 and 1048576 sectors"
}

reject_system_device() {
    local dev="$1"
    local disk
    disk="$(block_name_from_device "${dev}")"

    [[ -b "${dev}" ]] || die "target device does not exist or is not a block device: ${dev}"

    while read -r name mountpoint; do
        [[ -n "${name}" ]] || continue
        [[ "${name}" == "${disk}" || "${name}" == "${disk}"p* || "${name}" == "${disk}"[0-9]* ]] || continue

        if [[ -n "${mountpoint}" ]]; then
            case "${mountpoint}" in
                /|/boot|/boot/*|/home|/home/*)
                    die "refusing to operate on ${dev}; ${name} is mounted at protected mountpoint ${mountpoint}"
                    ;;
                *)
                    die "refusing to operate on ${dev}; ${name} is currently mounted at ${mountpoint}"
                    ;;
            esac
        fi
    done < <(lsblk -nr -o NAME,MOUNTPOINT "${dev}")

    while read -r swap_dev _rest; do
        [[ "${swap_dev}" == Filename ]] && continue
        if [[ "${swap_dev}" == "${dev}" || "${swap_dev}" == "${dev}"p* || "${swap_dev}" == "${dev}"[0-9]* ]]; then
            die "refusing to operate on ${dev}; ${swap_dev} is configured as swap"
        fi
    done < /proc/swaps
}

confirm_destructive_action() {
    local dev="$1"

    cat <<EOF

WARNING: destructive NVMe setup requested.

Target device: ${dev}
Mount point:   /mnt/${mnt_point}
Alignment:     ${sector_size}s

Planned destructive actions:
  - format ${dev}
  - create a new GPT partition table on ${dev}
  - create one ext4 partition
  - create an ext4 filesystem on the discovered partition
  - set the I/O scheduler to none
  - mount the partition at /mnt/${mnt_point}

EOF

    read -r -p "Type the exact target device path to continue: " confirmation
    [[ "${confirmation}" == "${dev}" ]] || die "confirmation did not match ${dev}; aborting"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
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
        -m|--mount)
            [[ $# -ge 2 ]] || die "$1 requires a value"
            mnt_point="$2"
            shift 2
            ;;
        --mount=*)
            mnt_point="${1#*=}"
            shift
            ;;
        -l|--lba-override)
            [[ $# -ge 2 ]] || die "$1 requires a value"
            override_4k_lba="$2"
            shift 2
            ;;
        --lba-override=*)
            override_4k_lba="${1#*=}"
            shift
            ;;
        -s|--sector-size)
            [[ $# -ge 2 ]] || die "$1 requires a value"
            sector_size="$2"
            shift 2
            ;;
        --sector-size=*)
            sector_size="${1#*=}"
            shift
            ;;
        --dry-run)
            dry_run=1
            shift
            ;;
        *)
            die "unknown option: $1"
            ;;
    esac
done

validate_sector_size
[[ "${override_4k_lba}" =~ ^[0-9]+$ ]] || die "LBA override must be numeric"
[[ "${mnt_point}" =~ ^[A-Za-z0-9._-]+$ ]] || die "mount name must contain only letters, numbers, dot, underscore, or dash"

nvme_dev="$(normalize_device "${nvme_dev}")"
nvme_ns="$(block_name_from_device "${nvme_dev}")"

require_cmd findmnt
require_cmd lsblk

if [[ "${dry_run}" -eq 0 ]]; then
    require_cmd nvme
    require_cmd parted
    require_cmd mkfs.ext4
    require_root
    reject_system_device "${nvme_dev}"
    confirm_destructive_action "${nvme_dev}"
else
    warn "dry-run mode: not validating block-device safety against live destructive operations"
fi

echo "Starting NVMe device setup."
echo "Target device: ${nvme_dev}"
echo "NVMe controller and namespace: ${nvme_ns}"
echo "Mount point: /mnt/${mnt_point}"
echo

echo "Checking if /mnt/${mnt_point} is in use"
if findmnt -M "/mnt/${mnt_point}" >/dev/null 2>&1; then
    echo "Mount point in use, unmounting..."
    run umount "/mnt/${mnt_point}"
else
    echo "Mount point not in use"
fi

echo
echo "Checking for supported LBA sizes"
if [[ "${dry_run}" -eq 1 ]]; then
    echo "[dry-run] would check LBA formats with nvme id-ns"
    if [[ "${override_4k_lba}" -eq 0 ]]; then
        echo "[dry-run] would format using detected LBA size"
    else
        echo "[dry-run] would format using 512-byte LBA because override is set"
    fi
elif [[ "${override_4k_lba}" -eq 0 ]]; then
    if nvme id-ns "${nvme_dev}" -H | grep -q 'LBA Format.*4096'; then
        echo "Found 4KB LBA support; formatting NVMe with 4096-byte LBA"
        is_4k_lba=1
        run nvme format -b 4096 "${nvme_dev}" -fr
    else
        echo "4KB LBA support not found; formatting NVMe with 512-byte LBA"
        run nvme format -b 512 "${nvme_dev}" -fr
    fi
else
    echo "Override set; formatting NVMe with 512-byte LBA"
    run nvme format -b 512 "${nvme_dev}" -fr
fi

echo
echo "Creating GPT partition table"
run parted -a optimal "${nvme_dev}" mklabel gpt

echo "Creating aligned primary ext4 partition"
if [[ "${is_4k_lba}" -eq 1 ]]; then
    run parted "${nvme_dev}" mkpart primary ext4 256s 100%
else
    run parted "${nvme_dev}" mkpart primary ext4 "${sector_size}s" 100%
fi

echo "Checking partition 1 alignment"
run parted "${nvme_dev}" align-check opt 1

echo
echo "Partition table output:"
run parted "${nvme_dev}" print

if [[ "${dry_run}" -eq 1 ]]; then
    nvme_part="${nvme_ns}p1"
    echo "[dry-run] would use first partition /dev/${nvme_part}"
else
    mapfile -t partitions < <(lsblk -nr -o NAME,TYPE "${nvme_dev}" | awk '$2 == "part" {print $1}')
    [[ "${#partitions[@]}" -eq 1 ]] || die "expected exactly one partition on ${nvme_dev}, found ${#partitions[@]}"
    nvme_part="${partitions[0]}"
    echo "Using partition /dev/${nvme_part} for filesystem"
fi

echo "Creating ext4 filesystem"
run mkfs.ext4 "/dev/${nvme_part}"

echo "Setting NVMe device I/O scheduler to [none]"
run bash -c "printf '%s\n' none > '/sys/block/${nvme_ns}/queue/scheduler'"

if [[ -d "/mnt/${mnt_point}" ]]; then
    echo "Using /mnt/${mnt_point} mount point"
else
    echo "Creating /mnt/${mnt_point} mount point"
    run mkdir "/mnt/${mnt_point}"
fi

echo "Mounting /dev/${nvme_part} with noatime"
run mount -o defaults,noatime "/dev/${nvme_part}" "/mnt/${mnt_point}"

echo
echo "Finished NVMe setup"
echo "Current configuration:"
echo "Device: ${nvme_dev}"
echo "Partition: /dev/${nvme_part}"
echo "Alignment: ${sector_size}s"
echo "Mount: /mnt/${mnt_point}"
echo "4KB LBA: ${is_4k_lba}"
