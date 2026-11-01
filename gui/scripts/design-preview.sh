#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
SOURCE="$ROOT/dist/G-Link.app"
[[ -d "$SOURCE" ]] || { echo '请先执行 bash gui/scripts/build.sh'; exit 1; }
STAGE="$(mktemp -d "$ROOT/dist/.design-preview.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/G-Link 设计预览.app"
/usr/bin/ditto "$SOURCE" "$APP"
python3 - "$APP/Contents/Info.plist" <<'PY'
import plistlib, sys
from pathlib import Path
p = Path(sys.argv[1])
info = plistlib.loads(p.read_bytes())
info.update(CFBundleIdentifier='local.glink.design-preview', CFBundleName='G-Link 设计预览', CFBundleDisplayName='G-Link 设计预览', GLinkDesignPreview=True)
info.pop('CFBundleDocumentTypes', None)
info.pop('UTExportedTypeDeclarations', None)
p.write_bytes(plistlib.dumps(info))
PY
# A review-only app has no engine to launch, and never instantiates the network delegate.
rm -rf "$APP/Contents/Helpers"
/usr/bin/codesign --force --sign - "$APP"
/usr/bin/codesign --verify --deep --strict "$APP"
DESTINATION="$ROOT/dist/G-Link 设计预览.app"
if [[ -d "$DESTINATION" ]]; then mv "$DESTINATION" "$STAGE/previous.app"; fi
mv "$APP" "$DESTINATION"
printf '设计预览：%s\n' "$DESTINATION"
