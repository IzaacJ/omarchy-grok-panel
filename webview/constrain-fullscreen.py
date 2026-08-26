#!/usr/bin/env python3
"""While the panel is open, covering SUPER+F fullscreen would paint under
the layer-shell chrome and the pinned Chromium sidecar. Convert covering
fullscreen on the panel's monitor into Omarchy tiled fullscreen (internal
none, client fullscreen) so the window fills the remaining work area.
Restore covering fullscreen when the panel closes."""
import json
import os
import subprocess
import sys
from pathlib import Path

MODE = sys.argv[1] if len(sys.argv) > 1 else "constrain"
SCREEN_NAME = sys.argv[2] if len(sys.argv) > 2 else ""
CLASS = "omarchy-grok-panel"
STATE = Path(os.environ.get("XDG_RUNTIME_DIR") or "/tmp") / "omarchy-grok-panel.fs-converted"


def hypr_json(args):
    return json.loads(subprocess.check_output(["hyprctl"] + args))


def eval_lua(code, required=True):
    r = subprocess.run(["hyprctl", "eval", code], capture_output=True, text=True)
    if required and r.returncode != 0:
        sys.stderr.write(r.stderr or r.stdout or "hyprctl eval failed\n")
        r.check_returncode()
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
        "hl.dispatch(hl.dsp.window.fullscreen_state({ internal = %d, client = %d, window = w }))\n"
        % (addr, int(internal), int(client)),
        required=False,
    )


def covering(fs):
    try:
        n = int(fs)
    except (TypeError, ValueError):
        return False
    return n == 2 or n == 3


def tiled_client(fs_client):
    try:
        return int(fs_client) == 2
    except (TypeError, ValueError):
        return False


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
        return []
    try:
        data = json.loads(STATE.read_text(encoding="utf-8") or "[]")
        return [str(x) for x in data] if isinstance(data, list) else []
    except json.JSONDecodeError:
        return []


def save_converted(addrs):
    STATE.write_text(json.dumps(addrs) + "\n", encoding="utf-8")


def is_panel(c):
    cls = str(c.get("class") or "")
    initial = str(c.get("initialClass") or "")
    return cls == CLASS or initial == CLASS


def main():
    mon = monitor_id(SCREEN_NAME)
    converted = load_converted()
    if MODE != "constrain":
        still = []
        for addr in converted:
            found = None
            for c in hypr_json(["clients", "-j"]):
                if c.get("address") == addr:
                    found = c
                    break
            if not found:
                continue
            if covering(found.get("fullscreen")):
                continue
            if tiled_client(found.get("fullscreenClient")):
                set_fs(addr, 2, 2)
            still.append(addr)
        save_converted([])
        return

    if mon is None:
        return
    keep = []
    for c in hypr_json(["clients", "-j"]):
        if is_panel(c):
            continue
        if c.get("monitor") != mon:
            continue
        addr = str(c.get("address") or "")
        if not addr:
            continue
        if covering(c.get("fullscreen")):
            if set_fs(addr, 0, 2):
                keep.append(addr)
            continue
        if addr in converted and tiled_client(c.get("fullscreenClient")):
            keep.append(addr)
    save_converted(keep)


if __name__ == "__main__":
    main()
