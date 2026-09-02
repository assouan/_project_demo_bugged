from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


ROOT = Path(__file__).resolve().parent
FILES = {
    "/": ("index.html", "text/html; charset=utf-8"),
    "/index.html": ("index.html", "text/html; charset=utf-8"),
    "/script.js": ("script.js", "text/javascript; charset=utf-8"),
    "/styles.css": ("styles.css", "text/css; charset=utf-8"),
}


class Handler(BaseHTTPRequestHandler):
    server_version = "Journal/1.0"
    sys_version = ""

    def _headers(self, status, content_type, content_length):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(content_length))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Security-Policy", "default-src 'self' https://fonts.googleapis.com https://fonts.gstatic.com data:; script-src 'self'; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src https://fonts.gstatic.com; img-src 'self' data:; object-src 'none'; frame-ancestors 'none'; base-uri 'none'")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.end_headers()

    def _serve(self, include_body):
        if self.path == "/healthz":
            payload = b'{"status":"ok"}\n'
            self._headers(HTTPStatus.OK, "application/json; charset=utf-8", len(payload))
            if include_body:
                self.wfile.write(payload)
            return

        selected = FILES.get(self.path)
        if selected is None:
            payload = b"Not found\n"
            self._headers(HTTPStatus.NOT_FOUND, "text/plain; charset=utf-8", len(payload))
            if include_body:
                self.wfile.write(payload)
            return

        file_name, content_type = selected
        payload = (ROOT / file_name).read_bytes()
        self._headers(HTTPStatus.OK, content_type, len(payload))
        if include_body:
            self.wfile.write(payload)

    def do_GET(self):
        self._serve(True)

    def do_HEAD(self):
        self._serve(False)

    def do_POST(self):
        payload = b"Method not allowed\n"
        self._headers(HTTPStatus.METHOD_NOT_ALLOWED, "text/plain; charset=utf-8", len(payload))
        self.wfile.write(payload)

    def log_message(self, _format, *_args):
        return


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()

