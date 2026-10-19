#!/usr/bin/env python3
"""Compare a Caprice32 screenshot of the M1 scroll test with the expected
playfield rendered from build/testtiles.bin + build/testmap.bin.

Usage: scrollcheck.py <shot.png> <sx> <sy> [--shift N]
  --shift N   : picture shift in Mode 0 pixels for R3 phase 1 (default +2)
  --hudshift N: HUD copy offset in bytes for phase 1 (default 1)
Prints OK or the number of mismatching pixels.
"""

import argparse
import os
import sys

from PIL import Image

from cpc import ROOT, fw_to_rgb, load_palette

BUILD = os.path.join(ROOT, "build")
TOP = 25            # first playfield line in the screenshot (CPC lines)
LEFT = 64           # screenshot x of the display start
PF_LINES = 168
MAP_W = 80


def decode(b):
    l = r = 0
    for bit, pos in ((0, 7), (1, 3), (2, 5), (3, 1)):
        if b & (1 << pos):
            l |= 1 << bit
        if b & (1 << (pos - 1)):
            r |= 1 << bit
    return l, r


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("shot")
    ap.add_argument("sx", type=int)
    ap.add_argument("sy", type=int, help="-1 = find it (for shots taken while scrolling)")
    ap.add_argument("--shift", type=int, default=2)
    ap.add_argument("--hudshift", type=int, default=1)
    ap.add_argument("--emu", choices=("caprice", "cpcec"), default="caprice",
                    help="screenshot geometry/colours of the emulator")
    args = ap.parse_args()

    tiles = open(os.path.join(BUILD, "testtiles.bin"), "rb").read()
    tmap = open(os.path.join(BUILD, "testmap.bin"), "rb").read()
    pens, _ = load_palette()
    global TOP
    mid = 127
    if args.emu == "cpcec":
        TOP, mid = 22, 180
    rgb = [tuple(mid if c == 128 else c for c in fw_to_rgb(fw)) for fw, _ in pens]

    def map_pen(x, y):
        t = tmap[(y // 8) * MAP_W + x // 8]
        b = tiles[t * 32 + (y % 8) * 4 + (x % 8) // 2]
        return decode(b)[x % 2]

    im = Image.open(args.shot).convert("RGB")
    if im.height % 2:
        sys.exit("odd screenshot height")
    px = im.load()
    cx, phase = (args.sx + 1) // 2, args.sx % 2
    d = args.shift if phase else 0
    if args.sy < 0:
        # find sy from the middle rows (columns sampled), then check everything
        best = None
        for sy in range(0, 505):
            bad = 0
            for line in range(16, 152, 5):
                for c in range(4, 156, 9):
                    if px[LEFT + (c + d) * 4 + 1, (TOP + line) * 2] != rgb[map_pen(4 * cx + c, sy + line)]:
                        bad += 1
                        break
                if bad:
                    break
            if not bad:
                best = sy
                break
        if best is None:
            print("BAD no matching sy")
            sys.exit(1)
        args.sy = best
        print(f"sy={best}", end=" ")
    bad = 0
    for line in range(PF_LINES):
        y = args.sy + line
        for c in range(160):
            sc = c + d                      # screen column of window column c
            if not 0 <= sc < 160:
                continue
            exp = rgb[map_pen(4 * cx + c, y)]  # window column c
            got = px[LEFT + sc * 4 + 1, (TOP + line) * 2]
            if got != exp:
                bad += 1
    # HUD: 4 rows right below the playfield, line 0 of each row black,
    # then black border down to the bottom of the screenshot.
    hud = open(os.path.join(BUILD, "testhud.bin"), "rb").read()
    hshift = (1 + (args.hudshift if phase else 0))
    hbad = 0
    for line in range(32):
        for c in range(160):
            sc = c + d
            if not 0 <= sc < 160:
                continue
            if line % 8 == 0:
                exp = (0, 0, 0)
            else:
                exp = rgb[decode(hud[hshift + c // 2])[c % 2]]
            if px[LEFT + sc * 4 + 1, (TOP + PF_LINES + line) * 2] != exp:
                hbad += 1
    for y in range((TOP + PF_LINES + 32) * 2, im.height, 2):
        for x in range(0, im.width, 4):
            if px[x, y] != (0, 0, 0):
                hbad += 1
    for y in range(0, (TOP - 1) * 2, 2):
        for x in range(0, im.width, 4):
            if px[x, y] != (0, 0, 0):
                hbad += 1
    bad += hbad
    print("OK" if bad == 0 else f"BAD {bad} (hud/border {hbad})")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
