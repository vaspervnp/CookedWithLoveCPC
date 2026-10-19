#!/usr/bin/env python3
"""Check a CPCEC/Caprice32 screenshot of a DBGPOS build (sprites on the map).

Reads the debug band (HUD line 0: sx, sy, sprite left/top, frame), renders the
expected playfield (map + the sprite frame, pen 0 transparent, clipped to the
view) and compares it pixel by pixel. Also checks that the sprite's feet box
is not inside a solid tile.

Usage: gamecheck.py <shot> [--emu cpcec|caprice] [--sheet assets/sprites/bill.png]
Prints a one-line result: OK sx=.. sy=.. x=.. y=.. f=..  or  BAD ...
"""

import argparse
import os
import sys

from PIL import Image

from cpc import ROOT, fw_to_rgb, load_palette
from png2cpc import to_pens
from scrollcheck import decode

BUILD = os.path.join(ROOT, "build")
LEFT = 64
MAP_W = 80
SOLID_FIRST = 48


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("shot")
    ap.add_argument("--emu", choices=("caprice", "cpcec"), default="cpcec")
    ap.add_argument("--sheet", default=os.path.join(ROOT, "assets", "sprites", "bill.png"))
    ap.add_argument("--mirror-from", type=int, default=10)
    args = ap.parse_args()
    top, mid = (22, 180) if args.emu == "cpcec" else (25, 127)

    pens, _ = load_palette()
    rgb = [tuple(mid if c == 128 else c for c in fw_to_rgb(fw)) for fw, _ in pens]
    tiles = open(os.path.join(BUILD, "testtiles.bin"), "rb").read()
    tmap = open(os.path.join(BUILD, "testmap.bin"), "rb").read()

    sheet = to_pens(Image.open(args.sheet).convert("RGBA"), False, sprite=True)
    frames = []
    for fy in range(len(sheet) // 48):
        for fx in range(len(sheet[0]) // 32):
            frames.append([row[fx * 32:(fx + 1) * 32] for row in sheet[fy * 48:(fy + 1) * 48]])
    frames += [[list(reversed(r)) for r in f] for f in frames[args.mirror_from:]]

    im = Image.open(args.shot).convert("RGB")
    px = im.load()

    # debug band
    # (R3 phase 1 shows the whole picture one byte to the right: odd sx)
    for shift in (1, 0):
        bits = []
        for i in range(80):
            v = px[LEFT + (i + shift) * 8 + 1, top * 2]
            bits.append(1 if v != (0, 0, 0) else 0)

        def field(a, n):
            return int("".join(map(str, bits[a:a + n])), 2)

        sx, sy, sxl, sty, fr = field(0, 8), field(8, 16), field(24, 16), field(40, 16), field(56, 8)
        prof = [field(64 + 4 * k, 4) for k in range(4)]
        if sx % 2 == shift:   # odd sx read at +1 byte, else even at 0
            break
    if sx > 240 or sy > 504 or fr >= len(frames):
        print(f"BAD band sx={sx} sy={sy} f={fr}")
        sys.exit(1)

    cx, phase = (sx + 1) // 2, sx % 2
    d = 2 if phase else 0

    def map_pen(x, y):
        t = tmap[(y // 8) * MAP_W + x // 8]
        return decode(tiles[t * 32 + (y % 8) * 4 + (x % 8) // 2])[x % 2]

    frame = frames[fr]
    bad = 0
    where = []
    for line in range(168):
        y = sy + line
        for c in range(160):
            sc = c + d
            if not 0 <= sc < 160:
                continue
            x = 4 * cx + c
            pen = map_pen(x, y)
            fx, fy = x - sxl, y - sty
            if 0 <= fx < 32 and 0 <= fy < 48 and frame[fy][fx]:
                pen = frame[fy][fx]
            if px[LEFT + sc * 4 + 1, (top + 32 + line) * 2] != rgb[pen]:
                bad += 1
                if len(where) < 3:
                    where.append((c, line))

    # feet box must be free
    fx, fy = sxl + 16, sty + 47
    for ox, oy in ((-6, -5), (5, -5), (-6, 0), (5, 0)):
        tx, ty = (fx + ox) // 8, (fy + oy) // 8
        if tmap[ty * MAP_W + tx] >= SOLID_FIRST:
            print(f"BAD feet in solid tile at {tx},{ty}")
            sys.exit(1)

    info = f"sx={sx} sy={sy} x={sxl} y={sty} f={fr} prof={prof}"
    if bad:
        print(f"BAD {bad} {info} first {where}")
        sys.exit(1)
    print(f"OK {info}")


if __name__ == "__main__":
    main()
