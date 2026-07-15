#!/usr/bin/env python3
"""Generate a macOS .icns icon file with a blue background and white delta symbol.

Usage:
    python tools/gen_icon.py                    # writes assets/Metanoia.icns
    python tools/gen_icon.py --size 1024         # custom base resolution
    python tools/gen_icon.py --color 0x1a6cf5    # custom background hex colour
"""

import argparse
import os
import struct
import subprocess
import sys
import tempfile
import zlib


def create_png(width: int, height: int, bg_color: int) -> bytes:
    """Create a PNG with a blue rounded-rect background and a white Greek capital delta."""

    def chunk(chunk_type: bytes, data: bytes) -> bytes:
        c = chunk_type + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)

    bg_r = (bg_color >> 16) & 0xFF
    bg_g = (bg_color >> 8) & 0xFF
    bg_b = bg_color & 0xFF

    header = b"\x89PNG\r\n\x1a\n"
    ihdr = chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))

    raw = b""
    radius = min(width, height) * 0.18  # rounded corner radius
    cx, cy = width / 2, height * 0.15   # triangle top point
    tri_x1, tri_y1 = cx, cy
    tri_x2, tri_y2 = cx - width * 0.3, height * 0.85
    tri_x3, tri_y3 = cx + width * 0.3, height * 0.85

    # Cutout rectangle (the crossbar of the delta)
    rect_top = int(height * 0.62)
    rect_bottom = int(height * 0.70)
    rect_left = int(cx - width * 0.17)
    rect_right = int(cx + width * 0.17)

    for y in range(height):
        raw += b"\x00"  # PNG filter byte
        for x in range(width):
            # Rounded rectangle test
            dx_r = min(x, width - x)
            dy_r = min(y, height - y)
            is_corner = dx_r <= radius and dy_r <= radius
            in_rounded_rect = True
            if is_corner:
                in_rounded_rect = (dx_r - radius) ** 2 + (dy_r - radius) ** 2 <= radius ** 2

            if not in_rounded_rect:
                raw += struct.pack("BBBB", 0, 0, 0, 0)  # transparent
                continue

            # Barycentric point-in-triangle test
            def _sign(px, py, ax, ay, bx, by):
                return (px - bx) * (ay - by) - (ax - bx) * (py - by)

            d1 = _sign(x, y, tri_x1, tri_y1, tri_x2, tri_y2)
            d2 = _sign(x, y, tri_x2, tri_y2, tri_x3, tri_y3)
            d3 = _sign(x, y, tri_x3, tri_y3, tri_x1, tri_y1)
            neg = (d1 < 0) or (d2 < 0) or (d3 < 0)
            pos = (d1 > 0) or (d2 > 0) or (d3 > 0)
            inside_tri = not (neg and pos)

            in_rect = rect_left <= x <= rect_right and rect_top <= y <= rect_bottom

            if inside_tri and not in_rect:
                raw += struct.pack("BBBB", 255, 255, 255, 255)  # white delta
            else:
                raw += struct.pack("BBBB", bg_r, bg_g, bg_b, 255)  # blue background

    idat = chunk(b"IDAT", zlib.compress(raw))
    iend = chunk(b"IEND", b"")
    return header + ihdr + idat + iend


def build_iconset(output_dir: str, size: int, color: int) -> str:
    """Build a .iconset directory from the generated PNG at multiple sizes."""
    iconset_dir = os.path.join(output_dir, "metanoia.iconset")
    os.makedirs(iconset_dir, exist_ok=True)

    for base_pt in (16, 32, 128, 256, 512):
        px = base_pt
        png = create_png(px, px, color)
        path = os.path.join(iconset_dir, f"icon_{base_pt}x{base_pt}.png")
        with open(path, "wb") as f:
            f.write(png)

    for base_pt, px in ((16, 32), (32, 64), (128, 256), (256, 512), (512, 1024)):
        png = create_png(px, px, color)
        path = os.path.join(iconset_dir, f"icon_{base_pt}x{base_pt}@2x.png")
        with open(path, "wb") as f:
            f.write(png)

    return iconset_dir


def main():
    parser = argparse.ArgumentParser(description="Generate macOS Metanoia .icns icon")
    parser.add_argument("--size", type=int, default=1024, help="Base resolution (default: 1024)")
    parser.add_argument("--color", type=lambda s: int(s, 16), default=0x1A6CF5, help="Background hex colour (default: 1A6CF5)")
    parser.add_argument("--output", default="assets/Metanoia.icns", help="Output .icns path")
    args = parser.parse_args()

    project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    output_dir = os.path.join(project_root, os.path.dirname(args.output))
    os.makedirs(output_dir, exist_ok=True)

    # Build iconset
    iconset_dir = build_iconset(output_dir, args.size, args.color)
    icns_path = os.path.join(project_root, args.output)

    # Convert to .icns using iconutil
    subprocess.run(
        ["iconutil", "-c", "icns", iconset_dir, "-o", icns_path],
        check=True,
        capture_output=True,
    )

    # Clean up iconset
    for f in os.listdir(iconset_dir):
        os.remove(os.path.join(iconset_dir, f))
    os.rmdir(iconset_dir)

    print(f"✅ Icon created: {icns_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
