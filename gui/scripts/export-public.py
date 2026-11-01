#!/usr/bin/env python3
"""显式白名单导出公开源码；禁止把私人仓库直接当公开仓库发布。"""
from pathlib import Path
import hashlib
import json
import os
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[2]
DIST = ROOT / "dist"


def allowed_files():
    names = [
        "LICENSE", "THIRD_PARTY_NOTICES.md", "gui/public.gitignore",
        "gui/Info.plist", "gui/README.md", "gui/先读我.txt", "gui/config.example.json",
        "gui/Sources/Core.swift", "gui/Sources/MacNetwork.swift", "gui/Sources/AppModel.swift",
        "gui/Sources/Views.swift", "gui/Sources/Main.swift", "gui/Sources/Cityscape.swift",
        "gui/scripts/build.sh", "gui/scripts/package.sh", "gui/scripts/icon.swift",
        "gui/scripts/export-public.py", "gui/scripts/cityscape.py", "gui/tests/artifacts.py", "gui/tests/engine.py",
        "docs/使用指南.html", "docs/assets/theme.css", "docs/assets/tutorial.js", "docs/assets/cityscape.svg",
        "docs/assets/setup.png", "docs/assets/connection-off.png", "docs/assets/connection-on.png", "docs/assets/recovery.png",
        "bin/sing-box-source-v1.13.8.tar.gz",
        "bin/SHA256SUMS", "bin/LICENSE-sing-box.txt", "bin/来源说明.md",
        "bin/darwin-arm64/sing-box", "bin/darwin-arm64/LICENSE",
        "bin/darwin-amd64/sing-box", "bin/darwin-amd64/LICENSE",
    ]
    return [ROOT / name for name in names]


def private_values():
    private = Path(os.environ.get("GLINK_PRIVATE_CONFIG", str(ROOT / "config/config.json")))
    if not private.exists():
        return set()
    cfg = json.loads(private.read_text())
    values = set()

    def walk(value):
        if isinstance(value, dict):
            for key, item in value.items():
                if key in {"server", "uuid", "password", "private_key", "public_key", "short_id"} and isinstance(item, str) and len(item) >= 8:
                    values.add(item.encode())
                walk(item)
        elif isinstance(value, list):
            for item in value:
                walk(item)

    walk(cfg.get("outbounds", []))
    return values


def main():
    files = allowed_files()
    secrets = private_values()
    for path in files:
        if not path.is_file() or path.is_symlink():
            raise SystemExit(f"缺失或不允许的链接：{path.relative_to(ROOT)}")
        data = path.read_bytes()
        if any(secret in data for secret in secrets):
            raise SystemExit(f"发现私人配置内容，导出已停止：{path.relative_to(ROOT)}")
        if str(Path.home()).encode() in data:
            raise SystemExit(f"发现本机用户路径，导出已停止：{path.relative_to(ROOT)}")
    DIST.mkdir(exist_ok=True)
    destination = DIST / "G-Link-公开源码.zip"
    with tempfile.NamedTemporaryFile(dir=DIST, suffix=".zip", delete=False) as temp:
        temporary = Path(temp.name)
    try:
        with zipfile.ZipFile(temporary, "w", zipfile.ZIP_DEFLATED) as archive:
            for path in files:
                archive.write(path, Path("g-link") / path.relative_to(ROOT))
            archive.writestr("g-link/README.md", (ROOT / "gui/README.md").read_text().replace("](../", "]("))
            archive.writestr("g-link/.gitignore", (ROOT / "gui/public.gitignore").read_bytes())
            manifest = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in files}
            archive.writestr("g-link/SOURCE-MANIFEST.json", json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
        os.chmod(temporary, 0o600)
        os.replace(temporary, destination)
    finally:
        temporary.unlink(missing_ok=True)
    print(f"已生成：{destination}")
    print("公开导出完成：白名单 + 私人节点值扫描通过。自有代码采用 MIT；第三方许可说明随包提供。")


if __name__ == "__main__":
    main()
