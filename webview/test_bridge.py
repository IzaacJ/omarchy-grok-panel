#!/usr/bin/env python3
import json
import os
import stat
import tempfile
import threading
import unittest
from http.client import HTTPConnection
from pathlib import Path

import bridge


class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.state = root / "state"
        self.runtime = root / "run"
        self.state.mkdir()
        self.runtime.mkdir()
        self.token = "test-token-value-32bytes-minimum"
        bridge.configure(state_dir=self.state, runtime_dir=self.runtime, token=self.token)
        self.httpd = bridge.ReuseHTTPServer(("127.0.0.1", 0), bridge.Handler)
        self.port = self.httpd.server_address[1]
        self.thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.httpd.shutdown()
        self.httpd.server_close()
        self.tmp.cleanup()

    def request(self, method, path, body=b"", headers=None, include_auth=True, origin=None, host=None):
        conn = HTTPConnection("127.0.0.1", self.port, timeout=2)
        hdrs = {}
        if include_auth:
            hdrs["Authorization"] = "Bearer " + self.token
        if origin is not None:
            hdrs["Origin"] = origin
        if host is not None:
            hdrs["Host"] = host
        if headers:
            hdrs.update(headers)
        conn.request(method, path, body=body, headers=hdrs)
        res = conn.getresponse()
        data = res.read()
        got = {k.lower(): v for k, v in res.getheaders()}
        conn.close()
        return res.status, data, got

    def test_unauthenticated_post_is_rejected(self):
        status, _, _ = self.request(
            "POST",
            "/state",
            body=b'{"chats":[]}',
            include_auth=False,
            origin="https://evil.example",
        )
        self.assertEqual(status, 403)
        self.assertFalse((self.state / "chats.json").exists())

    def test_missing_token_is_unauthorized(self):
        status, _, _ = self.request("POST", "/state", body=b'{"chats":[]}', include_auth=False)
        self.assertEqual(status, 401)
        self.assertFalse((self.state / "chats.json").exists())

    def test_wrong_token_is_unauthorized(self):
        status, _, _ = self.request(
            "POST",
            "/state",
            body=b'{"chats":[]}',
            include_auth=False,
            headers={"Authorization": "Bearer wrong-token-value-32bytes-min"},
        )
        self.assertEqual(status, 401)

    def test_foreign_origin_is_forbidden(self):
        status, _, headers = self.request(
            "POST",
            "/state",
            body=b'{"chats":[]}',
            origin="https://evil.example",
        )
        self.assertEqual(status, 403)
        self.assertNotIn("access-control-allow-origin", headers)
        self.assertFalse((self.state / "chats.json").exists())

    def test_authenticated_grok_origin_writes_state(self):
        payload = {"chats": [{"url": "https://grok.com/chat/1", "title": "Hi"}]}
        status, _, headers = self.request(
            "POST",
            "/state",
            body=json.dumps(payload).encode(),
            origin="https://grok.com",
            headers={"Content-Type": "application/json"},
        )
        self.assertEqual(status, 204)
        self.assertEqual(headers.get("access-control-allow-origin"), "https://grok.com")
        self.assertNotEqual(headers.get("access-control-allow-origin"), "*")
        chats = json.loads((self.state / "chats.json").read_text(encoding="utf-8"))
        self.assertEqual(chats["chats"][0]["title"], "Hi")
        mode = stat.S_IMODE(os.stat(self.state / "chats.json").st_mode)
        self.assertEqual(mode, 0o600)

    def test_cors_preflight_allows_only_grok(self):
        status, _, headers = self.request(
            "OPTIONS",
            "/state",
            include_auth=False,
            origin="https://grok.com",
        )
        self.assertEqual(status, 204)
        self.assertEqual(headers.get("access-control-allow-origin"), "https://grok.com")
        self.assertEqual(headers.get("access-control-allow-private-network"), "true")
        self.assertIn("Authorization", headers.get("access-control-allow-headers", ""))

        status, _, headers = self.request(
            "OPTIONS",
            "/state",
            include_auth=False,
            origin="https://evil.example",
        )
        self.assertEqual(status, 403)
        self.assertNotIn("access-control-allow-origin", headers)

    def test_body_over_limit_is_rejected(self):
        status, _, _ = self.request(
            "POST",
            "/state",
            body=b"x" * (bridge.MAX_BODY + 1),
            headers={"Content-Type": "application/json"},
        )
        self.assertEqual(status, 413)
        self.assertFalse((self.state / "chats.json").exists())

    def test_unknown_path_does_not_write(self):
        status, _, _ = self.request("POST", "/anything", body=b'{"chats":[]}')
        self.assertEqual(status, 404)
        self.assertFalse((self.state / "chats.json").exists())

    def test_bad_host_is_forbidden(self):
        status, _, _ = self.request("GET", "/refresh", host="evil.example:18765")
        self.assertEqual(status, 403)

    def test_symlink_chats_is_rejected(self):
        victim = self.tmp.name + "/victim"
        with open(victim, "w", encoding="utf-8") as fh:
            fh.write("keep-me\n")
        os.symlink(victim, self.state / "chats.json")
        status, _, _ = self.request("POST", "/state", body=b'{"chats":[]}')
        self.assertEqual(status, 500)
        with open(victim, encoding="utf-8") as fh:
            self.assertEqual(fh.read(), "keep-me\n")

    def test_refresh_roundtrip(self):
        status, _, _ = self.request("POST", "/refresh", body=b"")
        self.assertEqual(status, 204)
        status, body, _ = self.request("GET", "/refresh")
        self.assertEqual(status, 200)
        self.assertEqual(body, b"1")
        status, body, _ = self.request("GET", "/refresh")
        self.assertEqual(status, 200)
        self.assertEqual(body, b"0")

    def test_refresh_symlink_is_ignored(self):
        victim = self.tmp.name + "/refresh-victim"
        with open(victim, "w", encoding="utf-8") as fh:
            fh.write("keep-me\n")
        os.symlink(victim, self.state / "refresh-requested")
        status, body, _ = self.request("GET", "/refresh")
        self.assertEqual(status, 200)
        self.assertEqual(body, b"0")
        self.assertTrue(os.path.islink(self.state / "refresh-requested"))
        with open(victim, encoding="utf-8") as fh:
            self.assertEqual(fh.read(), "keep-me\n")

    def test_token_file_is_regular_and_private(self):
        token_path = self.runtime / "omarchy-grok-panel.bridge.token"
        bridge.configure(state_dir=self.state, runtime_dir=self.runtime, token=None)
        st = os.lstat(token_path)
        self.assertTrue(stat.S_ISREG(st.st_mode))
        self.assertFalse(stat.S_ISLNK(st.st_mode))
        self.assertEqual(stat.S_IMODE(st.st_mode), 0o600)
        text = token_path.read_text(encoding="ascii").strip()
        self.assertGreaterEqual(len(text), 16)

    def test_non_object_json_is_rejected(self):
        status, _, _ = self.request("POST", "/state", body=b"[1,2,3]")
        self.assertEqual(status, 400)
        self.assertFalse((self.state / "chats.json").exists())


if __name__ == "__main__":
    unittest.main()
