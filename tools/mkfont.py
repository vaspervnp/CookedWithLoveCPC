#!/usr/bin/env python3
"""HUD font: glyphs of 4 x 8 Mode 0 pixels (40 columns), 1 bit per pixel,
drawn here as text; icons are two glyphs wide (money, clock, customer,
angry customer, day, star full and empty) and the dishes of the first menu
(with their ink).

Output (asm, base RAM): G_* glyph numbers, m0_left / m0_right: the screen
byte bits of a pen as the left / right pixel of a byte, and hud_font (4
bytes per glyph, a byte holds two lines: the high nibble the upper one, bit
3 of a nibble = left pixel). hud_font comes last: the letters of the
language (tools/text2asm.py) follow it. LETTERS: the letter glyphs.

Usage: mkfont.py <out.asm>
"""

import sys

from cpc import mode0_byte

# 3 pixels wide (the 4th column is the gap), 7 lines (the 8th is the gap)
DIGITS = {
    "0": ["###", "#.#", "#.#", "#.#", "#.#", "#.#", "###"],
    "1": [".#.", "##.", ".#.", ".#.", ".#.", ".#.", "###"],
    "2": ["###", "..#", "..#", "###", "#..", "#..", "###"],
    "3": ["###", "..#", "..#", "###", "..#", "..#", "###"],
    "4": ["#.#", "#.#", "#.#", "###", "..#", "..#", "..#"],
    "5": ["###", "#..", "#..", "###", "..#", "..#", "###"],
    "6": ["###", "#..", "#..", "###", "#.#", "#.#", "###"],
    "7": ["###", "..#", "..#", ".#.", ".#.", ".#.", ".#."],
    "8": ["###", "#.#", "#.#", "###", "#.#", "#.#", "###"],
    "9": ["###", "#.#", "#.#", "###", "..#", "..#", "###"],
}
OTHER = {
    "SPACE": ["...", "...", "...", "...", "...", "...", "..."],
    "COLON": ["...", ".#.", ".#.", "...", ".#.", ".#.", "..."],
}
# 8 pixels wide: two glyphs (_L, _R)
ICONS = {
    "COIN": ["..####..",
             ".##..##.",
             "##.##.##",
             "##.#..##",
             "##.##.##",
             ".##..##.",
             "..####.."],
    "CLOCK": ["..####..",
              ".#..#.#.",
              "#...#..#",
              "#...##.#",
              "#......#",
              ".#....#.",
              "..####.."],
    "ANGRY": ["..####..",
              ".#....#.",
              "#.#..#.#",
              "#......#",
              "#..##..#",
              ".##..##.",
              "..####.."],
    "SUN": ["#..##..#",
            ".#....#.",
            "..####..",
            "#.####.#",
            "..####..",
            ".#....#.",
            "#..##..#"],
    "STAR": ["...##...",
             "...##...",
             "########",
             ".######.",
             "..####..",
             ".##..##.",
             "##....##"],
    "STAR0": ["...##...",
              "..#..#..",
              "###..###",
              ".#....#.",
              "..#..#..",
              ".#.##.#.",
              "##....##"],
    "PERSON": ["...##...",
               "...##...",
               "..####..",
               ".#.##.#.",
               "...##...",
               "..#..#..",
               "..#..#.."],
}


# the dishes of the first menu (data/recipes/recipes.tsv order): icon, ink
DISHES = [
    ("dolmades", 10, [".######.",
                      "#.#.#.##",
                      ".######.",
                      "........",
                      ".######.",
                      "##.#.#.#",
                      ".######."]),
    ("cod", 13, ["........",
                 ".####..#",
                 "######.#",
                 "#.######",
                 "######.#",
                 ".####..#",
                 "........"]),
    ("pasta", 8, ["...##...",
                  "..#..#..",
                  ".#.##.#.",
                  "#.#..#.#",
                  "########",
                  ".######.",
                  "........"]),
    ("lentils", 5, ["........",
                    "#.#.#.#.",
                    ".#.#.#.#",
                    "########",
                    ".######.",
                    "..####..",
                    "........"]),
    ("pork", 4, ["..####..",
                 ".######.",
                 "########",
                 "########",
                 ".######.",
                 "...##...",
                 "...##..."]),
    ("pumpkinpie", 5, ["#.......",
                       "##......",
                       "###.....",
                       "####....",
                       "#####...",
                       "######..",
                       "#######."]),
    ("potatoes", 8, ["........",
                     ".##..##.",
                     "####.###",
                     "####.###",
                     ".##..##.",
                     "...##...",
                     "..####.."]),
    ("cookies", 7, ["..####..",
                    ".######.",
                    "##....##",
                    "##....##",
                    "##....##",
                    ".######.",
                    "..####.."]),
]


