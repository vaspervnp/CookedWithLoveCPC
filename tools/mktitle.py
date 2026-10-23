#!/usr/bin/env python3
"""Title screen: a standard Mode 0 screen (160 x 200, &C000 layout: line y at
(y / 8) * 80 + (y % 8) * &800) with the title in big letters, Bill, Liberty
and Blossom (frame 0 of their sheets), the controls and the credits, in
English or Greek, with the letters of tools/mkfont.py (3 x 7, scaled).
The loader (src/loader.asm) shows it while the game loads, src/ovl/prep.asm
loads it again (fdc_load) and shows it until fire.

Usage: mktitle.py <en|gr> <out.scr> [--png preview.png]
"""

import argparse
import os

from PIL import Image

from cpc import ROOT, fw_to_rgb, load_palette, mode0_byte
from mkfont import DIGITS, LETTERS, OTHER, SAME, plain_char
from png2cpc import to_pens

W, H = 160, 200
SIZE = 0x4000 - 128     # with its AMSDOS header 32 whole sectors: fdc_load reads
                        # them to &C000 - 128 .. &FFFF; the rest (line 199) black
BLACK, RED, ORANGE, YELLOW, GREEN, WHITE, GREY, WOOD = 0, 4, 5, 8, 10, 13, 12, 15

TEXT = {
    "en": {
        "names": ("BILL", "LIBERTY", "BLOSSOM"),
        "lines": [
            (WHITE, "ARROWS: WALK  FIRE: ACTION"),
            (WHITE, "SPACE / FIRE 2: SWAP"),
            (GREY, "RECIPES: COOKEDWITHLOVE.GR"),
            (GREY, "ELEFTHERIA PANAGIOTOPOULOU"),
        ],
        "start": "FIRE: START",
    },
    "gr": {
        "names": ("ΒΑΣΙΛΗΣ", "ΕΛΕΥΘΕΡΙΑ", "ΑΝΘΗ"),
        "lines": [
            (WHITE, "ΒΕΛΑΚΙΑ: ΚΙΝΗΣΗ  FIRE: ΕΝΕΡΓΕΙΑ"),
            (WHITE, "SPACE / FIRE 2: ΑΛΛΑΓΗ"),
            (GREY, "ΣΥΝΤΑΓΕΣ: COOKEDWITHLOVE.GR"),
            (GREY, "ΕΛΕΥΘΕΡΙΑ ΠΑΝΑΓΙΩΤΟΠΟΥΛΟΥ"),
        ],
        "start": "FIRE: ΕΝΑΡΞΗ",
    },
}


def glyph_rows(ch):
    if ch in DIGITS:
        return DIGITS[ch]
    if ch == " ":
        return OTHER["SPACE"]
    if ch == ":":
        return OTHER["COLON"]
    return LETTERS[plain_char(ch)]


def text(img, s, y, pen, sx=1, sy=1, x=None):
    """Draw s (cells of 4 x 8, scaled sx, sy), centred unless x is given."""
    w = len(s) * 4 * sx
    if x is None:
        x = (W - w) // 2
    for i, ch in enumerate(s):
        rows = glyph_rows(ch)
        for r, line in enumerate(rows):
            for c, b in enumerate(line):
                if b == "#":
                    for dy in range(sy):
                        for dx in range(sx):
                            img[y + r * sy + dy][x + (i * 4 + c) * sx + dx] = pen
    return x


def sprite(img, sheet, x, y):
    pens = to_pens(Image.open(os.path.join(ROOT, "assets", "sprites", sheet)).crop((0, 0, 32, 48)), False, True)
    for r, row in enumerate(pens):
        for c, p in enumerate(row):
            if p:
                img[y + r][x + c] = p


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("lang", choices=TEXT)
    ap.add_argument("out")
    ap.add_argument("--png")
    args = ap.parse_args()
    t = TEXT[args.lang]
    img = [[BLACK] * W for _ in range(H)]
    for y in range(0, 4):               # tablecloth stripes, top and bottom
        for x in range(W):                  # (line 199 stays black: SIZE)
            img[y][x] = img[H - 2 - y][x] = RED if (x // 4 + y // 2) % 2 else WHITE
    text(img, "COOKED", 12, YELLOW, 2, 3)
    text(img, "WITH LOVE", 38, ORANGE, 2, 3)
    for i, (sheet, name) in enumerate(zip(("bill.png", "liberty.png", "blossom.png"), t["names"])):
        cx = 30 + i * 50
        sprite(img, sheet, cx - 16, 66)
        text(img, name, 118, GREEN, x=cx - len(name) * 2)
    y = 134
    for pen, s in t["lines"]:
        text(img, s, y, pen)
        y += 10
    text(img, t["start"], 180, YELLOW)
    scr = bytearray(0x4000)
    for y in range(H):
        base = (y // 8) * 80 + (y % 8) * 0x800
        for x in range(0, W, 2):
            scr[base + x // 2] = mode0_byte(img[y][x], img[y][x + 1])
    assert not any(scr[SIZE:]), "the screen's last bytes are not black"
    with open(args.out, "wb") as f:
        f.write(scr[:SIZE])
    if args.png:
        pens, _ = load_palette()
        rgb = [fw_to_rgb(fw) for fw, _ in pens]
        im = Image.new("RGB", (W * 2, H))
        for y in range(H):
            for x in range(W):
                im.putpixel((2 * x, y), rgb[img[y][x]])
                im.putpixel((2 * x + 1, y), rgb[img[y][x]])
        im.resize((W * 4, H * 2), Image.NEAREST).save(args.png)


if __name__ == "__main__":
    main()
