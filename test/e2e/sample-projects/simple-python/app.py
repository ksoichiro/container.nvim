#!/usr/bin/env python3
"""Simple Python app for E2E testing."""

import http.server
import socketserver
import os
from urllib.parse import urlparse


class SimpleHTTPRequestHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/':
            self.send_response(200)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'Hello from containerized Python app!\n')
        else:
            super().do_GET()


def main():
    port = int(os.environ.get('PORT', 5000))

    with socketserver.TCPServer(("", port), SimpleHTTPRequestHandler) as httpd:
        print(f"Server running at http://localhost:{port}/")
        httpd.serve_forever()


if __name__ == "__main__":
    main()
