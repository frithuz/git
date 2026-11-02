#!/usr/bin/env python3
"""Exercise the release key fetcher over HTTPS without production credentials."""

import http.server
import json
import os
from pathlib import Path
import ssl
import stat
import subprocess
import tempfile
import threading
import unittest
from urllib.parse import parse_qs, urlsplit


FETCH = Path(__file__).resolve().parents[1] / "scripts/apt/openbao.sh"
PRIVATE_KEY = "test private key\nwith multiple lines\n"


class OpenBaoTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory()
        cls.root = Path(cls.directory.name)
        cls.cert = cls.root / "cert.pem"
        key = cls.root / "key.pem"
        subprocess.run(
            [
                "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                "-keyout", str(key), "-out", str(cls.cert), "-days", "1",
                "-subj", "/CN=localhost", "-addext", "subjectAltName=DNS:localhost",
            ],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )

    @classmethod
    def tearDownClass(cls):
        cls.directory.cleanup()

    def setUp(self):
        self.failure = ""
        self.requests = []
        self.handler_errors = []
        test = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *_):
                pass

            def do_GET(self):
                self.respond()

            def do_POST(self):
                self.respond()

            def respond(self):
                path = urlsplit(self.path)
                test.requests.append((self.command, path.path))
                try:
                    if path.path == "/oidc":
                        test.assertEqual(self.command, "GET")
                        test.assertEqual(self.headers["Authorization"], "bearer request-token")
                        test.assertEqual(parse_qs(path.query), {
                            "request": ["1"], "audience": [test.address],
                        })
                        response = {} if test.failure == "oidc-missing" else {"value": "oidc-jwt"}
                    elif path.path == "/v1/auth/jwt-github/login":
                        test.assertEqual(self.command, "POST")
                        test.assertEqual(self.headers["X-Vault-Request"], "true")
                        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                        test.assertEqual(body, {"role": "git-release", "jwt": "oidc-jwt"})
                        if test.failure == "login-denied":
                            self.send_error(403)
                            return
                        response = {"auth": {"client_token": "bao-token"}}
                        if test.failure == "token-missing":
                            response = {"auth": {}}
                    elif path.path == "/v1/git/data/apt":
                        test.assertEqual(self.command, "GET")
                        test.assertEqual(self.headers["X-Vault-Token"], "bao-token")
                        test.assertEqual(self.headers["X-Vault-Request"], "true")
                        if test.failure == "secret-denied":
                            self.send_error(403)
                            return
                        value = {"private_key": PRIVATE_KEY}
                        if test.failure == "key-missing":
                            value = {}
                        elif test.failure == "key-wrong-type":
                            value = {"private_key": {"unexpected": "object"}}
                        response = {"data": {"data": value}}
                    else:
                        raise AssertionError(f"Unexpected path: {path.path}")
                    self.send_response(200)
                    self.end_headers()
                    self.wfile.write(json.dumps(response).encode())
                except Exception as error:
                    test.handler_errors.append(str(error))
                    self.send_error(500)

        self.server = http.server.ThreadingHTTPServer(("localhost", 0), Handler)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(self.cert, self.root / "key.pem")
        self.server.socket = context.wrap_socket(self.server.socket, server_side=True)
        self.address = f"https://localhost:{self.server.server_port}"
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.work = tempfile.TemporaryDirectory()
        self.addCleanup(self.work.cleanup)
        self.addCleanup(self.thread.join)
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)

    def fetch(self, overrides=None):
        output = Path(self.work.name) / "private-key.asc"
        temporary = Path(self.work.name) / "temporary"
        temporary.mkdir()
        env = {name: value for name, value in os.environ.items()
               if not name.startswith("OPENBAO_")}
        env.update({
            "OPENBAO_ADDR": self.address,
            "ACTIONS_ID_TOKEN_REQUEST_URL": self.address + "/oidc?request=1",
            "ACTIONS_ID_TOKEN_REQUEST_TOKEN": "request-token",
            "CURL_CA_BUNDLE": str(self.cert),
            "TMPDIR": str(temporary),
        })
        env.update(overrides or {})
        result = subprocess.run(["bash", str(FETCH), str(output)], env=env,
                                capture_output=True, text=True, timeout=15)
        self.assertEqual(self.handler_errors, [])
        self.assertEqual(list(temporary.iterdir()), [], "Temporary credentials were retained")
        self.assertEqual(result.stdout, "")
        for secret in (PRIVATE_KEY, "request-token", "oidc-jwt", "bao-token"):
            self.assertNotIn(secret, result.stderr)
        return result, output

    def test_fetch(self):
        result, output = self.fetch()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(output.read_text(), PRIVATE_KEY + "\n")
        self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o600)
        self.assertEqual(len(self.requests), 3)

    def test_failures_do_not_write_a_key(self):
        for failure, requests in (
            ("oidc-missing", 1), ("login-denied", 2), ("token-missing", 2),
            ("secret-denied", 3), ("key-missing", 3), ("key-wrong-type", 3),
        ):
            with self.subTest(failure=failure):
                self.failure = failure
                self.requests.clear()
                result, output = self.fetch()
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(output.exists())
                self.assertEqual(len(self.requests), requests)
                (Path(self.work.name) / "temporary").rmdir()

    def test_untrusted_tls_is_rejected(self):
        result, output = self.fetch({"CURL_CA_BUNDLE": ""})
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(output.exists())
        self.assertEqual(self.requests, [])


if __name__ == "__main__":
    unittest.main()
