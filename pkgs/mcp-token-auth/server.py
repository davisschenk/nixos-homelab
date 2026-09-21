import argparse
import hmac
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


def is_authorized(header: str | None, token: str) -> bool:
    if header is None:
        return False
    scheme, separator, credential = header.partition(" ")
    return separator == " " and scheme.lower() == "bearer" and hmac.compare_digest(credential, token)


def make_handler(token: str):
    class TokenAuthHandler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path == "/healthz":
                self.send_response(200)
            elif self.path != "/verify":
                self.send_response(404)
            elif is_authorized(self.headers.get("Authorization"), token):
                self.send_response(200)
            else:
                self.send_response(401)
                self.send_header("WWW-Authenticate", "Bearer")
            self.send_header("Content-Length", "0")
            self.end_headers()

        def log_message(self, format, *args):
            return

    return TokenAuthHandler


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--listen", default="127.0.0.1")
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--token-file", type=Path, required=True)
    args = parser.parse_args()

    token = args.token_file.read_text().strip()
    if not token:
        raise SystemExit("token file is empty")

    server = ThreadingHTTPServer((args.listen, args.port), make_handler(token))
    server.serve_forever()


if __name__ == "__main__":
    main()
