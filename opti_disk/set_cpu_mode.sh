#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

dry_run=0
is_desktop=1
is_dell_laptop=0

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
  [[ "${EUID}" -eq 0 ]] || die "root privileges are required to change CPU performance settings"
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
Set CPU performance-oriented settings for opti_disk/WCCKIT measurements.

Options:
  --dry-run  Print planned commands without changing system state.
  -h, --help Print this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      dry_run=1
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

if [[ "${dry_run}" -eq 0 ]]; then
  require_cmd cpupower
  require_cmd lshw
  require_root
fi

echo "Setting CPU to Performance mode..."
echo

if command -v lshw >/dev/null 2>&1 && [[ "$(lshw 2>/dev/null | awk '/description/ {print $2; exit}')" != 'Desktop' ]]; then
  is_desktop=0
  echo "Running on a laptop..."
  if [[ "$(lshw 2>/dev/null | awk '/vendor/ {print $2; exit}')" == 'Dell' ]]; then
    echo "Dell laptop detected"
    echo
    is_dell_laptop=1
  fi
fi

if [[ "${dry_run}" -eq 0 && ! -w /sys/devices/system/cpu/cpuidle/current_governor ]]; then
  die "cannot write cpuidle governor; run as root or check kernel support"
fi

echo "Set CPU idle governor to TEO"
run bash -c "printf '%s\n' teo > /sys/devices/system/cpu/cpuidle/current_governor"
echo

if [[ "${is_dell_laptop}" -eq 1 ]]; then
  if [[ "${dry_run}" -eq 0 ]]; then
    require_cmd smbios-thermal-ctl
  fi
  echo "Setting Dell smbios thermal control to performance mode"
  run smbios-thermal-ctl --set-thermal-mode=Performance
  echo
fi

echo "Setting CPU energy bias to 0"
run cpupower set -b 0
echo

echo "Setting CPU to performance mode"
run cpupower frequency-set -g performance
echo

if [[ "${is_dell_laptop}" -eq 1 ]]; then
  echo "Limiting Dell laptop CPU to 3.9GHz"
  run cpupower frequency-set -u 3900000
  echo
fi

echo "Setting CPU to C1 state"
run cpupower idle-set -D 10
echo

echo "Finished setting CPU to Performance mode."
