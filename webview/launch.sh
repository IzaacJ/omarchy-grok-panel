#!/usr/bin/env bash
set -euo pipefail
DIR=$(cd "$(dirname "$0")" && pwd)
STATE="${XDG_DATA_HOME:-$HOME/.local/share}/online.izz0.omarchy.grok-panel"
DATA="$STATE/chromium"
mkdir -p "$DATA"
URL="${1:-}"
if [[ -z "$URL" && -f "$STATE/default-chat.json" ]]; then
  URL=$(python3 -c "import json,sys; print((json.load(open(sys.argv[1])).get('url') or '').strip())" "$STATE/default-chat.json" || true)
fi
if [[ -z "${URL:-}" ]]; then
  URL="https://grok.com"
fi
PIDFILE="${XDG_RUNTIME_DIR:-/tmp}/omarchy-grok-panel.webview.pid"
if [[ -f "$PIDFILE" ]]; then
  old=$(cat "$PIDFILE" || true)
  if [[ -n "${old:-}" ]] && kill -0 "$old" 2>/dev/null; then
    kill "$old" 2>/dev/null || true
    sleep 0.1
  fi
fi
echo $$ > "$PIDFILE"
RUNTIME="${XDG_RUNTIME_DIR:-/tmp}"
TOKEN_FILE="$RUNTIME/omarchy-grok-panel.bridge.token"
EXT_DST="$RUNTIME/omarchy-grok-panel.ext"
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  if [[ -s "$TOKEN_FILE" ]]; then
    break
  fi
  sleep 0.05
done
if [[ -L "$EXT_DST" ]]; then
  rm -f "$EXT_DST"
fi
rm -rf "$EXT_DST"
mkdir -p "$EXT_DST"
cp -a "$DIR/no-context-menu/." "$EXT_DST/"
python3 - "$TOKEN_FILE" "$EXT_DST/token.js" <<'PY'
import json, os, stat, sys
token_path, dest = sys.argv[1], sys.argv[2]
token = ""
try:
    fd = os.open(token_path, os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW)
    try:
        st = os.fstat(fd)
        if stat.S_ISREG(st.st_mode):
            token = os.read(fd, 256).decode("ascii", "strict").strip()
    finally:
        os.close(fd)
except OSError:
    pass
with open(dest, "w", encoding="utf-8") as fh:
    fh.write("var GROK_PANEL_BRIDGE_TOKEN = %s;\n" % json.dumps(token))
PY
# Chromium --app paints grok.com; Qt WebEngine on Wayland stayed black even
# though view-source showed the document. X11/XWayland keeps a stable WM_CLASS
# for placement.
exec /usr/bin/chromium \
  --ozone-platform=x11 \
  --class=omarchy-grok-panel \
  --app="$URL" \
  --user-data-dir="$DATA" \
  --load-extension="$EXT_DST" \
  --no-first-run \
  --no-default-browser-check \
  --disable-popup-blocking \
  --disable-features=TranslateUI,Translate \
  --disable-sync
