#!/usr/bin/env bash
set -euo pipefail
# place.sh show|hide <screenName> <side> <width>
MODE=${1:-hide}
SCREEN_NAME=${2:-}
SIDE=${3:-right}
WIDTH=${4:-420}

python3 - "$MODE" "$SCREEN_NAME" "$SIDE" "$WIDTH" <<'PY'
import json, subprocess, sys, time

mode, screen_name, side, width_s = sys.argv[1:5]
width = int(width_s)
CLASS = "omarchy-grok-panel"
TITLE = "omarchy-grok-panel"

def hypr_json(args):
    return json.loads(subprocess.check_output(["hyprctl"] + args))

def eval_lua(code, required=True):
    r = subprocess.run(["hyprctl", "eval", code], capture_output=True, text=True)
    if required and r.returncode != 0:
        sys.stderr.write(r.stderr or r.stdout or "hyprctl eval failed\n")
        r.check_returncode()
    return r.returncode == 0

def wait_win(timeout=3.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        for c in hypr_json(["clients", "-j"]):
            if c.get("class") == CLASS or c.get("initialClass") == CLASS or c.get("title") == TITLE:
                return c
        time.sleep(0.08)
    return None

if not wait_win(0.4 if mode != "show" else 3.0):
    sys.exit(0 if mode != "show" else 1)

if mode != "show":
    eval_lua(
        'local w = hl.get_windows({ class = "%s" })[1] or hl.get_windows({ title = "%s" })[1]\n'
        "if not w then return end\n"
        "hl.dispatch(hl.dsp.window.move({ x = 50000, y = 0, relative = false, window = w }))\n"
        % (CLASS, TITLE)
    )
    sys.exit(0)

mons = hypr_json(["monitors", "-j"])
mon = next((m for m in mons if screen_name and m.get("name") == screen_name), None)
if mon is None:
    mon = next((m for m in mons if m.get("focused")), mons[0] if mons else None)
if not mon:
    sys.exit(1)

reserved = mon.get("reserved") or [0, 0, 0, 0]
top = int(reserved[1] or 0)
bottom = int(reserved[3] or 0)
mx, my = int(mon["x"]), int(mon["y"])
mw, mh = int(mon["width"]), int(mon["height"])
h = max(1, mh - top - bottom)
y = my + top
x = mx + mw - width if side == "right" else mx

eval_lua(
    "hl.window_rule({\n"
    "  name = \"omarchy-grok-panel-chrome\",\n"
    "  match = { class = \"^omarchy-grok-panel$\" },\n"
    "  float = true,\n"
    "  pin = true,\n"
    "  border_size = 0,\n"
    "  rounding = 0,\n"
    "  decorate = false,\n"
    "  no_shadow = true,\n"
    "  no_anim = true,\n"
    "  no_blur = true,\n"
    "  tag = \"-default-opacity\",\n"
    "  opacity = \"1 override 1 override 1 override\",\n"
    "  border_color = \"rgba(00000000)\",\n"
    "})\n"
)
for prop, value in (
    ("border_size", "0"),
    ("rounding", "0"),
    ("decorate", "false"),
    ("no_shadow", "true"),
    ("no_anim", "true"),
    ("no_blur", "true"),
    ("border_color", "rgba(00000000)"),
):
    eval_lua(
        "local w = hl.get_windows({ class = \"%s\" })[1] or hl.get_windows({ title = \"%s\" })[1]\n"
        "if not w then return end\n"
        "hl.dispatch(hl.dsp.window.set_prop({ prop = \"%s\", value = \"%s\", window = w }))\n"
        % (CLASS, TITLE, prop, value),
        required=False,
    )
eval_lua(
    "local w = hl.get_windows({ class = \"%s\" })[1] or hl.get_windows({ title = \"%s\" })[1]\n"
    "if not w then return end\n"
    "hl.dispatch(hl.dsp.window.float({ action = \"on\", window = w }))\n"
    "hl.dispatch(hl.dsp.window.pin({ action = \"on\", window = w }))\n"
    "hl.dispatch(hl.dsp.window.bring_to_top({ window = w }))\n"
    "hl.dispatch(hl.dsp.window.resize({ x = %d, y = %d, relative = false, window = w }))\n"
    "hl.dispatch(hl.dsp.window.move({ x = %d, y = %d, relative = false, window = w }))\n"
    % (CLASS, TITLE, width, h, x, y)
)
PY
