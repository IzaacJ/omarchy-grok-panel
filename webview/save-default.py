#!/usr/bin/env python3
import json
import os
import sys
from pathlib import Path

url = (sys.argv[1] if len(sys.argv) > 1 else "").strip()
title = (sys.argv[2] if len(sys.argv) > 2 else "").strip()
section = (sys.argv[3] if len(sys.argv) > 3 else "").strip()
state = Path(os.environ.get("XDG_DATA_HOME") or (Path.home() / ".local/share")) / "online.izz0.omarchy.grok-panel"
state.mkdir(parents=True, exist_ok=True)
payload = {"url": url, "title": title}
if section:
    payload["section"] = section
(state / "default-chat.json").write_text(
    json.dumps(payload, indent=2) + "\n",
    encoding="utf-8",
)
