#!/usr/bin/env python3
"""验证构建产物和公开/私人归档；不改动系统网络设置。"""
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import zipfile

root = Path(__file__).resolve().parents[2]
dist = Path(os.environ.get("GLINK_DIST_DIR", root / "dist"))
app = dist / "G-Link.app"
subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)], check=True)
for name in ("MacOS/G-Link", "Helpers/sing-box"):
    architectures = subprocess.check_output(["/usr/bin/lipo", "-archs", str(app / "Contents" / name)], text=True)
    assert "arm64" in architectures and "x86_64" in architectures
    assert str(Path.home()).encode() not in (app / "Contents" / name).read_bytes(), "应用不得泄露本机用户路径"
info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
assert info["LSMinimumSystemVersion"] == "13.0"
subprocess.run([str(app / "Contents/MacOS/G-Link"), "--self-test"], check=True)
assert not list(app.rglob("*.qinglink"))
assert not list(app.rglob("config.json"))
assert not list(app.rglob("维护手册.html"))
assert (app / "Contents/Resources/docs/assets/connection-on.png").stat().st_size > 10000
for city in ("shenzhen", "shanghai", "new-york", "chicago"):
    asset = app / "Contents/Resources/docs/assets/cities" / (city + ".png")
    data = asset.read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n" and data[25] == 6, "建筑素材应为 RGBA PNG"
print("PASS：通用架构、本地签名、应用不含私人配置、教程素材存在")

spec = importlib.util.spec_from_file_location("exporter", root / "gui/scripts/export-public.py")
exporter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(exporter)
secrets = exporter.private_values()
for name in ("G-Link-公开应用.zip", "G-Link-公开源码.zip"):
    with zipfile.ZipFile(dist / name) as archive:
        for item in archive.infolist():
            assert "维护手册" not in item.filename and "/private/" not in item.filename
            assert not item.filename.endswith(".qinglink")
            data = archive.read(item)
            assert not any(secret in data for secret in secrets), f"私人内容泄漏：{item.filename}"
    print(f"PASS：{name} 不含私人节点与个人手册")

private = dist / "G-Link-私人分享.zip"
if private.exists():
    with zipfile.ZipFile(private) as archive:
        configurations = [n for n in archive.namelist() if n.endswith("/连接配置.qinglink") and not n.startswith("__MACOSX/")]
        assert len(configurations) == 1
        cfg = json.loads(archive.read(configurations[0]))
        source_config = Path(os.environ.get("GLINK_PRIVATE_CONFIG", str(root / "config/config.json")))
        assert source_config.is_file(), "验证私人包需要原配置；请设置 GLINK_PRIVATE_CONFIG"
        assert cfg == json.loads(source_config.read_text())
        assert not any("维护手册" in n for n in archive.namelist())
    print("PASS：私人分享包携带匹配的配置，不携带个人维护手册")

# macOS 解压后保留签名和可执行权限。
with tempfile.TemporaryDirectory(prefix="qinglink-unzip-") as temporary:
    subprocess.run(["/usr/bin/ditto", "-x", "-k", str(dist / "G-Link-公开应用.zip"), temporary], check=True)
    unpacked = Path(temporary) / "G-Link/G-Link.app"
    subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(unpacked)], check=True)
    subprocess.run([str(unpacked / "Contents/MacOS/G-Link"), "--self-test"], check=True, stdout=subprocess.DEVNULL)
print("PASS：ZIP 解压后签名与执行权限有效")
