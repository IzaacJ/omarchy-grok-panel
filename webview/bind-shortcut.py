#!/usr/bin/env python3
import json
import os
import subprocess
import sys
import time
from pathlib import Path

KEYS = "SUPER + CTRL + G"
DESC = "Toggle Grok panel"
CMD = "omarchy-shell online.izz0.omarchy.grok-panel toggle"
MODMASK = 68
KEY = "G"
STAMP = Path(os.environ.get("XDG_RUNTIME_DIR") or "/tmp") / "omarchy-grok-panel.shortcut"


def hypr_json(args):
    return json.loads(subprocess.check_output(["hyprctl"] + args))


def eval_lua(code):
    subprocess.check_call(["hyprctl", "eval", code], stdout=subprocess.DEVNULL)


def lua_string(value):
    return json.dumps(str(value), ensure_ascii=True)


def matching_binds():
    out = []
    for bind in hypr_json(["binds", "-j"]):
        if bind.get("mouse") or bind.get("release"):
            continue
        if int(bind.get("modmask") or 0) != MODMASK:
            continue
        if str(bind.get("key") or "") != KEY:
            continue
        out.append(bind)
    return out


def is_ours(bind):
    return str(bind.get("description") or "") == DESC


def write_stamp():
    now = time.time()
    STAMP.write_text("%.6f\n" % now, encoding="ascii")
    return now


def read_stamp():
    try:
        return float((STAMP.read_text(encoding="ascii") or "0").strip() or "0")
    except (OSError, ValueError):
        return 0.0


def bind():
    existing = matching_binds()
    if any(not is_ours(item) for item in existing):
        print("taken")
        return 2
    write_stamp()
    if existing:
        eval_lua("hl.unbind(%s)" % lua_string(KEYS))
    eval_lua(
        "hl.bind(%s, hl.dsp.exec_cmd(%s), { description = %s })"
        % (lua_string(KEYS), lua_string(CMD), lua_string(DESC))
    )
    print("bound")
    return 0


def unbind(delay):
    started = time.time()
    if delay > 0:
        time.sleep(delay)
        if read_stamp() > started:
            print("superseded")
            return 0
    existing = matching_binds()
    if not existing:
        print("absent")
        return 0
    if any(not is_ours(item) for item in existing):
        print("taken")
        return 0
    eval_lua("hl.unbind(%s)" % lua_string(KEYS))
    try:
        STAMP.unlink()
    except OSError:
        pass
    print("unbound")
    return 0


def main():
    action = sys.argv[1] if len(sys.argv) > 1 else ""
    if action == "bind":
        return bind()
    if action == "unbind":
        delay = 0.4 if "--delay" in sys.argv[2:] else 0.0
        return unbind(delay)
    print("usage: bind-shortcut.py bind|unbind [--delay]", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
