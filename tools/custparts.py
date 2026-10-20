#!/usr/bin/env python3
"""Customer part sheets (head / body / legs) from the customer renders
(assets/blender/customer_build.py).

Each style of a part was rendered on its own; it goes through the
render2sprite conversion (material per pixel, palette ramps, face features,
outline) with the colours of that style, and its band is cut out: head lines
0-19, body 20-33, legs 34-47. Output sheets have one row per style and 9
frames per row (down, up, right x idle, walk 1, walk 2), the layout
tools/spritec.py expects (GROUP 9, MIRROR_FROM 6). Any head combines with any
body and legs.

Usage: custparts.py <render dir> <out dir> [--preview out.png]
"""

import argparse
import json
import os

from PIL import Image

import render2sprite as r2s
from cpc import fw_to_rgb, load_palette

SPLIT = {"head": (0, 20), "body": (20, 34), "legs": (34, 48)}
DIRS = ("down", "up", "right")
POSES = 3

# materials of the renders (same order as MATS in customer_build.py)
MATS = ["hair", "skin", "top", "trim", "bottom", "shoes", "eyes", "mouth",
        "brows", "beard"]
PRIORITY = {"trim": 3, "mouth": 3, "beard": 3}
SKIN = [5, 6, 6, 6]

# colour ramps (pens dark -> light) per style
STYLES = {
    "head": [
        {"hair": [14, 14, 14, 1]},                            # short dark hair
        {"hair": [5, 15, 15, 8, 8], "mouth": [3]},            # blonde bob, lips
        {"hair": [12, 12, 13], "beard": [12, 13]},            # bald, grey, moustache
    ],
    "body": [
        {"top": [9, 9, 10], "trim": [10]},                    # green t-shirt
        {"top": [2, 11, 11], "trim": [12, 13]},               # blue shirt, white collar
        {"top": [3, 4, 4], "trim": [14]},                     # red blouse, belt
    ],
    "legs": [
        {"bottom": [1, 2, 2], "shoes": [14, 14, 12]},         # jeans
        {"bottom": [15, 8, 8], "shoes": [3, 4]},              # yellow skirt
        {"bottom": [14, 14, 1], "trim": [1], "shoes": [5]},   # dark trousers
    ],
}


def convert(renders, feats, part, style, d, i):
    tag = f"{part}{style}_{d}{i}"
    idi = Image.open(os.path.join(renders, f"id_{tag}.png")).convert("RGBA")
    shi = Image.open(os.path.join(renders, f"shade_{tag}.png")).convert("RGBA")
    saved = (r2s.MATS, dict(r2s.RAMP), dict(r2s.PRIORITY))
    r2s.MATS = MATS
    r2s.RAMP.clear()
    r2s.RAMP.update({m: [14] for m in MATS})
    r2s.RAMP["skin"] = SKIN
    r2s.RAMP.update(STYLES[part][style])
    r2s.PRIORITY.clear()
    r2s.PRIORITY.update(PRIORITY)
    try:
        px = r2s.convert(idi, shi)
        if part == "head":
            r2s.draw_face(px, feats[tag], d == "right")
        return r2s.outline(px)
    finally:
        r2s.MATS = saved[0]
        r2s.RAMP.clear()
        r2s.RAMP.update(saved[1])
        r2s.PRIORITY.clear()
        r2s.PRIORITY.update(saved[2])


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("renders")
    ap.add_argument("out")
    ap.add_argument("--preview")
    args = ap.parse_args()

    pens, _ = load_palette()
    rgb = [fw_to_rgb(fw) for fw, _ in pens]
    feats = json.load(open(os.path.join(args.renders, "features.json")))
    sheets = {}
    for part, (y0, y1) in SPLIT.items():
        n = len(STYLES[part])
        sheet = Image.new("RGBA", (32 * POSES * len(DIRS), (y1 - y0) * n), (0, 0, 0, 0))
        for st in range(n):
            col = 0
            for d in DIRS:
                for i in range(POSES):
                    px = convert(args.renders, feats, part, st, d, i)
                    for y in range(y0, y1):
                        for x in range(32):
                            if px[y][x]:
                                sheet.putpixel((col * 32 + x, st * (y1 - y0) + y - y0), rgb[px[y][x]] + (255,))
                    col += 1
        sheet.save(os.path.join(args.out, f"cust_{part}.png"))
        sheets[part] = sheet
    if args.preview:
        # all 27 combinations, standing facing down, and a walking row
        combos = [(h, b, l) for h in range(3) for b in range(3) for l in range(3)]
        im = Image.new("RGBA", (34 * 14, 50 * 2), (60, 60, 70, 255))
        for c, idx in enumerate(combos[:14]):
            for (part, (y0, y1)), st in zip(SPLIT.items(), idx):
                band = sheets[part].crop((0, st * (y1 - y0), 32, (st + 1) * (y1 - y0)))
                im.alpha_composite(band, (c * 34, y0))
        for c, idx in enumerate(combos[13:27]):
            f = 6 + (c % 3)                         # right: idle, walk 1, walk 2
            for (part, (y0, y1)), st in zip(SPLIT.items(), idx):
                band = sheets[part].crop((f * 32, st * (y1 - y0), f * 32 + 32, (st + 1) * (y1 - y0)))
                im.alpha_composite(band, (c * 34, 50 + y0))
        im.resize((im.width * 4, im.height * 2), Image.NEAREST).save(args.preview)


if __name__ == "__main__":
    main()
