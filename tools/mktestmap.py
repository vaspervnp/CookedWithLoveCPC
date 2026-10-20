#!/usr/bin/env python3
"""Generate the M1 scroll test map (80x84 tiles of 8x8 = 4x4 playfield screens).

Each of the 16 screens has its own colour. Every tile has a black top line and
left column (grid), so 1-line / 2-pixel offsets are easy to see. Some tiles
carry a white diagonal (on the 16x16 metatile grid, so the map compresses)
and every screen has its number in a corner tile, so
direction and position can be read off a screenshot.

Outputs: <tiles.bin> (N tiles x 32 bytes), <map.bin> (80x84 bytes) and
<hud.bin> (82-byte HUD line pattern for x = -1..80, used with a 1-byte shift
for the R3 phase).
"""

import argparse

from cpc import mode0_byte

MAP_W, MAP_H = 80, 84
SCR_W, SCR_H = 20, 21          # tiles per playfield screen
SCREEN_PENS = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 6, 15, 3, 9]
WHITE = 13

DIGITS = {  # 3x5 font
    0: "111101101101111", 1: "010110010010111", 2: "111001111100111",
    3: "111001111001111", 4: "101101111001001", 5: "111100111001111",
    6: "111100111101111", 7: "111001010010010", 8: "111101111101111",
    9: "111101111001111",
}


def tile_pixels(pen, diag=False, digit=None):
    px = [[pen] * 8 for _ in range(8)]
    for i in range(8):
        px[0][i] = 0
        px[i][0] = 0
    if diag:
        for i in range(1, 8):
            px[i][i] = WHITE
    if digit is not None:
        bits = DIGITS[digit]
        for y in range(5):
            for x in range(3):
                if bits[y * 3 + x] == "1":
                    px[2 + y][3 + x] = WHITE
    return px


def encode(px):
    return bytes(mode0_byte(px[y][x], px[y][x + 1]) for y in range(8) for x in range(0, 8, 2))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("tiles")
    ap.add_argument("map")
    ap.add_argument("hud")
    args = ap.parse_args()

    tiles = []
    for s in range(16):                      # 0..15 plain, 16..31 diagonal
        tiles.append(tile_pixels(SCREEN_PENS[s]))
    for s in range(16):
        tiles.append(tile_pixels(SCREEN_PENS[s], diag=True))
    for s in range(16):                      # 32..47 screen number (1..16 -> last digit)
        tiles.append(tile_pixels(SCREEN_PENS[s], digit=(s + 1) % 10))
    # 48: brick wall, 49: stone pillar (solid: tile >= SOLID_FIRST)
    wall = [[12] * 8 for _ in range(8)]
    for y in range(8):
        for x in range(8):
            if y in (3, 7):
                wall[y][x] = 12                  # mortar
            elif x == (0 if y < 3 else 4):
                wall[y][x] = 12
            else:
                wall[y][x] = 4 if (y in (0, 4)) else 3
    tiles.append(wall)
    pillar = [[13 if x < 2 else (12 if x < 6 else 14) for x in range(8)] for y in range(8)]
    for x in range(8):
        pillar[0][x] = 13
        pillar[7][x] = 14
    tiles.append(pillar)

    m = bytearray()
    for ty in range(MAP_H):
        for tx in range(MAP_W):
            s = (tx // SCR_W) + 4 * (ty // SCR_H)
            lx, ly = tx % SCR_W, ty % SCR_H
            if tx in (0, MAP_W - 1) or ty in (0, MAP_H - 1):
                t = 48
            elif tx % 10 in (5, 6) and ty % 10 in (5, 6) and (tx, ty) != (5, 5):
                t = 49
            elif (lx, ly) == (1, 1):
                t = 32 + s
            elif tx % 2 == 0 and ty % 2 == 0 and (tx // 2 + 2 * (ty // 2)) % 5 == 0:
                t = 16 + s
            else:
                t = s
            m.append(t)

    with open(args.tiles, "wb") as f:
        f.write(b"".join(encode(t) for t in tiles))
    with open(args.map, "wb") as f:
        f.write(m)

    hud = bytearray()
    for x in range(-1, 81):
        if x % 10 == 0:
            pen = WHITE
        else:
            pen = SCREEN_PENS[(x // 5) % 16]
        hud.append(mode0_byte(pen, pen))
    with open(args.hud, "wb") as f:
        f.write(hud)


if __name__ == "__main__":
    main()
