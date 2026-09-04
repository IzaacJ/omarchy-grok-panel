#!/usr/bin/env python3
import os
import stat
from pathlib import Path
from urllib.request import Request, urlopen

TOKEN_PATH = Path(os.environ.get("XDG_RUNTIME_DIR") or "/tmp") / "omarchy-grok-panel.bridge.token"
flags = os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW
fd = os.open(TOKEN_PATH, flags)
try:
    st = os.fstat(fd)
    if not stat.S_ISREG(st.st_mode):
        raise SystemExit("bridge token is not a regular file")
    token = os.read(fd, 256).decode("ascii", "strict").strip()
finally:
    os.close(fd)
if len(token) < 16:
    raise SystemExit("bridge token is missing")
urlopen(
    Request(
        "http://127.0.0.1:18765/refresh",
        data=b"",
        method="POST",
        headers={"Authorization": "Bearer " + token},
    ),
    timeout=2,
).read()
