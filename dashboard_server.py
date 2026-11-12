#!/usr/bin/env python3
"""Serve the local launcher preview dashboard at http://localhost:5069."""
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import os

ROOT = Path(__file__).resolve().parent
os.chdir(ROOT)

class Handler(SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path in ("/", "/index.html"):
            self.path = "/dashboard.html"
        return super().do_GET()

if __name__ == "__main__":
    print("Dashboard: http://localhost:5069")
    try:
        ThreadingHTTPServer(("127.0.0.1", 5069), Handler).serve_forever()
    except OSError as exc:
        raise SystemExit(f"Não foi possível iniciar o dashboard em 5069: {exc}")
