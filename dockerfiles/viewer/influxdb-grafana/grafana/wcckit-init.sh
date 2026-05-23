#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Start Grafana with WCCKIT viewer defaults. Grafana stores the docked
# navigation state in browser localStorage, so this injects a tiny default before
# the upstream Grafana entrypoint starts. The service runs this shim as root only
# long enough to edit the template, then drops back to the grafana user.
set -eu

INDEX=/usr/share/grafana/public/views/index.html
MARKER=wcckit-nav-default
NAV_DEFAULT='    <script>try{window.localStorage.setItem("grafana.navigation.docked","false");window.localStorage.setItem("grafana.navigation.open","false");}catch(e){}</script><!-- wcckit-nav-default -->'

if [ -w "$INDEX" ]; then
  tmp="${INDEX}.wcckit"
  awk '$0 != "$NAV_DEFAULT" { print }' "$INDEX" > "$tmp"
  cat "$tmp" > "$INDEX"
  rm -f "$tmp"
fi

if [ -w "$INDEX" ] && ! grep -q "$MARKER" "$INDEX"; then
  tmp="${INDEX}.wcckit"
  awk -v nav="$NAV_DEFAULT" '
    /<head>/ && !done {
      print
      print nav
      done=1
      next
    }
    { print }
  ' "$INDEX" > "$tmp"
  cat "$tmp" > "$INDEX"
  rm -f "$tmp"
fi

if [ "$(id -u)" = "0" ]; then
  exec su grafana -s /bin/bash -c /run.sh
fi

exec /run.sh
