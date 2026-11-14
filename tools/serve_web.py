#!/usr/bin/env python3
"""Serve build/web locally with headers Godot Web likes."""
from __future__ import annotations

import http.server
import socketserver
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "build" / "web"
PORT = 8000


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


if __name__ == "__main__":
    if not (ROOT / "index.html").exists():
        print("Build first: python tools/build_all.py --only Web")
        raise SystemExit(1)
    print(f"http://127.0.0.1:{PORT}/")
    with socketserver.TCPServer(("", PORT), Handler) as httpd:
        httpd.serve_forever()
