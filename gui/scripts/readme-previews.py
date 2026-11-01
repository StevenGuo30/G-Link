#!/usr/bin/env python3
"""Render offline UI states and encode looping README demos (requires ffmpeg)."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
DIST = Path(os.environ.get("GLINK_DIST_DIR", ROOT / "dist"))
APP = DIST / "G-Link.app/Contents/MacOS/G-Link"
OUTPUT = ROOT / "docs/assets/demos"
FPS = 12


def animate(frames, destination, width, temporary):
    # Return to the first frame before the loop restarts, avoiding a hard cut.
    frames = [*frames, frames[0]]
    hold, fade = 2.2, 0.6
    args = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y"]
    filters = []
    for i, frame in enumerate(frames):
        args += ["-loop", "1", "-framerate", str(FPS), "-t", str(hold + fade), "-i", str(frame)]
        filters.append(f"[{i}:v]scale={width}:-1:flags=lanczos,format=rgb24,setpts=PTS-STARTPTS,fps={FPS}[v{i}]")
    previous = "v0"
    for i in range(1, len(frames)):
        name = f"blend{i}"
        filters.append(f"[{previous}][v{i}]xfade=transition=fade:duration={fade}:offset={i * hold},fps={FPS}[{name}]")
        previous = name
    duration = (len(frames) - 1) * hold + fade
    filters += [
        f"[{previous}]trim=duration={duration},fps={FPS},split[frames][colors]",
        "[colors]palettegen=max_colors=256:stats_mode=full[palette]",
        "[frames][palette]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle[out]",
    ]
    staged = temporary / destination.name
    subprocess.run(args + ["-filter_complex_threads", "1", "-filter_complex", ";".join(filters),
                           "-map", "[out]", "-an", "-loop", "0", str(staged)], check=True)
    if staged.stat().st_size > 5_000_000:
        raise SystemExit(f"Preview exceeds 5 MB: {destination.name}")
    os.replace(staged, destination)
    print(f"Created {destination.relative_to(ROOT)} ({destination.stat().st_size / 1_000_000:.2f} MB)", flush=True)


def main():
    if not APP.is_file():
        raise SystemExit("Build G-Link first: bash gui/scripts/build.sh")
    if not shutil.which("ffmpeg"):
        raise SystemExit("ffmpeg is needed only to regenerate README animations.")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="glink-readme-", dir=DIST) as tmp:
        temporary = Path(tmp)
        cities = []
        # Shanghai → Shenzhen → New York → Chicago. These are preview models;
        # rendering does not read personal config or enable any system proxy.
        for city in (1, 0, 2, 3):
            directory = temporary / str(city)
            subprocess.run([str(APP), "--render-previews", str(directory), "--preview-city", str(city)], check=True)
            cities.append(directory)
        animate([cities[0] / "connection-off.png", cities[0] / "connection-on.png"],
                OUTPUT / "connection.gif", 880, temporary)
        for state in ("off", "on"):
            animate([city / f"connection-{state}.png" for city in cities],
                    OUTPUT / f"cities-{state}.gif", 704, temporary)


if __name__ == "__main__":
    main()
