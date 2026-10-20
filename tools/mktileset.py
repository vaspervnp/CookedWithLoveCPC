#!/usr/bin/env python3
"""Restaurant tileset: 16x16 metatiles (Mode 0 pixels, 2x2 tiles of 8x8)
drawn as pixel art by code, for the level maps (assets/maps/*.txt,
tools/buildmap.py).

  assets/tiles/restaurant.png  the metatiles in a sheet (8 per row)
  assets/tiles/restaurant.txt  one line per metatile: map character, name,
                               solid quadrants (4 bits: top left, top right,
                               bottom left, bottom right)

The view is top-down with the camera tilted (as the characters): objects
show their top and a strip of their front. Mode 0 pixels are twice as wide
as tall, so a metatile looks twice as wide as high.

Usage: mktileset.py <out dir> [--preview out.png]
"""

import argparse
import os

from PIL import Image

from cpc import fw_to_rgb, load_palette

# pens (data/palette.txt)
BLUE, BBLUE, RED, BRED, ORANGE, PINK, PYEL, BYEL = 1, 2, 3, 4, 5, 6, 7, 8
GREEN, BGREEN, SKY, GREY, WHITE, BLACK, OLIVE = 9, 10, 11, 12, 13, 14, 15

N = 16


class M:
    """A metatile canvas."""

    def __init__(self, floor=None):
        self.p = [[BLACK] * N for _ in range(N)]
        if floor:
            floor(self)

    def put(self, x, y, c):
        if 0 <= x < N and 0 <= y < N:
            self.p[y][x] = c

    def rect(self, x0, y0, x1, y1, c):          # inclusive
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.put(x, y, c)

    def hline(self, x0, x1, y, c):
        self.rect(x0, y, x1, y, c)

    def vline(self, x, y0, y1, c):
        self.rect(x, y0, x, y1, c)


# ---- floors (period 16 or 8 so they repeat between metatiles) ----
def wood(m):
    """Dining room: olive planks of 8 lines, joints staggered."""
    for y in range(N):
        for x in range(N):
            m.p[y][x] = OLIVE
    for y in (7, 15):
        m.hline(0, 15, y, RED)
    m.vline(3, 0, 6, RED)
    m.vline(11, 8, 14, RED)


