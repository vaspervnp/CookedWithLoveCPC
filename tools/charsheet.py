#!/usr/bin/env python3
"""Sprite sheets of a staff character from its Blender renders
(assets/blender/<name>_build.py, shared helpers cwl_char.py).

Every frame goes through the render2sprite conversion (material per pixel,
palette ramps, face features, outline) with the character's materials and
colours, and is placed in the character's sheets (rows of frames, the layout
tools/spritec.py reads).

Usage: charsheet.py <name> <render dir> <out dir> [--preview out.png]
"""

import argparse
import json
import os

from PIL import Image

import render2sprite as r2s
from cpc import fw_to_rgb, load_palette

CHARS = {
    "liberty": {
        "mats": ["hair", "skin", "jacket", "buttons", "scarf", "trousers", "shoes",
                 "cap", "metal", "wood", "eyes", "mouth", "brows"],
        "ramps": {"hair": [14, 14, 1], "skin": [5, 6, 6, 6], "jacket": [12, 13, 13],
                  "buttons": [12], "scarf": [3, 4], "trousers": [14, 14, 1],
                  "shoes": [14, 14], "cap": [12, 13, 13], "metal": [12, 13],
                  "wood": [5], "mouth": [3]},
        "priority": {"buttons": 2, "scarf": 3, "metal": 2, "wood": 2, "mouth": 3},
        # sheet -> rows of frame tags
        "sheets": {
            "liberty": [["walk_down0", "walk_down1", "walk_down2"],
                        ["walk_up0", "walk_up1", "walk_up2"],
                        ["walk_right0", "walk_right1", "walk_right2"]],
            "liberty_act": [["act_chop0", "act_chop1", "act_stir0", "act_stir1",
                             "act_oven0", "act_oven1"]],
        },
        "side": lambda tag: "right" in tag or tag.startswith("act_"),
    },
    "blossom": {
        "mats": ["hair", "skin", "shirt", "overall", "buckle", "boots", "box", "tape",
                 "eyes", "mouth", "brows"],
        "ramps": {"hair": [3, 3, 4, 5], "skin": [5, 6, 6, 6], "shirt": [9, 10, 10],
                  "overall": [1, 2, 2], "buckle": [12], "boots": [14, 14],
                  "box": [5, 5, 15], "tape": [7], "mouth": [3]},
        "priority": {"buckle": 2, "tape": 2, "mouth": 3},
        "sheets": {
            "blossom": [["walk_down0", "walk_down1", "walk_down2"],
                        ["walk_up0", "walk_up1", "walk_up2"],
                        ["walk_right0", "walk_right1", "walk_right2"]],
            # carrying away from the viewer the box is hidden: walk_up is used
            "blossom_carry": [["carry_down0", "carry_down1", "carry_down2"],
                              ["carry_right0", "carry_right1", "carry_right2"]],
            "blossom_act": [["act_shelf0", "act_shelf1"]],
        },
        "side": lambda tag: "right" in tag or tag.startswith("act_"),
    },
}

W, H = 32, 48


def convert(cfg, renders, feats, tag):
    idi = Image.open(os.path.join(renders, f"id_{tag}.png")).convert("RGBA")
    shi = Image.open(os.path.join(renders, f"shade_{tag}.png")).convert("RGBA")
    saved = (r2s.MATS, dict(r2s.RAMP), dict(r2s.PRIORITY))
    r2s.MATS = cfg["mats"]
    r2s.RAMP.clear()
    r2s.RAMP.update({m: [14] for m in cfg["mats"]})
    r2s.RAMP.update(cfg["ramps"])
    r2s.PRIORITY.clear()
    r2s.PRIORITY.update(cfg["priority"])
    try:
        px = r2s.convert(idi, shi)
        r2s.draw_face(px, feats[tag], cfg["side"](tag))
        return r2s.outline(px)
    finally:
        r2s.MATS = saved[0]
        r2s.RAMP.clear()
        r2s.RAMP.update(saved[1])
        r2s.PRIORITY.clear()
        r2s.PRIORITY.update(saved[2])


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("name", choices=sorted(CHARS))
    ap.add_argument("renders")
    ap.add_argument("out")
    ap.add_argument("--preview")
    args = ap.parse_args()

    cfg = CHARS[args.name]
    pens, _ = load_palette()
    rgb = [fw_to_rgb(fw) for fw, _ in pens]
    feats = json.load(open(os.path.join(args.renders, "features.json")))
    images = []
    for sheet, rows in cfg["sheets"].items():
        im = Image.new("RGBA", (W * max(len(r) for r in rows), H * len(rows)), (0, 0, 0, 0))
        for ry, row in enumerate(rows):
            for rx, tag in enumerate(row):
                px = convert(cfg, args.renders, feats, tag)
                for y in range(H):
                    for x in range(W):
                        if px[y][x]:
                            im.putpixel((rx * W + x, ry * H + y), rgb[px[y][x]] + (255,))
        im.save(os.path.join(args.out, sheet + ".png"))
        images.append(im)
    if args.preview:
        w = sum(i.width for i in images) + 8
        pv = Image.new("RGBA", (w, max(i.height for i in images)), (60, 60, 70, 255))
        x = 0
        for i in images:
            pv.alpha_composite(i, (x, 0))
            x += i.width + 8
        pv.resize((pv.width * 8, pv.height * 4), Image.NEAREST).save(args.preview)


if __name__ == "__main__":
    main()
