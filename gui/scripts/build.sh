#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
BUILD="$ROOT/gui/.build"
DIST="$ROOT/dist"
mkdir -p "$BUILD" "$DIST"
[[ "$(uname -s)" == Darwin ]] || { echo '需要在 Mac 上构建。' >&2; exit 1; }
/usr/bin/xcrun --find swiftc >/dev/null
(cd "$ROOT" && /usr/bin/shasum -a 256 -c bin/SHA256SUMS)
stage="$(mktemp -d "$DIST/.qinglink-build.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
APP="$stage/G-Link.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources/docs/assets"
for arch in arm64 x86_64; do
  printf '正在编译 %s…\n' "$arch"
  /usr/bin/xcrun swiftc -swift-version 5 -target "$arch-apple-macos13.0" -O \
    "$ROOT"/gui/Sources/*.swift -o "$BUILD/QingLink-$arch" \
    -framework SwiftUI -framework AppKit -framework SystemConfiguration -framework Security
done
/usr/bin/lipo -create "$BUILD/QingLink-arm64" "$BUILD/QingLink-x86_64" -output "$APP/Contents/MacOS/G-Link"
/usr/bin/lipo -create "$ROOT/bin/darwin-arm64/sing-box" "$ROOT/bin/darwin-amd64/sing-box" -output "$APP/Contents/Helpers/sing-box"
# 新建通用二进制后重新做本地签名；不修改原始随包文件和校验值。
/usr/bin/codesign --force --sign - "$APP/Contents/Helpers/sing-box"
cp "$ROOT/gui/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE-G-Link.txt"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp "$ROOT/bin/sing-box-source-v1.13.8.tar.gz" "$APP/Contents/Resources/sing-box-source-v1.13.8.tar.gz"
cp "$ROOT/bin/LICENSE-sing-box.txt" "$APP/Contents/Resources/LICENSE-sing-box.txt"
cp "$ROOT/bin/来源说明.md" "$APP/Contents/Resources/SING-BOX-SOURCE.md"
"$APP/Contents/MacOS/G-Link" --self-test
/usr/bin/ditto "$ROOT/docs/assets/cities" "$APP/Contents/Resources/docs/assets/cities"
"$APP/Contents/MacOS/G-Link" --render-previews "$ROOT/docs/assets"
cp "$ROOT/docs/使用指南.html" "$APP/Contents/Resources/docs/使用指南.html"
cp "$ROOT/docs/assets/"*.css "$ROOT/docs/assets/"*.js "$ROOT/docs/assets/"*.png "$APP/Contents/Resources/docs/assets/"
/usr/bin/xcrun swift "$ROOT/gui/scripts/icon.swift" "$BUILD"
/usr/bin/iconutil -c icns "$BUILD/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
/usr/bin/codesign --force --sign - "$APP"
/usr/bin/codesign --verify --deep --strict "$APP"
# 只替换此构建脚本产生的具名产物。
if [[ -d "$DIST/G-Link.app" ]]; then
  /usr/bin/ditto "$DIST/G-Link.app" "$stage/previous.app"
  rm -rf "$DIST/G-Link.app"
fi
mv "$APP" "$DIST/G-Link.app"
printf '\n构建完成：%s\n本地 ad-hoc 签名；未进行 Apple Developer ID 公证。\n' "$DIST/G-Link.app"