# letters (and punctuation) for the texts: tools/text2asm.py takes the ones a
# language uses; Greek capitals shaped like Latin ones use those
LETTERS = {
    "A": [".#.", "#.#", "#.#", "###", "#.#", "#.#", "#.#"],
    "B": ["##.", "#.#", "#.#", "##.", "#.#", "#.#", "##."],
    "C": [".##", "#..", "#..", "#..", "#..", "#..", ".##"],
    "D": ["##.", "#.#", "#.#", "#.#", "#.#", "#.#", "##."],
    "E": ["###", "#..", "#..", "##.", "#..", "#..", "###"],
    "F": ["###", "#..", "#..", "##.", "#..", "#..", "#.."],
    "G": [".##", "#..", "#..", "#.#", "#.#", "#.#", ".##"],
    "H": ["#.#", "#.#", "#.#", "###", "#.#", "#.#", "#.#"],
    "I": ["###", ".#.", ".#.", ".#.", ".#.", ".#.", "###"],
    "J": ["..#", "..#", "..#", "..#", "..#", "#.#", ".#."],
    "K": ["#.#", "#.#", "##.", "#..", "##.", "#.#", "#.#"],
    "L": ["#..", "#..", "#..", "#..", "#..", "#..", "###"],
    "M": ["#.#", "###", "###", "#.#", "#.#", "#.#", "#.#"],
    "N": ["#.#", "##.", "##.", "#.#", "#.#", "#.#", "#.#"],
    "O": [".#.", "#.#", "#.#", "#.#", "#.#", "#.#", ".#."],
    "P": ["##.", "#.#", "#.#", "##.", "#..", "#..", "#.."],
    "Q": [".#.", "#.#", "#.#", "#.#", "#.#", "##.", ".##"],
    "R": ["##.", "#.#", "#.#", "##.", "#.#", "#.#", "#.#"],
    "S": [".##", "#..", "#..", ".#.", "..#", "..#", "##."],
    "T": ["###", ".#.", ".#.", ".#.", ".#.", ".#.", ".#."],
    "U": ["#.#", "#.#", "#.#", "#.#", "#.#", "#.#", "###"],
    "V": ["#.#", "#.#", "#.#", "#.#", "#.#", ".#.", ".#."],
    "W": ["#.#", "#.#", "#.#", "#.#", "###", "###", "#.#"],
    "X": ["#.#", "#.#", ".#.", ".#.", ".#.", "#.#", "#.#"],
    "Y": ["#.#", "#.#", "#.#", ".#.", ".#.", ".#.", ".#."],
    "Z": ["###", "..#", "..#", ".#.", "#..", "#..", "###"],
    "Γ": ["###", "#..", "#..", "#..", "#..", "#..", "#.."],
    "Δ": [".#.", ".#.", "#.#", "#.#", "#.#", "#.#", "###"],
    "Θ": [".#.", "#.#", "#.#", "###", "#.#", "#.#", ".#."],
    "Λ": [".#.", ".#.", "#.#", "#.#", "#.#", "#.#", "#.#"],
    "Ξ": ["###", "...", "...", "###", "...", "...", "###"],
    "Π": ["###", "#.#", "#.#", "#.#", "#.#", "#.#", "#.#"],
    "Σ": ["###", "#..", ".#.", "..#", ".#.", "#..", "###"],
    "Φ": [".#.", "###", "#.#", "#.#", "###", ".#.", ".#."],
    "Ψ": ["#.#", "#.#", "#.#", "###", ".#.", ".#.", ".#."],
    "Ω": [".#.", "#.#", "#.#", "#.#", "#.#", ".#.", "#.#"],
    "-": ["...", "...", "...", "###", "...", "...", "..."],
    ".": ["...", "...", "...", "...", "...", "...", ".#."],
    ",": ["...", "...", "...", "...", "...", ".#.", "#.."],
    "!": [".#.", ".#.", ".#.", ".#.", ".#.", "...", ".#."],
    "?": ["##.", "..#", "..#", ".#.", ".#.", "...", ".#."],
}
SAME = dict(zip("ΑΒΕΖΗΙΚΜΝΟΡΤΥΧ", "ABEZHIKMNOPTYX"))


