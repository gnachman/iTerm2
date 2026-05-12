#!/usr/bin/env python3
"""Scale the artwork inside an .icns file by SCALE (default 0.8) while
keeping every iconset slot's canvas dimensions identical. Used to make
the MomenTerm dock icon appear visibly smaller next to neighboring macOS
apps in the Dock / Cmd+Tab switcher / Finder.

Usage:
    tools/resize_app_icon.py <input.icns> <output.icns> [scale]

Workflow:
    1. iconutil --convert iconset <input.icns>  -> temp iconset
    2. for each slot PNG: resize artwork to (w*scale, h*scale),
       paste centered on a fully transparent canvas of original (w, h).
    3. iconutil --convert icns temp.iconset      -> <output.icns>

Requires Pillow. Run from any directory; absolute paths recommended.
"""
import os
import shutil
import subprocess
import sys
import tempfile

from PIL import Image


def rescale_iconset(src_dir: str, dst_dir: str, scale: float) -> None:
    os.makedirs(dst_dir, exist_ok=True)
    for name in sorted(os.listdir(src_dir)):
        if not name.endswith(".png"):
            continue
        img = Image.open(os.path.join(src_dir, name)).convert("RGBA")
        w, h = img.size
        nw, nh = max(1, round(w * scale)), max(1, round(h * scale))
        small = img.resize((nw, nh), Image.LANCZOS)
        canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        ox, oy = (w - nw) // 2, (h - nh) // 2
        canvas.paste(small, (ox, oy), small)
        canvas.save(os.path.join(dst_dir, name), "PNG", optimize=True)


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    src_icns = os.path.abspath(sys.argv[1])
    dst_icns = os.path.abspath(sys.argv[2])
    scale = float(sys.argv[3]) if len(sys.argv) > 3 else 0.8

    with tempfile.TemporaryDirectory() as tmp:
        src_set = os.path.join(tmp, "src.iconset")
        dst_set = os.path.join(tmp, "dst.iconset")
        subprocess.check_call(["iconutil", "--convert", "iconset", src_icns, "-o", src_set])
        rescale_iconset(src_set, dst_set, scale)
        subprocess.check_call(["iconutil", "--convert", "icns", dst_set, "-o", dst_icns])

    print(f"wrote {dst_icns} (scale={scale})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
