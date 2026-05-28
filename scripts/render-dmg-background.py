#!/usr/bin/env python3
from __future__ import annotations

import math
import struct
import sys
import zlib
from pathlib import Path


WIDTH = 480
HEIGHT = 320
SCALE = 4

BACKGROUND = (248, 250, 252)
ARROW = (70, 87, 117, 220)
ARROW_SHADOW = (15, 23, 42, 34)
ARROW_HIGHLIGHT = (255, 255, 255, 72)


def blend(canvas: bytearray, x: int, y: int, color: tuple[int, int, int, int]) -> None:
    scaled_width = WIDTH * SCALE
    scaled_height = HEIGHT * SCALE

    if x < 0 or y < 0 or x >= scaled_width or y >= scaled_height:
        return

    red, green, blue, alpha = color
    opacity = alpha / 255
    offset = (y * scaled_width + x) * 3

    canvas[offset] = round((red * opacity) + (canvas[offset] * (1 - opacity)))
    canvas[offset + 1] = round((green * opacity) + (canvas[offset + 1] * (1 - opacity)))
    canvas[offset + 2] = round((blue * opacity) + (canvas[offset + 2] * (1 - opacity)))


def fill_rect(canvas: bytearray, left: float, top: float, right: float, bottom: float, color: tuple[int, int, int, int]) -> None:
    for y in range(math.floor(top * SCALE), math.ceil(bottom * SCALE)):
        for x in range(math.floor(left * SCALE), math.ceil(right * SCALE)):
            blend(canvas, x, y, color)


def fill_circle(canvas: bytearray, center_x: float, center_y: float, radius: float, color: tuple[int, int, int, int]) -> None:
    left = math.floor((center_x - radius) * SCALE)
    right = math.ceil((center_x + radius) * SCALE)
    top = math.floor((center_y - radius) * SCALE)
    bottom = math.ceil((center_y + radius) * SCALE)
    radius_squared = radius * radius

    for y in range(top, bottom):
        logical_y = (y + 0.5) / SCALE
        for x in range(left, right):
            logical_x = (x + 0.5) / SCALE
            if ((logical_x - center_x) ** 2) + ((logical_y - center_y) ** 2) <= radius_squared:
                blend(canvas, x, y, color)


def point_in_polygon(x: float, y: float, points: list[tuple[float, float]]) -> bool:
    inside = False
    previous_x, previous_y = points[-1]

    for current_x, current_y in points:
        crosses_y = (current_y > y) != (previous_y > y)
        if crosses_y:
            slope_x = (previous_x - current_x) * (y - current_y) / (previous_y - current_y) + current_x
            if x < slope_x:
                inside = not inside

        previous_x, previous_y = current_x, current_y

    return inside


def fill_polygon(canvas: bytearray, points: list[tuple[float, float]], color: tuple[int, int, int, int]) -> None:
    left = math.floor(min(point[0] for point in points) * SCALE)
    right = math.ceil(max(point[0] for point in points) * SCALE)
    top = math.floor(min(point[1] for point in points) * SCALE)
    bottom = math.ceil(max(point[1] for point in points) * SCALE)

    for y in range(top, bottom):
        logical_y = (y + 0.5) / SCALE
        for x in range(left, right):
            logical_x = (x + 0.5) / SCALE
            if point_in_polygon(logical_x, logical_y, points):
                blend(canvas, x, y, color)


def fill_arrow(canvas: bytearray, x1: float, y: float, x2: float, color: tuple[int, int, int, int]) -> None:
    shaft_width = 13
    head_height = 44
    shaft_end = x2 - 29

    fill_rect(canvas, x1, y - shaft_width / 2, shaft_end, y + shaft_width / 2, color)
    fill_circle(canvas, x1, y, shaft_width / 2, color)
    fill_polygon(
        canvas,
        [
            (shaft_end - 2, y - head_height / 2),
            (x2, y),
            (shaft_end - 2, y + head_height / 2),
        ],
        color,
    )


def downsample(canvas: bytearray) -> bytes:
    scaled_width = WIDTH * SCALE
    rows = []

    for y in range(HEIGHT):
        row = bytearray()
        for x in range(WIDTH):
            red = green = blue = 0

            for sample_y in range(SCALE):
                for sample_x in range(SCALE):
                    offset = (((y * SCALE + sample_y) * scaled_width) + (x * SCALE + sample_x)) * 3
                    red += canvas[offset]
                    green += canvas[offset + 1]
                    blue += canvas[offset + 2]

            samples = SCALE * SCALE
            row.extend((red // samples, green // samples, blue // samples))

        rows.append(b"\x00" + bytes(row))

    return b"".join(rows)


def png_chunk(kind: bytes, data: bytes) -> bytes:
    crc = zlib.crc32(kind)
    crc = zlib.crc32(data, crc)
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", crc & 0xFFFFFFFF)


def write_png(path: Path, pixels: bytes) -> None:
    header = struct.pack(">IIBBBBB", WIDTH, HEIGHT, 8, 2, 0, 0, 0)
    payload = b"".join(
        [
            b"\x89PNG\r\n\x1a\n",
            png_chunk(b"IHDR", header),
            png_chunk(b"IDAT", zlib.compress(pixels, 9)),
            png_chunk(b"IEND", b""),
        ]
    )
    path.write_bytes(payload)


def main() -> None:
    if len(sys.argv) != 2:
        print("usage: render-dmg-background.py <output.png>", file=sys.stderr)
        sys.exit(2)

    canvas = bytearray(BACKGROUND * (WIDTH * SCALE * HEIGHT * SCALE))
    fill_arrow(canvas, 204, 156, 292, ARROW_SHADOW)
    fill_arrow(canvas, 204, 152, 292, ARROW)
    fill_rect(canvas, 208, 146, 257, 150, ARROW_HIGHLIGHT)

    output_path = Path(sys.argv[1])
    output_path.parent.mkdir(parents=True, exist_ok=True)
    write_png(output_path, downsample(canvas))


if __name__ == "__main__":
    main()
