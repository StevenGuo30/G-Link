#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
mode="${1:-public}"
case "$mode" in public|private) ;; *) echo '用法：package.sh public|private' >&2; exit 2;; esac
DIST="${GLINK_DIST_DIR:-$ROOT/dist}"
APP="$DIST/G-Link.app"
[[ -d "$APP" ]] || { echo '请先运行 bash gui/scripts/build.sh' >&2; exit 1; }
/usr/bin/codesign --verify --deep --strict "$APP"
stage="$(mktemp -d "$DIST/.qinglink-package.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
folder="$stage/G-Link"
mkdir -p "$folder"
/usr/bin/ditto "$APP" "$folder/G-Link.app"
/usr/bin/ditto "$ROOT/docs" "$folder/教程"
cp "$ROOT/gui/先读我.txt" "$folder/先读我.txt"
if [[ "$mode" == private ]]; then
  PRIVATE_CONFIG="${GLINK_PRIVATE_CONFIG:-$ROOT/config/config.json}"
  [[ -f "$PRIVATE_CONFIG" ]] || { echo '缺少私人连接配置；可设置 GLINK_PRIVATE_CONFIG 指向本地文件' >&2; exit 1; }
  "$APP/Contents/Helpers/sing-box" check -c "$PRIVATE_CONFIG"
  cp "$PRIVATE_CONFIG" "$folder/连接配置.qinglink"
  chmod 600 "$folder/连接配置.qinglink"
  name=G-Link-私人分享.zip
else
  name=G-Link-公开应用.zip
fi
# zipfile 为中文路径写入 UTF-8 标记，避免 ditto ZIP 被跨平台工具读成乱码。
python3 - "$folder" "$stage/$name" <<'PY'
from pathlib import Path
import sys, zipfile
folder, destination = map(Path, sys.argv[1:])
with zipfile.ZipFile(destination, 'w', zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(folder.rglob('*')):
        if path.is_symlink():
            raise SystemExit('不允许在应用包中意外引入符号链接')
        if path.is_file():
            archive.write(path, Path(folder.name) / path.relative_to(folder))
PY
chmod 600 "$stage/$name"
mv -f "$stage/$name" "$DIST/$name"
printf '已生成：%s\n' "$DIST/$name"
if [[ "$mode" == private ]]; then printf '含真实连接配置，仅私下分享；不含私人维护手册。\n'; fi
