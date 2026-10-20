#!/usr/bin/env python3
"""Check the standing test customers (src/game/customer.asm) in a CPCEC shot
of a build with the camera at 0,0: every pixel of each figure (head + body +
legs parts from the cust_* sheets) must be on screen as expected.

Usage: custcheck.py <shot.bmp>
"""
import sys

from PIL import Image

from cpc import fw_to_rgb, load_palette
from png2cpc import to_pens

TOP, LEFT = 22, 64
PARTS = (("head", 20), ("body", 14), ("legs", 14))
# standing customers: x, y, head, body, legs, frame (dir*3: down 0, right 6)
STANDING = ((100, 10, 0, 1, 2, 0), (30, 104, 2, 0, 1, 6))


def main():
    pens, _ = load_palette()
    rgb = [tuple(180 if c == 128 else c for c in fw_to_rgb(fw)) for fw, _ in pens]
    px = Image.open(sys.argv[1]).convert("RGB").load()
    sheets = {n: to_pens(Image.open(f"assets/sprites/cust_{n}.png").convert("RGBA"), False, sprite=True)
              for n, _ in PARTS}
    ok = True
    for x0, y0, *styles, f in STANDING:
        fig = []
        for (n, h), st in zip(PARTS, styles):
            fig += [sheets[n][st * h + y][f * 32:f * 32 + 32] for y in range(h)]
        tot = sum(1 for r in fig for p in r if p)
        bad = sum(1 for y in range(48) for x in range(32)
                  if fig[y][x] and px[LEFT + (x0 + x) * 4 + 1, (TOP + 32 + y0 + y) * 2] != rgb[fig[y][x]])
        print(f"{'OK' if not bad else 'BAD'} customer at {x0},{y0}: {tot} pixels, {bad} wrong")
        ok &= not bad
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
