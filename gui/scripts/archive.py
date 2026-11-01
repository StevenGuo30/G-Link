#!/usr/bin/env python3
"""UTF-8 ZIP with executable modes and only internal Sparkle framework links."""
import os
from pathlib import Path
import stat
import sys
import zipfile


def archive(folder: Path, destination: Path):
    folder = folder.resolve()
    with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED) as output:
        for path in sorted(folder.rglob("*")):
            name = (Path(folder.name) / path.relative_to(folder)).as_posix()
            if path.is_symlink():
                target = os.readlink(path)
                if ("/Contents/Frameworks/Sparkle.framework/" not in name
                        or os.path.isabs(target) or not path.resolve(strict=True).is_relative_to(folder)):
                    raise ValueError("Archive contains an unexpected symlink")
                entry = zipfile.ZipInfo(name)
                entry.create_system = 3
                entry.external_attr = (stat.S_IFLNK | 0o777) << 16
                output.writestr(entry, target.encode("utf-8"))
            elif path.is_file():
                output.write(path, name)


if __name__ == "__main__":
    archive(Path(sys.argv[1]), Path(sys.argv[2]))
