#!/usr/bin/env python3
import http.server
import json
import os
from pathlib import Path
import select
import shutil
import socket
import subprocess
import tempfile
import threading

root = Path(__file__).resolve().parents[2]
dist = Path(os.environ.get("GLINK_DIST_DIR", root / "dist"))


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


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


try:
    with tempfile.TemporaryDirectory(prefix="qinglink-native-") as temp:
        state = Path(temp) / "包含空格的 状态目录"
        target = f"http://127.0.0.1:{server.server_port}/"
        for locale in ("C", "en_US.UTF-8"):
            subprocess.run([
                str(dist / "G-Link.app/Contents/MacOS/G-Link"), "--engine-test",
                str(state), str(free_port()), target,
            ], env=dict(os.environ, LC_ALL=locale, LANG=locale), check=True, timeout=30)

        driver = Path(temp) / "engine-lifecycle"
        subprocess.run(["/usr/bin/xcrun", "swiftc", "-swift-version", "5",
                        str(root / "gui/Sources/Core.swift"), str(root / "gui/tests/EngineLifecycle.swift"),
                        "-o", str(driver)], check=True, timeout=60)
        helper = Path(temp) / "私人分享 文件夹/G-Link.app/Contents/Helpers/sing-box"
        helper.parent.mkdir(parents=True)
        shutil.copy2(dist / "G-Link.app/Contents/Helpers/sing-box", helper)
        env = dict(os.environ, LC_ALL="C", LANG="C")

        def run(mode, state, port, *args):
            return subprocess.run([str(driver), mode, str(state), str(helper), str(port), *args],
                                  env=env, check=True, timeout=30)

        for record in ("valid", "missing", "corrupt", "stale"):
            state = Path(temp) / ("中断启动 " + record)
            port = free_port()
            parent = subprocess.Popen([str(driver), "hold", str(state), str(helper), str(port)],
                                      env=env, stdout=subprocess.PIPE, text=True)
            try:
                assert select.select([parent.stdout], [], [], 15)[0], "测试引擎启动超时"
                line = parent.stdout.readline().strip()
                assert line.startswith("READY "), line
                pid = int(line.split()[1])
                # Force-quit the real engine owner; the child remains alive.
                parent.kill()
                parent.wait(timeout=5)
                os.kill(pid, 0)
                metadata = state / "engine.json"
                if record == "missing":
                    metadata.unlink()
                elif record == "corrupt":
                    metadata.write_text("{")
                elif record == "stale":
                    metadata.write_text(json.dumps({"pid": os.getpid(), "binary": str(helper)}))
                run("recover", state, port, str(pid), target)
                print(f"PASS: 强制退出父进程 + {record} 记录 + 中文路径/C locale")
            finally:
                if parent.poll() is None:
                    parent.kill()
                    parent.wait(timeout=5)
                parent.stdout.close()
                run("stop", state, port)

        # A live sing-box for a different configuration must remain untouched,
        # even when a stale/forged PID record points to it.
        foreign_state = Path(temp) / "其他配置"
        port = free_port()
        foreign = subprocess.Popen([str(driver), "hold", str(foreign_state), str(helper), str(port)],
                                   env=env, stdout=subprocess.PIPE, text=True)
        try:
            assert select.select([foreign.stdout], [], [], 15)[0]
            line = foreign.stdout.readline().strip()
            assert line.startswith("READY "), line
            pid = int(line.split()[1])
            isolated = Path(temp) / "待启动配置"
            isolated.mkdir()
            (isolated / "engine.json").write_text(json.dumps({"pid": pid, "binary": str(helper)}))
            run("reject", isolated, port)
            os.kill(pid, 0)
            result = subprocess.check_output(["/usr/bin/curl", "--noproxy", "", "--proxy",
                                              f"http://127.0.0.1:{port}", "-sS", "--max-time", "5", target])
            assert result == b"qinglink-ok"
            run("reject", isolated, server.server_port)
        finally:
            foreign.kill()
            foreign.wait(timeout=5)
            foreign.stdout.close()
            run("stop", foreign_state, port)
finally:
    server.shutdown()
    server.server_close()
