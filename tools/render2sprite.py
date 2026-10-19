#!/usr/bin/env python3
"""Turn Blender id/shade renders (assets/blender/*_build.py) into a palette
sprite sheet.

Each sprite pixel covers a 4x4 block of the renders:
  - material: majority of the opaque samples; small "priority" materials
    (eyes, mouth, ...) win as soon as they cover a few samples
  - transparent when too few samples are opaque
  - colour: the material's ramp (dark..light pens), chosen by the average
    light level of its samples
The face is too small to come out of the render: the Blender script exports
the sprite-pixel positions and visibility of eyes, brows, nose and mouth
(features.json) and they are drawn here as clean pixels. Then a 1-pixel
outline is added around the silhouette.

Usage: render2sprite.py <render dir> <out sheet.png> [--preview out.png]
"""

import argparse
import json
import os

from PIL import Image

from cpc import fw_to_rgb, load_palette

W, H, S = 32, 48, 4               # sprite size, supersampling

# material ids (same order as MATS in bill_build.py)
MATS = ["hair", "skin", "shirt", "vest", "trousers", "shoes", "bowtie",
        "buttons", "eyes", "mouth", "apron", "brows"]

# ramps: pens dark -> light; priority materials need PRIO samples to show
RAMP = {
    "hair": [14, 14, 14, 14, 1],
    "skin": [5, 6, 6, 6],
    "shirt": [12, 13, 13],
    "vest": [14, 14, 1, 1],
    "trousers": [14, 1],
    "shoes": [14, 14, 12],
    "bowtie": [3, 4],
    "buttons": [8],
    "eyes": [14],
    "mouth": [3],
    "apron": [12, 13, 13],
    "brows": [14],
}
PRIORITY = {"eyes": 3, "mouth": 3, "brows": 3, "buttons": 2, "bowtie": 4}
MIN_OPAQUE = 7                    # of 16 samples
OUTLINE = 14
# light curve per material (t ** gamma, < 1 = lighter)
GAMMA = {"skin": 0.6}
SKIN = (5, 6)
EYE, BROW, MOUTH, NOSE = 14, 14, 3, 5

DIRS = ["down", "up", "right"]
POSES = 5


def draw_face(out, feats, side):
    def put(x, y, pen):
        if 0 <= x < W and 0 <= y < H and out[y][x]:
            out[y][x] = pen

    for e in ("eye_l", "eye_r"):
        x, y, vis = feats[e]
        if vis:
            put(int(x), round(y) - 1, EYE)
            put(int(x), round(y), EYE)
    for b in ("brow_l", "brow_r"):
        x, y, vis = feats[b]
        if vis:
            put(int(x), int(y), BROW)
    x, y, vis = feats["nose"]
    if not side and feats["eye_l"][2]:
        put(int(x), int(y), NOSE)
    x, y, vis = feats["mouth"]
    row = round(y)
    if side:
        if feats["eye_l"][2] or feats["eye_r"][2]:
            # face looks right: mouth on the front edge of the skin
            xs = [i for i in range(W) if out[row][i] in SKIN]
            if xs:
                put(xs[-1], row, MOUTH)
    elif vis:
        put(int(x) - 1, row, MOUTH)
        put(int(x), row, MOUTH)


def convert(id_img, shade_img):
    idp, shp = id_img.load(), shade_img.load()
    out = [[0] * W for _ in range(H)]
    mats = [[None] * W for _ in range(H)]
    for y in range(H):
        for x in range(W):
            counts, light = {}, {}
            opaque = 0
            for sy in range(S):
                for sx in range(S):
                    r, g, b, a = idp[x * S + sx, y * S + sy]
                    if a < 128:
                        continue
                    opaque += 1
                    k = max(0, min(len(MATS) - 1, round((r - 8) / 16)))
                    m = MATS[k]
                    counts[m] = counts.get(m, 0) + 1
                    lr, lg, lb, la = shp[x * S + sx, y * S + sy]
                    light.setdefault(m, []).append((lr + lg + lb) / 3)
            if not counts:
                continue
            mat = None
            for m, need in PRIORITY.items():
                if counts.get(m, 0) >= need and (mat is None or counts[m] > counts[mat]):
                    mat = m
            if mat is None:
                if opaque < MIN_OPAQUE:
                    continue
                mat = max(counts, key=counts.get)
            lv = sum(light[mat]) / len(light[mat]) / 255
            mats[y][x] = (mat, lv)
    # light level -> rank within the material in this frame (0..1), so a ramp
    # splits the material's pixels in proportion
    per = {}
    for row in mats:
        for m in row:
            if m:
                per.setdefault(m[0], []).append(m[1])
    for v in per.values():
        v.sort()
    for y in range(H):
        for x in range(W):
            if not mats[y][x]:
                continue
            mat, lv = mats[y][x]
            v = per[mat]
            t = (sum(1 for a in v if a < lv) + 0.5 * sum(1 for a in v if a == lv)) / len(v)
            t = t ** GAMMA.get(mat, 1.0)
            ramp = RAMP[mat]
            out[y][x] = ramp[min(len(ramp) - 1, int(t * len(ramp)))]
    return out


def outline(out):
    res = [row[:] for row in out]
    for y in range(H):
        for x in range(W):
            if out[y][x]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < W and 0 <= ny < H and out[ny][nx]:
                    res[y][x] = OUTLINE
                    break
    return res


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("renders")
    ap.add_argument("out")
    ap.add_argument("--preview")
    args = ap.parse_args()

    pens, _ = load_palette()
    rgb = [fw_to_rgb(fw) for fw, _ in pens]
    feats = json.load(open(os.path.join(args.renders, "features.json")))
    sheet = Image.new("RGBA", (W * POSES, H * len(DIRS)), (0, 0, 0, 0))
    for r, d in enumerate(DIRS):
        for i in range(POSES):
            idi = Image.open(os.path.join(args.renders, f"id_{d}{i}.png")).convert("RGBA")
            shi = Image.open(os.path.join(args.renders, f"shade_{d}{i}.png")).convert("RGBA")
            px = convert(idi, shi)
            draw_face(px, feats[f"{d}{i}"], d == "right")
            px = outline(px)
            for y in range(H):
                for x in range(W):
                    if px[y][x]:
                        sheet.putpixel((i * W + x, r * H + y), rgb[px[y][x]] + (255,))
    sheet.save(args.out)
    if args.preview:
        # Mode 0 aspect (2:1), scaled x4, on a mid grey background
        bg = Image.new("RGBA", sheet.size, (60, 60, 70, 255))
        bg.alpha_composite(sheet)
        bg.resize((sheet.width * 8, sheet.height * 4), Image.NEAREST).save(args.preview)


if __name__ == "__main__":
    main()
