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

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "root privileges are required to reset CPU settings"
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
Reset CPU settings after opti_disk/WCCKIT measurements.

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

echo "Resetting CPU to Normal mode..."
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

echo "Resetting CPU to schedutil mode"
run cpupower frequency-set -g schedutil
echo

echo "Re-enabling all CPU C-States"
run cpupower idle-set -E
echo

if [[ "${is_dell_laptop}" -eq 1 ]]; then
  echo "Resetting Dell laptop CPU to 4.5GHz"
  run cpupower frequency-set -u 4500000
  echo
fi

echo "Resetting CPU energy bias to 0"
run cpupower set -b 0
echo

if [[ "${is_dell_laptop}" -eq 1 ]]; then
  if [[ "${dry_run}" -eq 0 ]]; then
    require_cmd smbios-thermal-ctl
  fi
  echo "Setting Dell smbios thermal control to balanced mode"
  run smbios-thermal-ctl --set-thermal-mode=Balanced
  echo
fi

echo "Finished resetting CPU to Normal mode."
