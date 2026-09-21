import importlib.util
import http.client
import os
import threading
import unittest
from http.server import ThreadingHTTPServer
from pathlib import Path


MODULE_PATH = Path(os.environ.get("MCP_TOKEN_AUTH_PATH", Path(__file__).with_name("server.py")))
SPEC = importlib.util.spec_from_file_location("mcp_token_auth", MODULE_PATH)
SERVER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SERVER)


class AuthorizationTest(unittest.TestCase):
    def test_accepts_matching_bearer_token(self):
        self.assertTrue(SERVER.is_authorized("Bearer secret", "secret"))

    def test_accepts_case_insensitive_scheme(self):
        self.assertTrue(SERVER.is_authorized("bearer secret", "secret"))

    def test_rejects_missing_header(self):
        self.assertFalse(SERVER.is_authorized(None, "secret"))

    def test_rejects_wrong_scheme(self):
        self.assertFalse(SERVER.is_authorized("Basic secret", "secret"))

    def test_rejects_wrong_token(self):
        self.assertFalse(SERVER.is_authorized("Bearer wrong", "secret"))


class HandlerTest(unittest.TestCase):
    def setUp(self):
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), SERVER.make_handler("secret"))
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()

    def request(self, path, authorization=None):
        connection = http.client.HTTPConnection(*self.server.server_address)
        headers = {"Authorization": authorization} if authorization else {}
        connection.request("GET", path, headers=headers)
        response = connection.getresponse()
        result = response.status, response.getheader("WWW-Authenticate")
        response.read()
        connection.close()
        return result

    def test_verify_accepts_token(self):
        self.assertEqual(self.request("/verify", "Bearer secret"), (200, None))

    def test_verify_challenges_invalid_token(self):
        self.assertEqual(self.request("/verify", "Bearer wrong"), (401, "Bearer"))

    def test_health_is_available(self):
        self.assertEqual(self.request("/healthz"), (200, None))


if __name__ == "__main__":
    unittest.main()
