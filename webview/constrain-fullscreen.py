#!/usr/bin/env python3
"""While the panel is open, covering SUPER+F fullscreen paints under the
layer-shell chrome and the pinned Chromium sidecar.

Hyprland's fullscreen_state defaults to toggle. SUPER+F already sets client
fullscreen to 2, so dispatching internal=0 client=2 toggled it back to a
normal tile. Use action=set and compositor maximize (internal=1), which fills
the working area and keeps exclusive-zone margins.
"""
import json
import os
import subprocess
import sys
import time
from pathlib import Path

MODE = sys.argv[1] if len(sys.argv) > 1 else "constrain"
SCREEN_NAME = sys.argv[2] if len(sys.argv) > 2 else ""
CLASS = "omarchy-grok-panel"
STATE = Path(os.environ.get("XDG_RUNTIME_DIR") or "/tmp") / "omarchy-grok-panel.fs-converted"
TOGGLE_GRACE = 0.6


def hypr_json(args):
    return json.loads(subprocess.check_output(["hyprctl"] + args))


def eval_lua(code):
    r = subprocess.run(["hyprctl", "eval", code], capture_output=True, text=True)
    return r.returncode == 0


def set_fs(address, internal, client):
    addr = json.dumps(str(address or ""))
    return eval_lua(
        "local want = %s\n"
        "local w = nil\n"
        "for _, cand in ipairs(hl.get_windows()) do\n"
        "  if cand.address == want then w = cand break end\n"
        "end\n"
        "if not w then return end\n"
        "hl.dispatch(hl.dsp.window.fullscreen_state({\n"
        "  internal = %d, client = %d, action = \"set\", window = w\n"
        "}))\n"
        % (addr, int(internal), int(client))
    )


def as_int(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def covering(c):
    return as_int(c.get("fullscreen")) in (2, 3)


def constrained(c):
    internal = as_int(c.get("fullscreen"))
    client = as_int(c.get("fullscreenClient"))
    return internal == 1 or (internal == 0 and client == 2)


def idle(c):
    return as_int(c.get("fullscreen")) == 0 and as_int(c.get("fullscreenClient")) == 0


def monitor_id(name):
    mons = hypr_json(["monitors", "-j"])
    if name:
        for m in mons:
            if m.get("name") == name:
                return m.get("id")
    for m in mons:
        if m.get("focused"):
            return m.get("id")
    return mons[0].get("id") if mons else None


def load_converted():
    if not STATE.exists():
        return {}
    try:
        data = json.loads(STATE.read_text(encoding="utf-8") or "{}")
    except json.JSONDecodeError:
        return {}
    if isinstance(data, list):
        now = time.time()
        return {str(x): now for x in data}
    if isinstance(data, dict):
        out = {}
        for key, val in data.items():
            try:
                out[str(key)] = float(val)
            except (TypeError, ValueError):
                out[str(key)] = 0.0
        return out
    return {}


def save_converted(mapping):
    STATE.write_text(json.dumps(mapping) + "\n", encoding="utf-8")


def is_panel(c):
    cls = str(c.get("class") or "")
    initial = str(c.get("initialClass") or "")
    return cls == CLASS or initial == CLASS


def main():
    mon = monitor_id(SCREEN_NAME)
    converted = load_converted()
    now = time.time()
    if MODE != "constrain":
        for addr, _ts in list(converted.items()):
            found = None
            for c in hypr_json(["clients", "-j"]):
                if c.get("address") == addr:
                    found = c
                    break
            if not found or idle(found) or covering(found):
                continue
            if constrained(found):
                set_fs(addr, 2, 2)
        save_converted({})
        return

    if mon is None:
        return
    keep = {}
    for c in hypr_json(["clients", "-j"]):
        if is_panel(c):
            continue
        if c.get("monitor") != mon:
            continue
        addr = str(c.get("address") or "")
        if not addr:
            continue
        last = converted.get(addr)
        if covering(c):
            if last is not None and now - last > TOGGLE_GRACE:
                set_fs(addr, 0, 0)
                continue
            if set_fs(addr, 1, 2):
                keep[addr] = last if last is not None else now
            continue
        if last is not None and constrained(c):
            keep[addr] = last
    save_converted(keep)


if __name__ == "__main__":
    main()
