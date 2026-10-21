#!/usr/bin/env python3
"""Small add-on sprites drawn as pixel art: Bill's tray and the customers'
mood bubbles. They are drawn together with a figure (own sprites with their
own depth key), so the figures need no extra poses.

  assets/sprites/tray.png    32x12 frames: 1, 2, 3 plates seen from the front
                             (Bill facing down), then from the side (facing
                             right; left = mirror)
  assets/sprites/mouth.png   32x20: an open mouth over a customer's head in
                             profile (facing right; left = mirror): the
                             sitting customers talk (drawn over their stamp)
  assets/sprites/bubble.png  32x14 frames: heart (happy), angry, waiting
                             (...), wants food (plate), wants to pay (coin); Bill
                             taking an order (notepad)

Usage: items.py <out dir> [--preview out.png]
"""

import argparse
import os

from PIL import Image

from cpc import fw_to_rgb, load_palette

# pens (data/palette.txt)
BLACK, BLUE, BRED, ORANGE, PINK, PYEL, BYEL, GREEN, BGREEN = 14, 1, 4, 5, 6, 7, 8, 9, 10
RED, WHITE, BWHITE, YELLOW = 3, 12, 13, 15


def canvas(w, h):
    return [[0] * w for _ in range(h)]


def put(c, x, y, p):
    if 0 <= y < len(c) and 0 <= x < len(c[0]):
        c[y][x] = p


def ellipse(c, cx, cy, rx, ry, p, fill=True):
    for y in range(len(c)):
        for x in range(len(c[0])):
            d = ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2
            if d <= 1.0 and (fill or d > 0.55):
                c[y][x] = p


def outline(c):
    out = [r[:] for r in c]
    for y in range(len(c)):
        for x in range(len(c[0])):
            if c[y][x]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= ny < len(c) and 0 <= nx < len(c[0]) and c[ny][nx] not in (0, BLACK):
                    out[y][x] = BLACK
                    break
    return out


FOOD = [(RED, ORANGE), (BGREEN, GREEN), (BYEL, ORANGE)]   # sauce, salad, fries


def plate(c, cx, cy, food, rx=3.6, ry=2.4):
    ellipse(c, cx, cy, rx, ry, BWHITE)
    ellipse(c, cx, cy - 0.4, rx * 0.68, ry * 0.68, food[0])
    put(c, int(cx), int(cy - 1), food[1])
    put(c, int(cx) - 1, int(cy), food[1])


def tray_front(n):
    c = canvas(32, 12)
    ellipse(c, 16, 8.5, 10, 2.8, WHITE)                   # grey tray, plates on it
    pos = {1: [16], 2: [11.5, 20.5], 3: [9.5, 16, 22.5]}[n]
    for k, x in enumerate(pos):
        plate(c, x, 6.2, FOOD[k])
    return outline(c)


def tray_side(n):
    c = canvas(32, 12)
    ellipse(c, 22, 8.5, 8, 2.0, WHITE)                    # held out in front
    pos = {1: [22], 2: [18.5, 25.5], 3: [17, 22, 27]}[n]
    for k, x in enumerate(pos):
        plate(c, x, 6.6, FOOD[k], 2.8, 2.0)
    return outline(c)


def bubble(icon):
    c = canvas(32, 14)
    ellipse(c, 16, 6, 7.5, 5.5, BWHITE)
    put(c, 14, 12, BWHITE)                                # tail
    put(c, 13, 13, BWHITE)
    if icon == "heart":
        for x, y in ((14, 4), (15, 4), (17, 4), (18, 4), (13, 5), (14, 5), (15, 5), (16, 5), (17, 5), (18, 5),
                     (19, 5), (14, 6), (15, 6), (16, 6), (17, 6), (18, 6), (15, 7), (16, 7), (17, 7), (16, 8)):
            put(c, x, y, BRED)
    elif icon == "angry":
        for i in range(8):                                # a red zigzag
            put(c, 12 + i, (3, 5, 7, 5, 3, 5, 7, 5)[i], BRED)
            put(c, 12 + i, (4, 6, 8, 6, 4, 6, 8, 6)[i], BRED)
    elif icon == "wait":
        for x in (12, 16, 20):                            # (Mode 0 pixels are wide)
            put(c, x, 5, BLACK)
            put(c, x, 6, BLACK)
    elif icon == "food":
        plate(c, 16, 6.5, FOOD[0], 5.5, 3.6)
    elif icon == "order":                                # notepad and pencil
        for y in range(3, 10):
            for x in range(13, 18):
                put(c, x, y, BWHITE if y > 3 else BRED)
        for y in (5, 7):
            for x in (14, 15, 16):
                put(c, x, y, BLUE)
        for k in range(4):
            put(c, 19, 3 + k * 2, BYEL)
            put(c, 19, 4 + k * 2, BYEL)
        put(c, 19, 10, BLACK)
    elif icon == "pay":
        ellipse(c, 16, 6, 3.2, 3.2, BYEL)
        ellipse(c, 16, 6, 3.2, 3.2, ORANGE, fill=False)
        put(c, 16, 5, ORANGE)
        put(c, 16, 6, ORANGE)
    return outline(c)


def mouth():
    """Open mouth, head lines 17-18 at the front of the face (profile)."""
    c = canvas(32, 20)
    put(c, 18, 17, BLACK)
    put(c, 19, 17, BLACK)
    put(c, 18, 18, RED)
    put(c, 19, 18, BLACK)
    return c


def save(frames, w, h, path, rgb):
    im = Image.new("RGBA", (w * len(frames), h), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        for y in range(h):
            for x in range(w):
                if f[y][x]:
                    im.putpixel((i * w + x, y), rgb[f[y][x]] + (255,))
    im.save(path)
    return im


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("out")
    ap.add_argument("--preview")
    args = ap.parse_args()
    pens, _ = load_palette()
    rgb = [fw_to_rgb(fw) for fw, _ in pens]
    a = save([tray_front(n) for n in (1, 2, 3)] + [tray_side(n) for n in (1, 2, 3)], 32, 12,
             os.path.join(args.out, "tray.png"), rgb)
    b = save([bubble(i) for i in ("heart", "angry", "wait", "food", "pay", "order")], 32, 14,
             os.path.join(args.out, "bubble.png"), rgb)
    save([mouth()], 32, 20, os.path.join(args.out, "mouth.png"), rgb)
    if args.preview:
        pv = Image.new("RGBA", (max(a.width, b.width), a.height + b.height + 2), (60, 60, 70, 255))
        pv.alpha_composite(a, (0, 0))
        pv.alpha_composite(b, (0, a.height + 2))
        pv.resize((pv.width * 8, pv.height * 4), Image.NEAREST).save(args.preview)


if __name__ == "__main__":
    main()