def checker(m):
    """Kitchen: white and grey tiles (4 px x 8 lines: square on screen)."""
    for y in range(N):
        for x in range(N):
            m.p[y][x] = WHITE if ((x // 4) + (y // 8)) % 2 else GREY


def concrete(m):
    """Storage: grey concrete with specks and slab joints."""
    for y in range(N):
        for x in range(N):
            m.p[y][x] = GREY
    m.hline(0, 15, 15, BLACK)
    m.vline(15, 0, 15, BLACK)
    for x, y in ((3, 2), (10, 5), (6, 9), (13, 12), (1, 13), (8, 1)):
        m.put(x, y, WHITE)
    for x, y in ((5, 6), (12, 2), (2, 10)):
        m.put(x, y, BLACK)


def locked(floor):
    """An expansion still closed: the floor in the dark (a sparse grid)."""
    def f(m):
        floor(m)
        for y in range(N):
            for x in range(N):
                if x % 4 or y % 4:
                    m.p[y][x] = BLACK
    return f


# ---- walls ----
def wall_cap(m):
    """Top of a wall seen from above (wall rows, vertical walls)."""
    m.rect(0, 0, 15, 15, GREY)
    m.hline(0, 15, 0, WHITE)
    m.hline(0, 15, 15, BLACK)
    for x in (3, 11):
        m.put(x, 7, WHITE)


def brick(m):
    """Front of a wall (under its cap): red bricks."""
    for y in range(N):
        for x in range(N):
            m.p[y][x] = RED if (y // 4) % 2 else BRED
    for y in (3, 7, 11, 15):
        m.hline(0, 15, y, GREY)
    for k, y in enumerate((0, 4, 8, 12)):
        for x in ((0, 8) if k % 2 == 0 else (4, 12)):
            m.vline(x, y, y + 2, GREY)
    m.hline(0, 15, 15, BLACK)                # shadow on the floor


def side_wall(left):
    """A vertical wall seen from above (thin: half the metatile)."""
    def f(m, floor):
        floor(m)
        x0, x1 = (0, 7) if left else (8, 15)
        m.rect(x0, 0, x1, 15, GREY)
        m.vline(x0, 0, 15, WHITE)
        m.vline(x1, 0, 15, BLACK)
    return f


# ---- dining room ----
def cloth(m, x0, x1, y0, y1):
    """Red and white checked tablecloth."""
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            m.put(x, y, WHITE if ((x - x0) // 2 + (y - y0) // 4) % 2 else BRED)


def table(m, x0=1, x1=14):
    """Table top (cloth) and its front drape."""
    cloth(m, x0, x1, 2, 10)
    m.hline(x0, x1, 1, BLACK)
    m.vline(x0 - 1, 1, 13, BLACK)
    m.vline(x1 + 1, 1, 13, BLACK)
    m.rect(x0, 11, x1, 13, RED)              # drape
    m.hline(x0, x1, 14, BLACK)
    m.put(x0 + 1, 15, BLACK)                 # legs
    m.put(x1 - 1, 15, BLACK)


def table4_top(m):
    """Table for 4, top half (it is two metatiles tall: two chairs a side)."""
    cloth(m, 1, 14, 2, 15)
    m.hline(1, 14, 1, BLACK)
    m.vline(0, 1, 15, BLACK)
    m.vline(15, 1, 15, BLACK)


def table4_bottom(m):
    cloth(m, 1, 14, 0, 9)
    m.vline(0, 0, 13, BLACK)
    m.vline(15, 0, 13, BLACK)
    m.rect(1, 10, 14, 13, RED)               # drape
    m.hline(1, 14, 14, BLACK)
    m.put(2, 15, BLACK)
    m.put(13, 15, BLACK)


def chair_top(m):
    """Chair above a table (the customer sits facing down): back at the
    top, seat below it."""
    m.rect(4, 1, 11, 3, ORANGE)              # back rest
    m.hline(4, 11, 0, BLACK)
    m.hline(4, 11, 4, RED)
    m.vline(4, 4, 7, RED)
    m.vline(11, 4, 7, RED)
    m.rect(4, 8, 11, 12, ORANGE)             # seat
    m.hline(4, 11, 13, RED)
    m.vline(4, 14, 15, BLACK)
    m.vline(11, 14, 15, BLACK)


def chair_bottom(m):
    """Chair below a table (facing up): seat, back rest at the bottom."""
    m.rect(4, 2, 11, 6, ORANGE)
    m.hline(4, 11, 1, BLACK)
    m.hline(4, 11, 7, RED)
    m.rect(4, 9, 11, 12, ORANGE)             # back rest, seen from behind
    m.hline(4, 11, 8, BLACK)
    m.hline(4, 11, 13, RED)
    m.vline(4, 13, 15, BLACK)
    m.vline(11, 13, 15, BLACK)


def chair_side(right):
    """Chair beside a table, the customer faces the table (in profile)."""
    def f(m):
        bx = 12 if not right else 3          # back rest away from the table
        m.rect(5, 6, 10, 10, ORANGE)         # seat
        m.hline(5, 10, 5, BLACK)
        m.hline(5, 10, 11, RED)
        m.rect(bx - 1, 1, bx, 11, RED)       # back rest
        m.vline(bx - 1 if right else bx, 0, 0, BLACK)
        for x in (5, 10):
            m.vline(x, 12, 14, BLACK)
    return f


def plant(m):
    m.rect(5, 10, 10, 14, ORANGE)            # pot
    m.hline(5, 10, 10, RED)
    m.hline(6, 9, 15, BLACK)
    for x, y in ((7, 1), (8, 1), (5, 3), (10, 3), (4, 5), (11, 5), (6, 6), (9, 6),
                 (7, 4), (8, 4), (6, 2), (9, 2), (5, 7), (10, 7), (7, 8), (8, 8)):
        m.put(x, y, BGREEN)
    for x, y in ((7, 3), (8, 6), (6, 5), (9, 4), (7, 7), (8, 9), (7, 9)):
        m.put(x, y, GREEN)


def till(m):
    """Cash desk with the till."""
    m.rect(0, 6, 15, 12, OLIVE)              # desk
    m.hline(0, 15, 5, ORANGE)
    m.rect(0, 13, 15, 14, RED)
    m.hline(0, 15, 15, BLACK)
    m.rect(4, 1, 11, 6, BLACK)               # till
    m.rect(5, 2, 10, 3, SKY)                 # its display
    m.hline(5, 10, 5, GREY)


def desk(m):
    m.rect(0, 6, 15, 12, OLIVE)
    m.hline(0, 15, 5, ORANGE)
    m.rect(0, 13, 15, 14, RED)
    m.hline(0, 15, 15, BLACK)


def mat(m):
    """Door mat at the entrance."""
    m.rect(1, 2, 14, 13, RED)
    m.rect(2, 3, 13, 12, BRED)
    for x in range(3, 13, 2):
        m.vline(x, 4, 11, RED)


def rope(m):
    """Rope barrier in front of a closed expansion."""
    m.hline(0, 15, 6, BRED)
    m.hline(0, 15, 7, RED)
    m.rect(7, 2, 8, 12, BYEL)                # post
    m.rect(6, 12, 9, 13, OLIVE)
    m.hline(7, 8, 1, PYEL)


# ---- kitchen ----
def steel_top(m, y1=10):
    m.rect(0, 0, 15, y1, WHITE)
    m.hline(0, 15, 0, GREY)
    m.rect(0, y1 + 1, 15, 14, GREY)          # front
    m.hline(0, 15, 15, BLACK)


def counter(m):
    steel_top(m)
    m.rect(3, 2, 12, 7, ORANGE)              # cutting board
    m.hline(3, 12, 8, RED)


def pass_counter(m):
    """The pass between dining room and kitchen: a shelf in the wall."""
    steel_top(m)
    m.hline(0, 15, 5, GREY)
    m.vline(7, 11, 14, BLACK)


def stove(m):
    steel_top(m)
    m.rect(1, 1, 14, 9, BLACK)
    for cx in (4, 11):
        for cy in (3, 7):
            m.hline(cx - 2, cx + 1, cy - 1, RED)
            m.hline(cx - 2, cx + 1, cy, BRED)
    for x in (3, 7, 11):                     # knobs on the front
        m.put(x, 12, BLACK)


def oven(m):
    steel_top(m, 4)
    m.rect(2, 6, 13, 12, BLACK)              # window
    m.rect(3, 8, 12, 11, RED)
    m.hline(4, 11, 10, ORANGE)
    m.hline(2, 13, 5, WHITE)                 # handle


def sink(m):
    steel_top(m)
    m.rect(2, 2, 13, 8, GREY)
    m.rect(3, 3, 12, 7, BBLUE)
    m.hline(3, 12, 3, SKY)
    m.rect(7, 0, 8, 2, BLACK)                # tap


def fridge_top(m):
    m.rect(1, 0, 14, 15, WHITE)
    m.vline(1, 0, 15, GREY)
    m.vline(14, 0, 15, GREY)
    m.hline(1, 14, 0, GREY)
    m.hline(1, 14, 9, GREY)                  # freezer door line
    m.vline(12, 3, 7, BLACK)                 # handles
    m.vline(12, 11, 15, BLACK)


def fridge_bottom(m):
    m.rect(1, 0, 14, 13, WHITE)
    m.vline(1, 0, 13, GREY)
    m.vline(14, 0, 13, GREY)
    m.vline(12, 0, 4, BLACK)
    m.hline(1, 14, 14, GREY)
    m.hline(1, 14, 15, BLACK)


def hatch(m):
    """The hatch between storage and kitchen: a shelf through the wall."""
    m.rect(0, 0, 15, 15, GREY)
    m.rect(2, 2, 13, 13, BLACK)
    m.rect(2, 9, 13, 11, WHITE)              # the shelf
    m.hline(2, 13, 12, GREY)


# ---- storage ----
def shelf(m):
    m.rect(0, 0, 15, 15, OLIVE)
    for y in (4, 9, 14):
        m.hline(0, 15, y, RED)
    for x, y, c in ((1, 1, ORANGE), (6, 1, BGREEN), (11, 1, ORANGE),
                    (2, 6, BRED), (8, 6, ORANGE), (12, 6, BYEL),
                    (1, 11, ORANGE), (5, 11, GREEN), (10, 11, BRED)):
        m.rect(x, y, x + 3, y + 2, c)
        m.hline(x, x + 3, y, PYEL if c in (ORANGE, BYEL) else WHITE)
    m.hline(0, 15, 15, BLACK)


def crate(m):
    m.rect(1, 1, 14, 9, ORANGE)              # top
    m.rect(1, 10, 14, 14, RED)               # front
    for x in (1, 14):
        m.vline(x, 1, 14, RED)
    m.hline(1, 14, 5, RED)
    m.hline(1, 14, 15, BLACK)
    m.rect(5, 11, 10, 13, ORANGE)


def freezer(m):
    m.rect(0, 1, 15, 9, SKY)                 # lid
    m.hline(0, 15, 0, WHITE)
    m.hline(0, 15, 5, WHITE)
    m.rect(0, 10, 15, 14, WHITE)
    m.hline(0, 15, 15, BLACK)
    m.rect(6, 11, 9, 12, GREY)


def door(m):
    """Delivery door in the outer wall (closed, solid)."""
    m.rect(0, 0, 15, 15, OLIVE)
    m.rect(1, 1, 14, 15, ORANGE)
    m.vline(7, 1, 15, RED)
    m.vline(8, 1, 15, RED)
    m.put(5, 8, BLACK)
    m.put(10, 8, BLACK)


# metatiles: char, name, floor, art, solid bits (TL TR BL BR)
SET = [
    (".", "wood", wood, None, "0000"),
    (",", "checker", checker, None, "0000"),
    (":", "concrete", concrete, None, "0000"),
    ("~", "wood_locked", locked(wood), None, "0000"),
    (";", "checker_locked", locked(checker), None, "0000"),
    ("#", "wall_cap", None, wall_cap, "1111"),
    ("H", "brick", None, brick, "1111"),
    ("[", "wall_left_wood", wood, side_wall(True), "1010"),
    ("]", "wall_right_wood", wood, side_wall(False), "0101"),
    ("{", "wall_left_checker", checker, side_wall(True), "1010"),
    ("}", "wall_right_checker", checker, side_wall(False), "0101"),
    ("(", "wall_left_concrete", concrete, side_wall(True), "1010"),
    (")", "wall_right_concrete", concrete, side_wall(False), "0101"),
    ("t", "table2", wood, table, "1111"),
    ("T", "table4_top", wood, table4_top, "1111"),
    ("U", "table4_bottom", wood, table4_bottom, "1111"),
    ("v", "chair_top", wood, chair_top, "1111"),
    ("^", "chair_bottom", wood, chair_bottom, "1111"),
    ("<", "chair_left", wood, chair_side(True), "1111"),   # left of a table, faces right
    (">", "chair_right", wood, chair_side(False), "1111"),
    ("p", "plant", wood, plant, "1111"),
    ("$", "till", wood, till, "1111"),
    ("=", "desk", wood, desk, "1111"),
    ("m", "mat", wood, mat, "0000"),
    ("-", "rope", wood, rope, "1111"),
    ("P", "pass", None, pass_counter, "1111"),
    ("K", "counter", checker, counter, "1111"),
    ("S", "stove", checker, stove, "1111"),
    ("O", "oven", checker, oven, "1111"),
    ("N", "sink", checker, sink, "1111"),
    ("F", "fridge_top", checker, fridge_top, "1111"),
    ("f", "fridge_bottom", checker, fridge_bottom, "1111"),
    ("h", "hatch", None, hatch, "1111"),
    ("B", "shelf", concrete, shelf, "1111"),
    ("X", "crate", concrete, crate, "1111"),
    ("Z", "freezer", concrete, freezer, "1111"),
    ("D", "door", None, door, "1111"),
]


def render():
    out = []
    for ch, name, floor, art, solid in SET:
        m = M(floor)
        if art:
            if art.__code__.co_argcount == 2:   # side walls take the floor
                art(m, floor)
            else:
                art(m)
        out.append((ch, name, solid, m.p))
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("out")
    ap.add_argument("--preview")
    args = ap.parse_args()
    pens, _ = load_palette()
    rgb = [fw_to_rgb(fw) for fw, _ in pens]
    rgb[0] = rgb[14]
    tiles = render()
    cols = 8
    rows = (len(tiles) + cols - 1) // cols
    im = Image.new("RGB", (cols * N, rows * N))
    for i, (ch, name, solid, p) in enumerate(tiles):
        for y in range(N):
            for x in range(N):
                im.putpixel(((i % cols) * N + x, (i // cols) * N + y), rgb[p[y][x]])
    os.makedirs(args.out, exist_ok=True)
    im.save(os.path.join(args.out, "restaurant.png"))
    with open(os.path.join(args.out, "restaurant.txt"), "w") as f:
        f.write("// generated by tools/mktileset.py: char name solid(TL TR BL BR), sheet order\n")
        for ch, name, solid, p in tiles:
            f.write(f"{ch} {name} {solid}\n")
    if args.preview:
        im.resize((im.width * 8, im.height * 4), Image.NEAREST).save(args.preview)


if __name__ == "__main__":
    main()
