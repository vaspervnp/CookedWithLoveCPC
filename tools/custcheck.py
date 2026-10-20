#!/usr/bin/env python3
"""Check the still test customers (src/game/customer.asm) in a CPCEC shot
of a build with the camera at 0,0: every pixel of each figure (head + body +
legs parts from the cust_* sheets) must be on screen as expected. Sitting,
the figure is SIT_DROP lines lower, with the cust_sit legs in profile and
none facing down.

Usage: custcheck.py <shot.bmp>
"""
import sys

from PIL import Image

from cpc import fw_to_rgb, load_palette
from png2cpc import to_pens

TOP, LEFT = 22, 64
PARTS = (("head", 20), ("body", 14), ("legs", 14))
SIT_DROP = 4
# still customers: x, y, head, body, legs, frame (dir*3: down 0, right 6), sitting
STILL = ((100, 10, 0, 1, 2, 0, True), (30, 104, 2, 0, 1, 6, True))


def main():
    pens, _ = load_palette()
    rgb = [tuple(180 if c == 128 else c for c in fw_to_rgb(fw)) for fw, _ in pens]
    px = Image.open(sys.argv[1]).convert("RGB").load()
    sheets = {n: to_pens(Image.open(f"assets/sprites/cust_{n}.png").convert("RGBA"), False, sprite=True)
              for n in ("head", "body", "legs", "sit")}
    ok = True
    for x0, y0, *styles, f, sit in STILL:
        fig = []
        for (n, h), st in zip(PARTS, styles):
            if n == "legs" and sit:
                if f < 6:                       # facing down/up: no legs
                    fig += [[0] * 32 for y in range(h)]
                    continue
                n, c = "sit", (f - 6) // 3      # profile: right 0, left 1 (mirrored)
                rows = [sheets[n][st * h + y][0:32] for y in range(h)]
                fig += [r[::-1] if c else r for r in rows]
                continue
            fig += [sheets[n][st * h + y][f * 32:f * 32 + 32] for y in range(h)]
        if sit:
            y0 += SIT_DROP
        tot = sum(1 for r in fig for p in r if p)
        bad = sum(1 for y in range(48) for x in range(32)
                  if fig[y][x] and px[LEFT + (x0 + x) * 4 + 1, (TOP + 32 + y0 + y) * 2] != rgb[fig[y][x]])
        print(f"{'OK' if not bad else 'BAD'} {'sitting' if sit else 'standing'} customer at {x0},{y0}: {tot} pixels, {bad} wrong")
        ok &= not bad
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
