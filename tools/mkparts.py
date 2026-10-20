#!/usr/bin/env python3
"""Customer part sheets (head / body / legs) from character renders.

Runs the render2sprite conversion once per colour variant (other material
ramps), then cuts each 32x48 frame into three horizontal bands. Each output
sheet has one row per variant and 9 frames per row (down, up, right x idle,
walk 1, walk 2), the layout tools/spritec.py expects (GROUP 9, MIRROR_FROM 6). Any
head can then be combined with any body and any legs.

Placeholder customers until they get their own Blender models: the variants
are recolours of the Bill renders (no apron, other hair/clothes colours).

Usage: mkparts.py <render dir> <out dir> [--preview out.png]
"""

import argparse
import json
import os

from PIL import Image

import render2sprite as r2s
from cpc import fw_to_rgb, load_palette

# band limits (lines): head 0..19, body 20..33, legs 34..47
SPLIT = (0, 20, 34, 48)
# poses kept: idle and a 2-step walk (of Bill's idle + 4-step walk)
POSES = (0, 1, 3)
PARTS = ("head", "body", "legs")

# variants per part: material ramps that differ from the base (render2sprite)
HEADS = [
    {"hair": [14, 14, 14, 14, 1]},           # black
    {"hair": [5, 15, 15, 8, 7]},             # blonde
    {"hair": [14, 12, 12, 13, 13]},          # grey
]
BODIES = [
    {"vest": [3, 3, 4, 4], "bowtie": [12, 13]},          # red
    {"vest": [9, 9, 10, 10], "bowtie": [8, 15]},         # green
    {"vest": [2, 2, 11, 11], "bowtie": [12, 13]},        # blue
]
LEGS = [
    {"trousers": [14, 1], "apron": [14, 1, 1]},          # navy
    {"trousers": [9, 9], "apron": [9, 9, 10]},           # green
    {"trousers": [3, 3], "apron": [3, 3, 4]},            # red
]


def frames_for(renders, feats, ramps):
    base = dict(r2s.RAMP)
    r2s.RAMP.update(ramps)
    out = []
    try:
        for d in r2s.DIRS:
            for i in POSES:
                idi = Image.open(os.path.join(renders, f"id_{d}{i}.png")).convert("RGBA")
                shi = Image.open(os.path.join(renders, f"shade_{d}{i}.png")).convert("RGBA")
                px = r2s.convert(idi, shi)
                r2s.draw_face(px, feats[f"{d}{i}"], d == "right")
                out.append(r2s.outline(px))
    finally:
        r2s.RAMP.clear()
        r2s.RAMP.update(base)
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("renders")
    ap.add_argument("out")
    ap.add_argument("--preview")
    args = ap.parse_args()

    pens, _ = load_palette()
    rgb = [fw_to_rgb(fw) for fw, _ in pens]
    feats = json.load(open(os.path.join(args.renders, "features.json")))
    n = len(POSES) * len(r2s.DIRS)
    sheets = []
    for k, (part, variants) in enumerate(zip(PARTS, (HEADS, BODIES, LEGS))):
        y0, y1 = SPLIT[k], SPLIT[k + 1]
        sheet = Image.new("RGBA", (32 * n, (y1 - y0) * len(variants)), (0, 0, 0, 0))
        for v, ramps in enumerate(variants):
            for i, px in enumerate(frames_for(args.renders, feats, ramps)):
                for y in range(y0, y1):
                    for x in range(32):
                        if px[y][x]:
                            sheet.putpixel((i * 32 + x, v * (y1 - y0) + y - y0), rgb[px[y][x]] + (255,))
        sheet.save(os.path.join(args.out, f"cust_{part}.png"))
        sheets.append(sheet)
    if args.preview:
        # every head with body/legs of the same index and some mixes, pose 0
        combos = [(h, b, l) for h in range(len(HEADS)) for b, l in ((h, h), ((h + 1) % 3, (h + 2) % 3))]
        im = Image.new("RGBA", (34 * len(combos), 48), (60, 60, 70, 255))
        for c, idx in enumerate(combos):
            for k, v in enumerate(idx):
                y0, y1 = SPLIT[k], SPLIT[k + 1]
                band = sheets[k].crop((0, v * (y1 - y0), 32, (v + 1) * (y1 - y0)))
                im.alpha_composite(band, (c * 34, y0))
        im.resize((im.width * 8, im.height * 4), Image.NEAREST).save(args.preview)


if __name__ == "__main__":
    main()
