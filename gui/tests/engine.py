#!/usr/bin/env python3
import http.server
from pathlib import Path
import socket
import subprocess
import tempfile
import threading

root = Path(__file__).resolve().parents[2]


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = b"qinglink-ok"
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    with tempfile.TemporaryDirectory(prefix="qinglink-native-") as temp:
        state = Path(temp) / "包含空格的 状态目录"
        subprocess.run([
            str(root / "dist/G-Link.app/Contents/MacOS/G-Link"), "--engine-test",
            str(state), str(port), f"http://127.0.0.1:{server.server_port}/",
        ], check=True, timeout=30)
finally:
    server.shutdown()
    server.server_close()
