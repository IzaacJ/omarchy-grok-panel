#!/usr/bin/env python3
import errno
import hmac
import json
import os
import re
import secrets
import stat
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

PORT = 18765
MAX_BODY = 1 << 20
ALLOWED_ORIGIN = re.compile(r"^https://([a-z0-9-]+\.)*grok\.com$")
ALLOWED_HOSTS = {"127.0.0.1", "localhost"}
TOKEN_BYTES = 256

STATE = Path()
CHATS = Path()
REFRESH = Path()
PIDFILE = Path()
TOKEN_PATH = Path()
TOKEN = ""


def configure(*, state_dir=None, runtime_dir=None, token=None):
    global STATE, CHATS, REFRESH, PIDFILE, TOKEN_PATH, TOKEN
    data_home = Path(os.environ.get("XDG_DATA_HOME") or (Path.home() / ".local/share"))
    run_home = Path(os.environ.get("XDG_RUNTIME_DIR") or "/tmp")
    STATE = Path(state_dir) if state_dir is not None else data_home / "online.izz0.omarchy.grok-panel"
    runtime = Path(runtime_dir) if runtime_dir is not None else run_home
    CHATS = STATE / "chats.json"
    REFRESH = STATE / "refresh-requested"
    PIDFILE = runtime / "omarchy-grok-panel.bridge.pid"
    TOKEN_PATH = runtime / "omarchy-grok-panel.bridge.token"
    _ensure_dir(STATE, 0o700)
    _ensure_dir(runtime, None)
    TOKEN = token if token is not None else _load_or_create_token(TOKEN_PATH)


def _ensure_dir(path, mode):
    path.mkdir(parents=True, exist_ok=True)
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC | os.O_NOFOLLOW
    fd = os.open(path, flags)
    try:
        if mode is not None:
            try:
                os.fchmod(fd, mode)
            except OSError:
                pass
        st = os.fstat(fd)
        if not stat.S_ISDIR(st.st_mode):
            raise OSError(errno.ENOTDIR, "not a directory", str(path))
    finally:
        os.close(fd)


def _open_dir(path):
    return os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC | os.O_NOFOLLOW)


def _load_or_create_token(path):
    flags = os.O_RDWR | os.O_CREAT | os.O_CLOEXEC | os.O_NOFOLLOW
    fd = os.open(path, flags, 0o600)
    try:
        os.fchmod(fd, 0o600)
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode):
            raise OSError(errno.EPERM, "token path is not a regular file", str(path))
        existing = os.read(fd, TOKEN_BYTES).decode("ascii", "strict").strip()
        if len(existing) >= 16:
            return existing
        token = secrets.token_urlsafe(32)
        os.lseek(fd, 0, os.SEEK_SET)
        os.ftruncate(fd, 0)
        os.write(fd, (token + "\n").encode("ascii"))
        os.fsync(fd)
        return token
    finally:
        os.close(fd)


def atomic_write(path, data, mode=0o600):
    if not isinstance(data, (bytes, bytearray)):
        raise TypeError("data must be bytes")
    dir_fd = _open_dir(path.parent)
    tmp_name = None
    try:
        try:
            existing = os.open(
                path.name, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC, dir_fd=dir_fd
            )
        except FileNotFoundError:
            existing = None
        except OSError as e:
            if e.errno == errno.ELOOP:
                raise OSError(errno.ELOOP, "refusing symlink state path", str(path)) from e
            raise
        if existing is not None:
            try:
                st = os.fstat(existing)
                if not stat.S_ISREG(st.st_mode):
                    raise OSError(errno.EPERM, "refusing non-regular state file", str(path))
            finally:
                os.close(existing)
        tmp_name = f".{path.name}.{os.getpid()}.{secrets.token_hex(8)}.tmp"
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC
        tmp_fd = os.open(tmp_name, flags, mode, dir_fd=dir_fd)
        try:
            os.fchmod(tmp_fd, mode)
            view = memoryview(data)
            while view:
                n = os.write(tmp_fd, view)
                view = view[n:]
            os.fsync(tmp_fd)
        except Exception:
            os.close(tmp_fd)
            try:
                os.unlink(tmp_name, dir_fd=dir_fd)
            except OSError:
                pass
            tmp_name = None
            raise
        os.close(tmp_fd)
        os.replace(tmp_name, path.name, src_dir_fd=dir_fd, dst_dir_fd=dir_fd)
        tmp_name = None
        try:
            os.fsync(dir_fd)
        except OSError:
            pass
    finally:
        if tmp_name is not None:
            try:
                os.unlink(tmp_name, dir_fd=dir_fd)
            except OSError:
                pass
        os.close(dir_fd)


