#!/usr/bin/env python3
"""Generate the app icons without any binary asset in the repository.

Run: python3 iOSViewer/Scripts/make_app_icon.py <output-app-bundle>
Only the workflow writes the resulting PNGs into the unsigned app bundle.
"""
from __future__ import annotations

import math
import struct
import sys
import zlib
from pathlib import Path

SIZES: list[tuple[str, int]] = [
    ("AppIcon20x20.png", 20),
    ("AppIcon20x20@2x.png", 40),
    ("AppIcon20x20@3x.png", 60),
    ("AppIcon29x29.png", 29),
    ("AppIcon29x29@2x.png", 58),
    ("AppIcon29x29@3x.png", 87),
    ("AppIcon40x40.png", 40),
    ("AppIcon40x40@2x.png", 80),
    ("AppIcon40x40@3x.png", 120),
    ("AppIcon60x60@2x.png", 120),
    ("AppIcon60x60@3x.png", 180),
    ("AppIcon76x76.png", 76),
    ("AppIcon76x76@2x.png", 152),
    ("AppIcon83.5x83.5@2x.png", 167),
    ("AppIcon1024x1024.png", 1024),
]

START = (0.043, 0.106, 0.290)
END = (0.075, 0.663, 1.000)
WHITE = (1.0, 1.0, 1.0)


def clamp(value: float) -> float:
    return max(0.0, min(1.0, value))


def smoothstep(edge0: float, edge1: float, value: float) -> float:
    t = clamp((value - edge0) / (edge1 - edge0))
    return t * t * (3.0 - 2.0 * t)


def rounded_rect_alpha(x: float, y: float, radius: float) -> float:
    """Antialiased signed distance to a centred rounded square."""
    half = 0.5
    r = radius
    dx = abs(x - half) - (half - r)
    dy = abs(y - half) - (half - r)
    outside = math.hypot(max(dx, 0.0), max(dy, 0.0))
    distance = outside + min(max(dx, dy), 0.0) - r
    return 1.0 - smoothstep(-0.004, 0.004, distance)


def segment_distance(x: float, y: float, ax: float, ay: float,
                     bx: float, by: float) -> float:
    vx, vy = bx - ax, by - ay
    length_sq = vx * vx + vy * vy
    t = 0.0 if length_sq == 0 else clamp(((x - ax) * vx + (y - ay) * vy) / length_sq)
    return math.hypot(x - (ax + t * vx), y - (ay + t * vy))


def pixel(x: float, y: float) -> tuple[int, int, int, int]:
    alpha = rounded_rect_alpha(x, y, 0.235)
    if alpha <= 0.0:
        return (0, 0, 0, 0)

    gradient = clamp((x * 0.55 + (1.0 - y) * 0.45))
    blend = gradient * gradient * (3.0 - 2.0 * gradient)
    glow = math.exp(-((x - 0.72) ** 2 + (y - 0.18) ** 2) / 0.10) * 0.16
    rgb = [
        START[i] + (END[i] - START[i]) * blend + glow * WHITE[i]
        for i in range(3)
    ]

    stroke = 0.052
    v = min(
        segment_distance(x, y, 0.275, 0.300, 0.500, 0.735),
        segment_distance(x, y, 0.500, 0.735, 0.725, 0.300),
    )
    glyph = 1.0 - smoothstep(stroke - 0.010, stroke + 0.010, v)
    # A small dot above the V suggests a remote cursor/connection point.
    dot = 1.0 - smoothstep(0.045, 0.055, math.hypot(x - 0.725, y - 0.275))
    glyph = max(glyph, dot * 0.9)
    for i in range(3):
        rgb[i] = rgb[i] * (1.0 - glyph) + WHITE[i] * glyph

    return tuple(int(round(clamp(channel) * 255)) for channel in rgb) + (int(round(alpha * 255)),)


def png_chunk(tag: bytes, payload: bytes) -> bytes:
    return (
        struct.pack(">I", len(payload))
        + tag
        + payload
        + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)
    )


def render(size: int) -> bytes:
    raw = bytearray()
    for py in range(size):
        raw.append(0)  # PNG filter: None
        y = (py + 0.5) / size
        for px in range(size):
            raw.extend(pixel((px + 0.5) / size, y))
    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + png_chunk(b"IHDR", ihdr)
        + png_chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + png_chunk(b"IEND", b"")
    )


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: make_app_icon.py <output-app-bundle>", file=sys.stderr)
        return 2
    output = Path(sys.argv[1])
    output.mkdir(parents=True, exist_ok=True)
    for name, size in SIZES:
        (output / name).write_bytes(render(size))
    print(f"Generated {len(SIZES)} AppIcon PNGs in {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
