#!/usr/bin/env python3
"""Sign an app-only release archive and its GitHub-hosted Sparkle feed."""
import argparse
from datetime import datetime, timezone
from email.utils import format_datetime
import hashlib
import os
from pathlib import Path
import plistlib
import subprocess
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[2]
DIST = Path(os.environ.get("GLINK_DIST_DIR", ROOT / "dist"))
SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--notes", required=True, type=Path, help="UTF-8 plain-text release notes")
    parser.add_argument("--repo", default="StevenGuo30/G-Link")
    args = parser.parse_args()
    info = plistlib.loads((DIST / "G-Link.app/Contents/Info.plist").read_bytes())
    version, build = info["CFBundleShortVersionString"], info["CFBundleVersion"]
    archive = DIST / f"G-Link-v{version}-update.zip"
    with zipfile.ZipFile(archive) as z:
        assert all(n.startswith("G-Link.app/") for n in z.namelist())
        assert not any(n.endswith(("config.json", ".qinglink", "维护手册.html")) for n in z.namelist())
        assert plistlib.loads(z.read("G-Link.app/Contents/Info.plist")) == info
    account = os.environ.get("GLINK_SIGNING_ACCOUNT", "G-Link")
    tools = ROOT / "gui/.build/sparkle/bin"
    public = subprocess.check_output([str(tools / "generate_keys"), "--account", account, "-p"], text=True).strip()
    if public != info["SUPublicEDKey"]:
        raise SystemExit("Signing key does not match the app's public key; refusing to publish")
    signer = [str(tools / "sign_update"), "--account", account]
    signature = subprocess.check_output(signer + ["-p", str(archive)], text=True).strip()
    url = f"https://github.com/{args.repo}/releases/download/v{version}/{archive.name}"
    rss = ET.Element("rss", version="2.0")
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = "G-Link"
    item = ET.SubElement(channel, "item")
    ET.SubElement(item, "title").text = f"G-Link {version}"
    ET.SubElement(item, "pubDate").text = format_datetime(datetime.now(timezone.utc))
    ET.SubElement(item, f"{{{SPARKLE}}}version").text = build
    ET.SubElement(item, f"{{{SPARKLE}}}shortVersionString").text = version
    ET.SubElement(item, f"{{{SPARKLE}}}minimumSystemVersion").text = info["LSMinimumSystemVersion"]
    ET.SubElement(item, "description").text = args.notes.read_text().strip()
    ET.SubElement(item, "enclosure", {
        "url": url, "length": str(archive.stat().st_size), "type": "application/octet-stream",
        f"{{{SPARKLE}}}edSignature": signature,
    })
    feed = DIST / "appcast.xml"
    ET.indent(rss)
    ET.ElementTree(rss).write(feed, encoding="utf-8", xml_declaration=True)
    subprocess.run(signer + [str(feed)], check=True)
    subprocess.run(signer + ["--verify", str(archive), signature], check=True)
    subprocess.run(signer + ["--verify", str(feed)], check=True)
    names = [archive, feed]
    public_zip = DIST / f"G-Link-v{version}-macOS.zip"
    if public_zip.exists():
        names.insert(0, public_zip)
    (DIST / f"SHA256SUMS-v{version}.txt").write_text("".join(
        f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n" for p in names))
    print(f"Signed update and feed ready: {feed}")


if __name__ == "__main__":
    main()