def take_regular(path):
    dir_fd = _open_dir(path.parent)
    try:
        try:
            fd = os.open(path.name, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC, dir_fd=dir_fd)
        except FileNotFoundError:
            return False
        except OSError as e:
            if e.errno == errno.ELOOP:
                return False
            raise
        try:
            st = os.fstat(fd)
            if not stat.S_ISREG(st.st_mode):
                return False
        finally:
            os.close(fd)
        os.unlink(path.name, dir_fd=dir_fd)
        return True
    finally:
        os.close(dir_fd)


def take_pidfile():
    if PIDFILE.exists():
        try:
            old = int((PIDFILE.read_text(encoding="utf-8") or "0").strip() or "0")
            if old and old != os.getpid():
                os.kill(old, 15)
                time.sleep(0.1)
        except Exception:
            pass
    atomic_write(PIDFILE, (str(os.getpid()) + "\n").encode("ascii"))


class ReuseHTTPServer(HTTPServer):
    allow_reuse_address = True


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        return

    def _origin(self):
        origin = (self.headers.get("Origin") or "").strip()
        if origin and ALLOWED_ORIGIN.fullmatch(origin):
            return origin
        return None

    def _host_ok(self):
        host = (self.headers.get("Host") or "").strip().lower()
        if not host or host.startswith("["):
            return False
        name = host.rsplit(":", 1)[0]
        return name in ALLOWED_HOSTS

    def _cors(self, origin):
        if not origin:
            return
        self.send_header("Access-Control-Allow-Origin", origin)
        self.send_header("Vary", "Origin")
        self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Max-Age", "600")

    def _send(self, code, origin, body=b"", content_type="text/plain"):
        self.send_response(code)
        self._cors(origin)
        self.send_header("Cache-Control", "no-store")
        if body:
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
        else:
            self.send_header("Content-Length", "0")
        self.end_headers()
        if body:
            self.wfile.write(body)

    def _authorized(self):
        header = self.headers.get("Authorization") or ""
        prefix = "Bearer "
        if not header.startswith(prefix):
            return False
        got = header[len(prefix):].strip()
        if not TOKEN or not got:
            return False
        return hmac.compare_digest(got, TOKEN)

    def _content_length(self):
        raw = self.headers.get("Content-Length")
        if raw is None or raw == "":
            return 0
        if len(raw) > 16:
            return None
        try:
            n = int(raw)
        except ValueError:
            return None
        if n < 0:
            return None
        return n

    def _read_body(self, origin):
        length = self._content_length()
        if length is None:
            self._send(400, origin)
            return None
        if length > MAX_BODY:
            self._send(413, origin)
            return None
        return self.rfile.read(length) if length else b""

    def do_OPTIONS(self):
        if not self._host_ok():
            self._send(403, None)
            return
        origin_header = (self.headers.get("Origin") or "").strip()
        origin = self._origin()
        if origin_header and not origin:
            self._send(403, None)
            return
        self.send_response(204)
        self._cors(origin)
        if origin:
            self.send_header("Access-Control-Allow-Private-Network", "true")
        self.send_header("Content-Length", "0")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()

    def do_GET(self):
        self._handle("GET")

    def do_POST(self):
        self._handle("POST")

    def _handle(self, method):
        origin_header = (self.headers.get("Origin") or "").strip()
        origin = self._origin()
        if not self._host_ok() or (origin_header and not origin):
            self._send(403, None)
            return
        if not self._authorized():
            self._send(401, origin)
            return
        path = (self.path or "/").split("?", 1)[0].rstrip("/") or "/"
        if method == "GET" and path == "/refresh":
            pending = take_regular(REFRESH)
            body = b"1" if pending else b"0"
            self._send(200, origin, body)
            return
        if method == "POST" and path == "/refresh":
            if self._read_body(origin) is None:
                return
            atomic_write(REFRESH, b"1\n")
            self._send(204, origin)
            return
        if method == "POST" and path == "/state":
            raw = self._read_body(origin)
            if raw is None:
                return
            try:
                data = json.loads(raw.decode("utf-8") or "{}")
            except (UnicodeDecodeError, json.JSONDecodeError):
                self._send(400, origin)
                return
            if not isinstance(data, dict):
                self._send(400, origin)
                return
            payload = (json.dumps(data, indent=2) + "\n").encode("utf-8")
            if len(payload) > MAX_BODY * 2:
                self._send(413, origin)
                return
            try:
                atomic_write(CHATS, payload)
            except OSError:
                self._send(500, origin)
                return
            self._send(204, origin)
            return
        self._send(404, origin)


if __name__ == "__main__":
    configure()
    take_pidfile()
    ReuseHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
