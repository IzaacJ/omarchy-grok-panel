#!/usr/bin/env python3
import json
import os
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

PORT = 18765
STATE = Path(os.environ.get("XDG_DATA_HOME") or (Path.home() / ".local/share")) / "online.izz0.omarchy.grok-panel"
STATE.mkdir(parents=True, exist_ok=True)
CHATS = STATE / "chats.json"
REFRESH = STATE / "refresh-requested"
PIDFILE = Path(os.environ.get("XDG_RUNTIME_DIR") or "/tmp") / "omarchy-grok-panel.bridge.pid"


def take_pidfile():
    if PIDFILE.exists():
        try:
            old = int((PIDFILE.read_text(encoding="utf-8") or "0").strip() or "0")
            if old and old != os.getpid():
                os.kill(old, 15)
                time.sleep(0.1)
        except Exception:
            pass
    PIDFILE.write_text(str(os.getpid()) + "\n", encoding="utf-8")


class ReuseHTTPServer(HTTPServer):
    allow_reuse_address = True


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        return

    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Private-Network", "true")

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_GET(self):
        path = (self.path or "/").split("?", 1)[0]
        if path.rstrip("/") == "/refresh":
            pending = REFRESH.exists()
            if pending:
                try:
                    REFRESH.unlink()
                except OSError:
                    pass
            body = b"1" if pending else b"0"
            self.send_response(200)
            self._cors()
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        self.send_response(404)
        self._cors()
        self.end_headers()

    def do_POST(self):
        path = (self.path or "/").split("?", 1)[0]
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b"{}"
        if path.rstrip("/") == "/refresh":
            REFRESH.write_text("1\n", encoding="utf-8")
            self.send_response(204)
            self._cors()
            self.end_headers()
            return
        try:
            data = json.loads(raw.decode("utf-8") or "{}")
        except json.JSONDecodeError:
            data = {}
        CHATS.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
        self.send_response(204)
        self._cors()
        self.end_headers()


if __name__ == "__main__":
    take_pidfile()
    ReuseHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
