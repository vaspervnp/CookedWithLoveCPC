#!/usr/bin/env python3
"""Convert an image to Amstrad CPC Mode 0 data.

The image must use only the colours of data/palette.txt. Indexed PNGs are
matched by RGB value (not by index), so the palette order in the file does not
matter. Width must be a multiple of 2 (sprite) or 8 (tiles). If the image has
square pixels at double width (e.g. 64x48 for a 32x48 sprite), use --halve.

Layouts:
  sprite : rows top to bottom, width/2 bytes per row
  tiles  : 8x8 tiles, left to right then top to bottom, 32 bytes per tile
"""

import argparse
import sys

from PIL import Image

from cpc import fw_to_rgb, load_palette, mode0_byte


def to_pens(img, halve, sprite=False):
    img = img.convert("RGBA")
    if halve:
        if img.width % 2:
            sys.exit("--halve needs an even width")
        img = img.resize((img.width // 2, img.height), Image.NEAREST)
    pens, _ = load_palette()
    # Several pens may share a colour (pen 0 and pen 14 are both black). For
    # sprites, pen 0 means transparent, so opaque pixels take the highest pen.
    order = list(enumerate(pens)) if sprite else list(reversed(list(enumerate(pens))))
    lookup = {fw_to_rgb(fw): i for i, (fw, _) in order}
    w, h = img.size
    px = img.load()
    out = []
    bad = set()
    for y in range(h):
        row = []
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 128:
                row.append(0)  # transparent -> pen 0
                continue
            pen = lookup.get((r, g, b))
            if pen is None:
                bad.add((r, g, b))
                pen = 0
            row.append(pen)
        out.append(row)
    if bad:
        sys.exit("colours not in palette: " + ", ".join("#%02X%02X%02X" % c for c in sorted(bad)))
    return out


def encode_rows(rows, x0, y0, w, h):
    data = bytearray()
    for y in range(y0, y0 + h):
        r = rows[y]
        for x in range(x0, x0 + w, 2):
            data.append(mode0_byte(r[x], r[x + 1]))
    return data


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input")
    ap.add_argument("output")
    ap.add_argument("--layout", choices=("sprite", "tiles"), default="sprite")
    ap.add_argument("--halve", action="store_true", help="halve width (square-pixel source)")
    args = ap.parse_args()

    rows = to_pens(Image.open(args.input), args.halve)
    h, w = len(rows), len(rows[0])

    if args.layout == "sprite":
        if w % 2:
            sys.exit("sprite width must be even")
        data = encode_rows(rows, 0, 0, w, h)
    else:
        if w % 8 or h % 8:
            sys.exit("tile sheet size must be a multiple of 8")
        data = bytearray()
        for ty in range(0, h, 8):
            for tx in range(0, w, 8):
                data += encode_rows(rows, tx, ty, 8, 8)

    with open(args.output, "wb") as f:
        f.write(data)


if __name__ == "__main__":
    main()
