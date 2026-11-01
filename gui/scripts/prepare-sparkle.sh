#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
(cd "$ROOT" && /usr/bin/shasum -a 256 -c bin/sparkle/SHA256SUMS)
mkdir -p "$ROOT/gui/.build/sparkle"
/usr/bin/tar -xJf "$ROOT/bin/sparkle/Sparkle-2.10.1.tar.xz" -C "$ROOT/gui/.build/sparkle"
/usr/bin/codesign --verify --deep --strict "$ROOT/gui/.build/sparkle/Sparkle.framework"