def pack(g):
    """8 lines of a glyph -> 4 bytes, two lines each"""
    return [(g[2 * i] << 4) | g[2 * i + 1] for i in range(4)]


# the ingredient groups of the storage (Hard, tools/recipes2asm.py ING_*):
# vegetables, meat/fish, grain/flour, dairy, pulses
INGREDIENTS = [
    ("veg", 5, ["....##..",
                "...##...",
                "..####..",
                ".####...",
                ".###....",
                "###.....",
                "##......"]),
    ("meat", 4, [".####...",
                 "######..",
                 "######..",
                 ".#####..",
                 "...###..",
                 "....##.#",
                 ".....###"]),
    ("grain", 8, ["...#....",
                  "..#.#...",
                  "...#....",
                  "..#.#...",
                  "...#....",
                  "..#.#...",
                  "...#...."]),
    ("dairy", 13, ["..###...",
                   ".#...#..",
                   ".#####..",
                   ".#####..",
                   ".##.##..",
                   ".#####..",
                   ".#####.."]),
    ("pulses", 7, ["........",
                   ".##..##.",
                   "####.###",
                   "####.###",
                   ".##..##.",
                   "........",
                   "........"]),
]


def glyph(rows, x0=0, w=3):
    out = []
    for r in rows + ["." * len(rows[0])]:
        bits = 0
        for i in range(4):
            x = x0 + i
            if i < w and x < len(r) and r[x] == "#":
                bits |= 8 >> i
        out.append(bits)
    return out


def base_glyphs():
    glyphs, names = [], []
    for k in sorted(DIGITS):
        names.append("G_" + k)
        glyphs.append(glyph(DIGITS[k]))
    for k, rows in OTHER.items():
        names.append("G_" + k)
        glyphs.append(glyph(rows))
    for k, rows in ICONS.items():
        names.append(f"G_{k}_L")
        glyphs.append(glyph(rows, 0, 4))
        names.append(f"G_{k}_R")
        glyphs.append(glyph(rows, 4, 4))
    dish0 = len(names)
    for k, ink, rows in DISHES:
        names.append(f"G_D_{k.upper()}_L")
        glyphs.append(glyph(rows, 0, 4))
        names.append(f"G_D_{k.upper()}_R")
        glyphs.append(glyph(rows, 4, 4))
    ing0 = len(names)
    for k, ink, rows in INGREDIENTS:
        names.append(f"G_I_{k.upper()}_L")
        glyphs.append(glyph(rows, 0, 4))
        names.append(f"G_I_{k.upper()}_R")
        glyphs.append(glyph(rows, 4, 4))
    return names, glyphs, dish0, ing0


def main():
    names, glyphs, dish0, ing0 = base_glyphs()
    with open(sys.argv[1], "w") as f:
        f.write("; generated by tools/mkfont.py\n")
        for i, n in enumerate(names):
            f.write(f"{n}\tequ {i}\n")
        f.write(f"G_DISH0\tequ {dish0}\t; dish d: G_DISH0 + 2 * d (left, right)\n")
        f.write("dish_ink:\n\tdb " + ",".join(str(ink) for _, ink, _ in DISHES) + "\n")
        f.write(f"G_ING0\tequ {ing0}\t; ingredient group g: G_ING0 + 2 * g\n")
        f.write("ing_ink:\n\tdb " + ",".join(str(ink) for _, ink, _ in INGREDIENTS) + "\n")
        f.write(f"G_BASE\tequ {len(names)}\t; the letters of the language follow\n")
        f.write("m0_left:\n\tdb " + ",".join(f"#{mode0_byte(p, 0):02X}" for p in range(16)) + "\n")
        f.write("m0_right:\n\tdb " + ",".join(f"#{mode0_byte(0, p):02X}" for p in range(16)) + "\n")
        f.write("hud_font:\n")
        for n, g in zip(names, glyphs):
            f.write("\tdb " + ",".join(f"#{b:02X}" for b in pack(g)) + f"\t; {n}\n")


if __name__ == "__main__":
    main()
