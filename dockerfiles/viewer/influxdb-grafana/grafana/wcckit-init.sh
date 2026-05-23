#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Start Grafana with WCCKIT viewer defaults. Grafana stores the docked
# navigation state in browser localStorage, so this injects a tiny default before
# the upstream Grafana entrypoint starts. The service runs this shim as root only
# long enough to edit the template, then drops back to the grafana user.
set -eu

INDEX=/usr/share/grafana/public/views/index.html
MARKER=wcckit-nav-default
BRAND_MARKER=wcckit-login-logo-width
BRAND_SCRIPT_MARKER=wcckit-login-hide-title
NAV_DEFAULT='    <script>try{window.localStorage.setItem("grafana.navigation.docked","false");window.localStorage.setItem("grafana.navigation.open","false");}catch(e){}</script><!-- wcckit-nav-default -->'
BRAND_STYLE='    <style id="wcckit-login-logo-width">img[src*="/public/build/static/img/grafana_icon"],img[src*="static/img/grafana_icon"]{width:min(440px,calc(100vw - 48px))!important;max-width:440px!important;height:auto!important;max-height:260px!important;object-fit:contain!important;border-radius:8px!important;overflow:hidden!important;}img[src*="/public/build/static/img/grafana_icon"]~h1,img[src*="static/img/grafana_icon"]~h1,img[src*="/public/build/static/img/grafana_icon"]+h1,img[src*="static/img/grafana_icon"]+h1{display:none!important;}</style>'
BRAND_SCRIPT='    <script id="wcckit-login-hide-title">(function(){function login(){return location.pathname.indexOf("/login")===0;}function setTitle(){if(login()&&document.title!=="WCCKIT"){document.title="WCCKIT";}else if(document.title.indexOf("Grafana")!==-1){document.title=document.title.replace(/Grafana/g,"WCCKIT");}}function hideTitle(){if(!login()){return;}document.querySelectorAll("h1,h2").forEach(function(el){var text=(el.textContent||"").trim();if(text==="Welcome"||text==="Welcome to Grafana"||text==="Workload Characterisation and Capacity Kit"){el.style.display="none";}});}function hideFooterLinks(){if(!login()){return;}document.querySelectorAll("a").forEach(function(el){var text=(el.textContent||"").trim();var href=el.getAttribute("href")||"";if(text==="Documentation"||text==="Support"||text==="Community"||text==="Grafana"||/grafana[.]com|docs[.]grafana/.test(href)){(el.closest("li")||el).style.display="none";}});}function apply(){setTitle();hideTitle();hideFooterLinks();}document.addEventListener("DOMContentLoaded",apply);new MutationObserver(apply).observe(document.documentElement,{childList:true,subtree:true,characterData:true});setInterval(setTitle,500);})();</script>'

LOGO_DIR=/etc/grafana/wcckit-logos
APP_ICON_PNG="$LOGO_DIR/PNGs/wcckit_app_icon_colour_transparent.png"
APP_ICON_SVG="$LOGO_DIR/SVGs/wcckit_logo_icon_only.svg"
HEADER_LOGO="$LOGO_DIR/SVGs/wcckit_logo_rectangle_cropped.svg"

[ -r "$APP_ICON_PNG" ] || APP_ICON_PNG="$LOGO_DIR/wcckit_app_icon_colour_transparent.png"
[ -r "$APP_ICON_SVG" ] || APP_ICON_SVG="$LOGO_DIR/wcckit_logo_icon_only.svg"
[ -r "$HEADER_LOGO" ] || HEADER_LOGO="$LOGO_DIR/wcckit_logo_rectangle_cropped.svg"

write_rounded_favicon() {
  src=$1
  dst=$2
  mime=$3
  encoded=$(base64 "$src" | tr -d '\n')
  tmp="${dst}.wcckit"
  {
    printf '%s\n' '<?xml version="1.0" encoding="utf-8"?>'
    printf '%s\n' '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" role="img" aria-label="WCCKIT">'
    printf '%s\n' '  <defs><clipPath id="wcckit-favicon-clip"><rect x="32" y="32" width="448" height="448" rx="96" ry="96"/></clipPath></defs>'
    printf '%s\n' '  <image href="data:'"${mime}"';base64,'"${encoded}"'" x="32" y="32" width="448" height="448" preserveAspectRatio="xMidYMid meet" clip-path="url(#wcckit-favicon-clip)"/>'
    printf '%s\n' '</svg>'
  } > "$tmp"
  cat "$tmp" > "$dst"
  rm -f "$tmp"
}

if [ -r "$APP_ICON_PNG" ]; then
  for dst in \
    /usr/share/grafana/public/img/fav32.png \
    /usr/share/grafana/public/build/img/fav32.png \
    /usr/share/grafana/public/img/apple-touch-icon.png \
    /usr/share/grafana/public/build/img/apple-touch-icon.png \
    /usr/share/grafana/public/img/mstile-150x150.png \
    /usr/share/grafana/public/build/img/mstile-150x150.png; do
    [ -w "$dst" ] && cp "$APP_ICON_PNG" "$dst"
  done
fi

if [ -r "$APP_ICON_SVG" ] || [ -r "$APP_ICON_PNG" ]; then
  if [ -r "$APP_ICON_SVG" ]; then
    favicon_src=$APP_ICON_SVG
    favicon_mime=image/svg+xml
  else
    favicon_src=$APP_ICON_PNG
    favicon_mime=image/png
  fi
  for dst in \
    /usr/share/grafana/public/img/wcckit_logo_icon_only.svg \
    /usr/share/grafana/public/build/img/wcckit_logo_icon_only.svg; do
    [ -w "$(dirname "$dst")" ] && write_rounded_favicon "$favicon_src" "$dst" "$favicon_mime"
  done
fi

if [ -r "$HEADER_LOGO" ]; then
  for dst in $(find /usr/share/grafana/public/build/static/img -type f -name 'grafana_icon*.svg' 2>/dev/null || true); do
    [ -w "$dst" ] && cp "$HEADER_LOGO" "$dst"
  done
fi

if [ -w "$INDEX" ]; then
  sed -i 's#<link rel="icon" type="image/png" href="\[\[.FavIcon\]\]" />#<link rel="icon" type="image/svg+xml" href="[[.Assets.ContentDeliveryURL]]public/img/wcckit_logo_icon_only.svg" />#' "$INDEX"
fi

if [ -w "$INDEX" ]; then
  sed -i 's#<title>.*</title>#<title>WCCKIT</title>#' "$INDEX"
fi

if [ -w "$INDEX" ]; then
  tmp="${INDEX}.wcckit"
  awk -v nav="$NAV_DEFAULT" -v style="$BRAND_STYLE" -v script="$BRAND_SCRIPT" -v nav_marker="$MARKER" -v brand_marker="$BRAND_MARKER" -v script_marker="$BRAND_SCRIPT_MARKER" '
    $0 == nav { next }
    $0 == style { next }
    $0 == script { next }
    index($0, nav_marker) { next }
    index($0, brand_marker) { next }
    index($0, script_marker) { next }
    { print }
  ' "$INDEX" > "$tmp"
  cat "$tmp" > "$INDEX"
  rm -f "$tmp"
fi

if [ -w "$INDEX" ] && ! grep -q "$MARKER" "$INDEX"; then
  tmp="${INDEX}.wcckit"
  awk -v nav="$NAV_DEFAULT" -v style="$BRAND_STYLE" -v script="$BRAND_SCRIPT" '
    /<head>/ && !done {
      print
      print nav
      print style
      print script
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
