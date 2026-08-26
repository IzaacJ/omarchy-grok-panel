#!/usr/bin/env bash
set -euo pipefail
DIR=$(cd "$(dirname "$0")" && pwd)
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/online.izz0.omarchy.grok-panel/chromium"
mkdir -p "$DATA"
PIDFILE="${XDG_RUNTIME_DIR:-/tmp}/omarchy-grok-panel.webview.pid"
if [[ -f "$PIDFILE" ]]; then
  old=$(cat "$PIDFILE" || true)
  if [[ -n "${old:-}" ]] && kill -0 "$old" 2>/dev/null; then
    kill "$old" 2>/dev/null || true
    sleep 0.1
  fi
fi
echo $$ > "$PIDFILE"
# Chromium --app paints grok.com; Qt WebEngine on Wayland stayed black even
# though view-source showed the document. X11/XWayland keeps a stable WM_CLASS
# for placement.
exec /usr/bin/chromium \
  --ozone-platform=x11 \
  --class=omarchy-grok-panel \
  --app=https://grok.com \
  --user-data-dir="$DATA" \
  --no-first-run \
  --no-default-browser-check \
  --disable-features=TranslateUI,Translate \
  --disable-sync
