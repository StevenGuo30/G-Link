#!/usr/bin/env python3
"""Real Sparkle installs against disposable apps and localhost; no system proxy changes."""
import functools
import http.server
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import shutil
import signal
import socket
import subprocess
import tempfile
import threading
import time
import uuid
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "gui/.build"
SPARKLE = BUILD / "sparkle"
NAMESPACE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", NAMESPACE)
spec = importlib.util.spec_from_file_location("archive", ROOT / "gui/scripts/archive.py")
archive_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(archive_module)


def run(args, **kwargs):
    return subprocess.run([str(x) for x in args], check=True, timeout=90, **kwargs)


class Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


def case(base, mode, public, key):
    root = base / mode
    root.mkdir()
    identifier = "local.glink.updatetest." + uuid.uuid4().hex
    web = root / "web"
    web.mkdir()
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(Handler, directory=str(web)))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    app = root / "installed/G-Link.app"
    (app / "Contents/MacOS").mkdir(parents=True)
    (app / "Contents/Helpers").mkdir()
    (app / "Contents/Frameworks").mkdir()
    shutil.copy2(BUILD / "update-harness", app / "Contents/MacOS/G-Link")
    shutil.copy2(ROOT / "bin/darwin-arm64/sing-box" if os.uname().machine == "arm64" else ROOT / "bin/darwin-amd64/sing-box", app / "Contents/Helpers/sing-box")
    shutil.copytree(SPARKLE / "Sparkle.framework", app / "Contents/Frameworks/Sparkle.framework", symlinks=True)
    info = {
        "CFBundleIdentifier": identifier, "CFBundleExecutable": "G-Link", "CFBundleName": "G-Link",
        "CFBundlePackageType": "APPL", "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0",
        "LSUIElement": True, "LSMinimumSystemVersion": "13.0", "SUPublicEDKey": public,
        "SUFeedURL": f"http://127.0.0.1:{server.server_port}/appcast.xml",
        "SUEnableAutomaticChecks": False, "SUAutomaticallyUpdate": False,
        "SUAllowsAutomaticUpdates": False, "SUEnableSystemProfiling": False,
        "SURequireSignedFeed": True, "SUVerifyUpdateBeforeExtraction": True,
        "NSAppTransportSecurity": {"NSAllowsLocalNetworking": True},
        "GLinkTestRoot": str(root), "GLinkTestMode": mode,
    }
    plist = app / "Contents/Info.plist"
    plist.write_bytes(plistlib.dumps(info))
    run(["/usr/bin/codesign", "--force", "--sign", "-", app], capture_output=True)
    updated = root / "new/G-Link.app"
    shutil.copytree(app, updated, symlinks=True)
    new_info = dict(info, CFBundleVersion="2", CFBundleShortVersionString="2.0")
    (updated / "Contents/Info.plist").write_bytes(plistlib.dumps(new_info))
    run(["/usr/bin/codesign", "--force", "--sign", "-", updated], capture_output=True)
    zip_path = web / "update.zip"
    archive_module.archive(updated, zip_path)
    signer = [SPARKLE / "bin/sign_update", "--ed-key-file", key]
    signature = subprocess.check_output([str(x) for x in signer + ["-p", zip_path]], text=True).strip()
    rss = ET.Element("rss", version="2.0")
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = "Local update fixture"
    item = ET.SubElement(channel, "item")
    ET.SubElement(item, "title").text = "Fixture update"
    ET.SubElement(item, f"{{{NAMESPACE}}}version").text = "1" if mode == "none" else "2"
    ET.SubElement(item, "description").text = "Fixture notes"
    ET.SubElement(item, "enclosure", {
        "url": f"http://127.0.0.1:{server.server_port}/update.zip", "type": "application/octet-stream",
        "length": str(zip_path.stat().st_size), f"{{{NAMESPACE}}}edSignature": signature,
    })
    feed = web / "appcast.xml"
    ET.ElementTree(rss).write(feed, encoding="utf-8", xml_declaration=True)
    run(signer + [feed], capture_output=True)
    if mode == "tamper-feed":
        feed.write_bytes(feed.read_bytes().replace(b"Fixture notes", b"Altered notes"))
    if mode == "tamper-package":
        content = bytearray(zip_path.read_bytes())
        content[len(content) // 2] ^= 1
        zip_path.write_bytes(content)
    state = root / "state"
    state.mkdir()
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    config = state / "config.json"
    config.write_text(json.dumps({
        "inbounds": [{"type": "mixed", "listen": "127.0.0.1", "listen_port": port}],
        "outbounds": [{"type": "socks", "tag": "unused", "server": "127.0.0.1", "server_port": 9}, {"type": "direct", "tag": "direct"}],
        "route": {"final": "direct"},
    }))
    original_config = config.read_bytes()
    if mode == "restore-failure":
        (state / "network-backup.plist").write_bytes(plistlib.dumps({"version": -1}))
    process = None
    try:
        with (root / "harness.log").open("wb") as log:
            # LaunchServices registration is needed for Sparkle to relaunch the
            # host exactly as it would when the user opens the app in Finder.
            process = subprocess.Popen(["/usr/bin/open", "-n", "-W", str(app)], stdout=log, stderr=log)
            deadline = time.monotonic() + 70
            while time.monotonic() < deadline:
                events = (root / "events.txt").read_text() if (root / "events.txt").exists() else ""
                if mode in ("success", "restore-failure"):
                    if "relaunched-2" in events:
                        break
                elif process.poll() is not None:
                    break
                if process.poll() not in (None, 0):
                    break
                time.sleep(0.1)
            else:
                raise AssertionError("Timed out; installed=" + str(plistlib.loads(plist.read_bytes())["CFBundleVersion"])
                                     + "; launcher=" + str(process.poll()) + ": " + events + "\n"
                                     + (root / "harness.log").read_text(errors="replace")[-4000:])
        events = (root / "events.txt").read_text()
        assert "ERROR-" not in events, events
        expected = {"none": "no-update", "cancel": "cancelled", "tamper-feed": "rejected",
                    "tamper-package": "rejected", "success": "relaunched-2", "restore-failure": "relaunched-2"}[mode]
        assert expected in events, events + (root / "harness.log").read_text(errors="replace")[-4000:]
        assert config.read_bytes() == original_config
        installed_version = plistlib.loads(plist.read_bytes())["CFBundleVersion"]
        assert installed_version == ("2" if mode in ("success", "restore-failure") else "1")
        if mode in ("success", "restore-failure"):
            assert events.index("engine-stopped-before-exit") < events.index("relaunched-2"), events
            assert "quit-waits-for-cleanup" in events
        if mode == "restore-failure":
            assert "restore-failure-blocked-quit" in events
        run(["/usr/bin/codesign", "--verify", "--deep", "--strict", app], capture_output=True)
        print("PASS: Sparkle " + mode + " (isolated app/config)", flush=True)
    finally:
        if process and process.poll() is None:
            process.kill()
            process.wait(timeout=5)
        # Clean only processes whose command contains this unique test root.
        rows = subprocess.check_output(["/bin/ps", "-ww", "-axo", "pid=,uid=,command="], text=True)
        for row in rows.splitlines():
            parts = row.split(None, 2)
            if len(parts) == 3 and parts[1] == str(os.getuid()) and parts[2].startswith("/") and str(root) in parts[2]:
                try:
                    os.kill(int(parts[0]), signal.SIGTERM)
                except ProcessLookupError:
                    pass
        server.shutdown()
        server.server_close()
        subprocess.run(["/usr/bin/defaults", "delete", identifier], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        shutil.rmtree(Path.home() / "Library/Caches" / identifier, ignore_errors=True)


def main():
    run(["/usr/bin/xcrun", "swiftc", "-swift-version", "5", "-O",
         *[ROOT / "gui/Sources" / name for name in ("Core.swift", "MacNetwork.swift", "AppModel.swift", "AppUpdates.swift")],
         ROOT / "gui/tests/UpdateHarness.swift", "-F", SPARKLE, "-framework", "Sparkle", "-framework", "AppKit",
         "-framework", "SwiftUI", "-framework", "SystemConfiguration", "-framework", "Security",
         "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks", "-o", BUILD / "update-harness"])
    # GUI fixtures must not store data in Desktop/Documents: a new bundle ID
    # would otherwise ask for unrelated macOS folder-access permission.
    with tempfile.TemporaryDirectory(prefix="glink-update-tests-") as temp:
        base = Path(temp)
        key = base / "fixture.key"
        public = subprocess.check_output([str(BUILD / "update-harness"), "--keygen", str(key)],
                                         env=dict(os.environ, DYLD_FRAMEWORK_PATH=str(SPARKLE)), text=True).strip()
        modes = os.environ.get("GLINK_UPDATE_TEST_CASES", "none,cancel,tamper-feed,tamper-package,success,restore-failure").split(",")
        for mode in modes:
            case(base, mode, public, key)


if __name__ == "__main__":
    main()
