#!/usr/bin/env python3
"""Level map -> tiles and tile map, for tools/maps2asm.py.

Reads a tileset (assets/tiles/<set>.png: 16x16 metatiles in rows of 8, and
<set>.txt: map character, name, solid quadrants per metatile) and a level
(assets/maps/<level>.txt: 40 x 42 characters, comment lines start with
"# "). Cuts every metatile into its four 8x8 tiles, keeps each distinct
(pixels, solid) tile once, walkable tiles first and solid ones after (the
engine's test is tile >= SOLID_FIRST), and writes:

  <out>_src_tiles.bin   tiles, 32 bytes each (Mode 0, 4 bytes x 8 lines)
  <out>_src_map.bin     80 x 84 tile map
  <out>.asm             SOLID_FIRST, the object constants, Bill's spot at
                        the pass
  <out>_objs.asm        the level's tables (data for bank 5)
  <out>_stations.asm    its stations (not used by the game yet):
      tables: found by their pattern, a table for 2 is <t>, a table for 4
        <T> over <U> (a chair on each side of each row); per table the
        seats and the spot where Bill serves (the floor below the table)
      stations: kitchen, storage and dining room objects with the free
        sides from which they are used

Usage: buildmap.py <tileset.png> <level.txt> <out prefix>
"""

import argparse
from collections import deque
import os
import sys

from PIL import Image

from cpc import mode0_byte
from png2cpc import to_pens

MW, MH = 40, 42


def load_set(png):
    txt = os.path.splitext(png)[0] + ".txt"
    defs = [l.split() for l in open(txt) if l.strip() and not l.startswith("//")]
    pens = to_pens(Image.open(png).convert("RGBA"), False)
    metas = {}
    for i, (ch, name, solid) in enumerate(defs):
        x0, y0 = (i % 8) * 16, (i // 8) * 16
        quads = []
        for q in range(4):
            qx, qy = x0 + (q & 1) * 8, y0 + (q >> 1) * 8
            px = tuple(tuple(pens[qy + y][qx:qx + 8]) for y in range(8))
            quads.append((px, solid[q] == "1"))
        metas[ch] = quads
    return metas


# station types: map character -> name (the first metatile of an object)
STATIONS = [("K", "counter"), ("S", "stove"), ("O", "oven"), ("N", "sink"), ("F", "fridge"),
            ("P", "pass"), ("h", "hatch"), ("$", "till"), ("B", "shelf"), ("X", "crate"),
            ("Z", "freezer"), ("D", "door"), ("m", "entrance")]
DIR_DOWN, DIR_UP, DIR_RIGHT, DIR_LEFT = 0, 1, 2, 3     # src/game/actor.asm


def seat(mx, my, d):
    """Sitting customer on the chair at (mx, my), facing d: sprite left/top
    (the figure is drawn SIT_DROP lower, src/game/customer.asm)."""
    return (16 * mx - 8, 16 * my - 30, d)


def find_objects(rows, metas):
    def free(mx, my):
        return 0 <= mx < MW and 0 <= my < MH and not any(s for _, s in metas[rows[my][mx]])

    def at(mx, my):
        return rows[my][mx] if 0 <= mx < MW and 0 <= my < MH else " "

    tables = []
    for my, r in enumerate(rows):
        for mx, c in enumerate(r):
            if c == "t" and at(mx - 1, my) == "<" and at(mx + 1, my) == ">":
                tables.append(([seat(mx - 1, my, DIR_RIGHT), seat(mx + 1, my, DIR_LEFT)], mx, my))
            elif c == "T" and at(mx, my + 1) == "U":
                seats = []
                for y in (my, my + 1):
                    if at(mx - 1, y) == "<":
                        seats.append(seat(mx - 1, y, DIR_RIGHT))
                    if at(mx + 1, y) == ">":
                        seats.append(seat(mx + 1, y, DIR_LEFT))
                tables.append((seats, mx, my + 1))
    out_t = []
    for seats, mx, by in tables:
        if not free(mx, by + 1):
            sys.exit(f"table at {mx},{by}: no floor below it for Bill")
        out_t.append((seats, 16 * mx + 8, 16 * (by + 1) + 14))   # Bill's feet, facing up

    out_s = []
    names = dict(STATIONS)
    for my, r in enumerate(rows):
        for mx, c in enumerate(r):
            if c not in names:
                continue
            if c in "Ff" and at(mx, my - 1) == c:
                continue
            if c in "PmD" and at(mx, my - 1) == c:            # tall objects: once
                continue
            if c == "m" and at(mx - 1, my) == "m":
                continue
            sides = (free(mx - 1, my) << 0 | free(mx + 1, my) << 1
                     | free(mx, my + (2 if c == "F" else 1)) << 2 | free(mx, my - 1) << 3)
            out_s.append((c, mx, my, sides))
    # the trunk: the free column nearest the entrance that runs from the
    # row above the first table down to the entrance (customers walk it to
    # the door)
    ent = next((mx, my) for c, mx, my, _ in out_s if c == "m")
    top = min(by for _, mx, by in tables) - 2
    trunk = next(mx for mx in sorted(range(MW), key=lambda m: abs(m - ent[0]))
                 if all(free(mx, y) for y in range(top, ent[1])))
    return out_t, out_s, trunk


def table_seats(n, bx, by):
    """the seats of a table of n (2 or 4) from Bill's spot, as tb_seat
    computes them: left (facing right) and right chair of each row"""
    y0 = by - 60 - (16 if n == 4 else 0)
    return [(bx - 32 + 32 * (k & 1), y0 + 16 * (k >> 1), DIR_LEFT if k & 1 else DIR_RIGHT)
            for k in range(n)]


def waiter_paths(rows, metas, home, tables):
    """the hired waiter's way from home (Bill's spot at the pass) to each
    table's spot: shortest over whole free metatiles (his feet fit in one),
    only the turning points (metatile column, row; the waiter walks to their
    centre, x first, then on to the spot)"""
    free = lambda c, r: 0 <= c < MW and 0 <= r < MH and not any(s for _, s in metas[rows[r][c]])
    prev, q = {home: None}, deque([home])
    while q:
        c = q.popleft()
        for d in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (c[0] + d[0], c[1] + d[1])
            if n not in prev and free(*n):
                prev[n] = c
                q.append(n)
    out = []
    for seats, bx, by in tables:
        t = (bx // 16, by // 16)
        if t not in prev:
            sys.exit(f"the waiter cannot reach the table at {bx},{by}")
        p = []
        while t:
            p.append(t)
            t = prev[t]
        p = p[::-1]
        step = lambda k: (p[k][0] - p[k - 1][0], p[k][1] - p[k - 1][1])
        out.append([p[k] for k in range(1, len(p) - 1) if step(k) != step(k + 1)])
    return out


def stand_path(rows, metas, home, mx, my):
    """the shortest way from home to a free metatile beside the station at
    mx, my (below, left, right, above: the nearest), as waiter_paths, its
    last point that one (None: none)"""
    free = lambda c, r: 0 <= c < MW and 0 <= r < MH and not any(s for _, s in metas[rows[r][c]])
    prev, q = {home: None}, deque([home])
    while q:
        c = q.popleft()
        for d in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (c[0] + d[0], c[1] + d[1])
            if n not in prev and free(*n):
                prev[n] = c
                q.append(n)
    best = None
    for d in ((0, 1), (-1, 0), (1, 0), (0, -1)):
        t = (mx + d[0], my + d[1])
        if t in prev:
            p = []
            while t:
                p.append(t)
                t = prev[t]
            if best is None or len(p) < len(best):
                best = p
    if best is None:
        return None
    p = best[::-1]
    step = lambda k: (p[k][0] - p[k - 1][0], p[k][1] - p[k - 1][1])
    return [p[k] for k in range(1, len(p) - 1) if step(k) != step(k + 1)] + [p[-1]], len(p)


def cook_paths(rows, krows, metas, home, cook, cook0):
    """the hired cook's way from home (Liberty's spot at the pass) to each
    stove and oven (stand_path); the kitchen's expansion's ones on its map
    (krows)"""
    out = []
    for i, (_, mx, my) in enumerate(cook):
        p = stand_path(rows if i < cook0 else krows, metas, home, mx, my)
        if p is None:
            sys.exit(f"the cook cannot reach the station at {mx},{my}")
        out.append(p[0])
    return out


def helper_paths(rows, metas, home, stor):
    """the storage helper's ways from home (beside the hatch) to the nearest
    place of each kind (0 shelf, 1 fridge, 2 door, 3 hatch: stand_path),
    and those places' indices among the storage's (stor)"""
    paths, idx = [], []
    for kind in range(4):
        best = None
        for i, (t, mx, my) in enumerate(stor):
            if t == kind:
                p = stand_path(rows, metas, home, mx, my)
                if p and (best is None or p[1] < best[0][1]):
                    best = (p, i)
        if best is None:
            sys.exit(f"the storage helper cannot reach a place of kind {kind}")
        paths.append(best[0][0])
        idx.append(best[1])
    return paths, idx


STOR_KINDS = {"B": 0, "F": 1, "Z": 1, "D": 2, "h": 3}


def storage_places(stations):
    """the storage's places for Blossom (Hard: 0 shelf, 1 fridge or
    freezer, 2 delivery door, 3 hatch; right of the kitchen): kind, column,
    row"""
    return [(STOR_KINDS[c], mx, my) for c, mx, my, _ in stations if c in STOR_KINDS and mx >= 29]


def write_objects(path, src, tables, stations, cook0, paths=(), cpaths=(), hpaths=(), hidx=()):
    names = dict(STATIONS)
    with open(path, "w") as f:
        f.write(f"; generated by tools/buildmap.py from {src}\n")
        f.write("; tables: seats, Bill's spot (feet x, y: below the table, facing up);\n")
        f.write("; the seats follow from it (src/game/service.asm tb_seat)\n")
        f.write("lvl_tables:\n")
        for i, (seats, bx, by) in enumerate(tables):
            if seats != table_seats(len(seats), bx, by):
                sys.exit(f"table {i}: its seats are not where tb_seat puts them")
            f.write(f"\tdb {len(seats)} : dw {bx},{by}\n")
        # the kitchen's cooking places (stoves and ovens, each metatile one):
        # type (0 stove, 1 oven), centre x, y (map pixels)
        # the kitchen's stoves (0) and ovens (1), the storage's places for
        # Blossom (Hard: 0 shelf, 1 fridge or freezer, 2 delivery door, 3
        # hatch, right of the kitchen), the hired waiter's ways to the tables
        # (src/game/waiter.asm): in the HUD page store (<out>_hp.asm)
        cook = [(0 if c == "S" else 1, mx, my) for c, mx, my, _ in stations if c in "SO"]
        stor = storage_places(stations)
        f.write(f"KS_N\tequ {len(cook)}\t; stoves, ovens: with the kitchen's expansion\n")
        f.write(f"KS_N0\tequ {cook0}\t; without it (the first ones)\n")
        f.write(f"SS_N\tequ {len(stor)}\t; the storage's places\n")
    def ways(name, paths, base):
        offs, pts = [], []
        for p in paths:
            offs.append(base + len(paths) + len(pts))
            pts += [len(p)] + [v for cr in p for v in cr]
        return [(name, offs), (name + "PTS", pts)]
    hp = [("HP_KS", [v for e in cook for v in e]), ("HP_SS", [v for e in stor for v in e])]
    hp2 = ways("HP_WTP", paths, 0)
    hp2 += ways("HP_CKP", cpaths, sum(len(d) for _, d in hp2))
    hp2 += ways("HP_HLP", hpaths, sum(len(d) for _, d in hp2))
    hp2.append(("HP_HLS", hidx))
    with open(path.replace("_objs.asm", "_hp.asm"), "w") as f:
        f.write(f"; generated by tools/buildmap.py from {src}: the HUD page stores\n")
        f.write("; (src/main.asm hp_get: the kitchen's stations, type, column, row:\n")
        f.write("; HP_KS, the storage's places: HP_SS; hp_get2: the waiter's ways to\n")
        f.write("; the tables, HP_WTP, the cook's to the stations, HP_CKP: per one the\n")
        f.write("; index of its turning points' number, then column, row of each);\n")
        f.write("; placed at the boot (hp_place)\n")
        for store, data, cap in (("hp_data", hp, 248), ("hp_data2", hp2, 360)):
            n = 0
            for name, d in data:
                f.write(f"{name}\tequ {n}\n")
                n += len(d)
            if n > cap:
                sys.exit(f"the HUD page store {store}: {n} bytes (at most {cap})")
            f.write(f"{store.upper()}_N\tequ {n}\n{store}:\n")
            for name, d in data:
                f.write(f"\tdb {','.join(map(str, d))}\t; {name}\n")
    with open(path, "a") as f:
        # seats as constants too (test placements)
        for i, (seats, bx, by) in enumerate(tables):
            for k, (x, y, d) in enumerate(seats):
                f.write(f"TB{i}_S{k}_X equ {x} : TB{i}_S{k}_Y equ {y} : TB{i}_S{k}_DIR equ {d}\n")


def write_stations(path, src, stations):
    names = dict(STATIONS)
    with open(path, "w") as f:
        f.write(f"; generated by tools/buildmap.py from {src}\n")
        f.write("; stations: type, metatile x, y, free sides (bit 0 left, 1 right,\n")
        f.write("; 2 below, 3 above)\n")
        f.write(f"STATION_COUNT\tequ {len(stations)}\n")
        f.write("lvl_stations:\n")
        for c, mx, my, sides in stations:
            f.write(f"\tdb STN_{names[c].upper()},{mx},{my},%{sides:04b}\n")


def encode(px):
    return bytes(mode0_byte(px[y][x], px[y][x + 1]) for y in range(8) for x in range(0, 8, 2))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("tileset")
    ap.add_argument("level")
    ap.add_argument("out")
    ap.add_argument("--open", help="the level with its expansion open (<out>_src_open.bin; the tables of this one, the expansion's first: TB_LOCK_N)")
    ap.add_argument("--kopen", help="the level with the kitchen's expansion open (<out>_src_kopen.bin; its stoves and ovens after the others: KS_N0 without it)")
    args = ap.parse_args()
    metas = load_set(args.tileset)

    def load_rows(path):
        rows = [l.rstrip("\n") for l in open(path) if not l.startswith("# ")]
        if len(rows) != MH or any(len(r) != MW for r in rows):
            sys.exit(f"{path}: expected {MH} rows of {MW} characters")
        bad = sorted({c for r in rows for c in r if c not in metas})
        if bad:
            sys.exit(f"{path}: unknown characters {''.join(bad)}")
        return rows

    rows = load_rows(args.level)
    orows = load_rows(args.open) if args.open else rows
    krows = load_rows(args.kopen) if args.kopen else rows
    used = sorted({q for rr in (rows, orows, krows) for r in rr for c in r for q in metas[c]}, key=lambda t: (t[1], t))
    if len(used) > 256:
        sys.exit(f"{len(used)} tiles (at most 256)")
    index = {t: i for i, t in enumerate(used)}

    def tilemap(rows):
        tmap = bytearray(MW * 2 * MH * 2)
        for my, r in enumerate(rows):
            for mx, c in enumerate(r):
                for q, t in enumerate(metas[c]):
                    tmap[(2 * my + (q >> 1)) * MW * 2 + 2 * mx + (q & 1)] = index[t]
        return tmap

    tmap = tilemap(rows)
    if args.open:
        with open(f"{args.out}_src_open.bin", "wb") as f:
            f.write(tilemap(orows))
    if args.kopen:
        with open(f"{args.out}_src_kopen.bin", "wb") as f:
            f.write(tilemap(krows))
    solid_first = sum(1 for t in used if not t[1])
    with open(f"{args.out}_src_tiles.bin", "wb") as f:
        f.write(b"".join(encode(t[0]) for t in used))
    with open(f"{args.out}_src_map.bin", "wb") as f:
        f.write(tmap)
    tables, stations, trunk = find_objects(orows, metas)
    # the stations with the kitchen open (the new ones after the others)
    kstations = find_objects(krows, metas)[1]
    cook0 = [s for s in stations if s[0] in "SO"]
    if [s for s in kstations if s[0] in "SO"][:len(cook0)] != cook0:
        sys.exit("the kitchen's expansion: its stoves and ovens must come after the others")
    spots = {(bx, by) for _, bx, by in find_objects(rows, metas)[0]}
    locked = [i for i, (_, bx, by) in enumerate(tables) if (bx, by) not in spots]
    if locked != list(range(len(locked))):
        sys.exit("the expansion's tables must come first (above the others)")
    with open(f"{args.out}.asm", "w") as f:
        f.write(f"; generated by tools/buildmap.py from {args.level}\n")
        f.write(f"SOLID_FIRST\tequ {solid_first}\t; tiles >= this block movement\n")
        f.write("TB_SEATS equ 0 : TB_BX equ 1 : TB_BY equ 3 : TB_SIZE equ 5\n")
        f.write(f"TABLE_COUNT\tequ {len(tables)}\n")
        f.write(f"TB_LOCK_N\tequ {len(locked)}\t; the expansion's tables (the first ones)\n")
        f.write(f"TRUNK_X\tequ {16 * trunk - 8}\t; customers to the door: column {trunk} (sprite left)\n")
        for k, (c, name) in enumerate(STATIONS):
            f.write(f"STN_{name.upper()}\tequ {k}\n")
        # Bill's spot at the pass (its dining room side: the free side left
        # or right of it, half way down the two metatiles)
        for c, mx, my, sides in stations:
            if c == "P":
                side = -1 if sides & 1 else 1
                f.write(f"PASS_BX\tequ {16 * (mx + side) + 8}\t; Bill's feet at the pass\n")
                f.write(f"PASS_BY\tequ {16 * my + 24}\n")
                f.write(f"PASS_X\tequ {16 * mx}\t; the pass, top left (map pixels)\n")
                f.write(f"PASS_Y\tequ {16 * my}\n")
                f.write(f"PASS_KX\tequ {16 * (mx - side) + 8}\t; Liberty's feet at it (kitchen)\n")
                break
    paths, cpaths = [], []
    for c, mx, my, sides in stations:
        if c == "P":				# home: Bill's (Liberty's) spot at the pass
            side = -1 if sides & 1 else 1
            paths = waiter_paths(orows, metas, (mx + side, (16 * my + 24) // 16), tables)
            cook = [(0, sx, sy) for sc, sx, sy, _ in kstations if sc in "SO"]
            cpaths = cook_paths(rows, krows, metas, (mx - side, (16 * my + 24) // 16), cook, len(cook0))
            break
    hpaths, hidx = [], []
    for c, mx, my, sides in stations:
        if c == "h":				# the storage helper's home: beside the hatch
            home = (mx + 1, my)
            hpaths, hidx = helper_paths(rows, metas, home, storage_places(kstations))
            with open(f"{args.out}.asm", "a") as f:
                f.write(f"HL_HX\tequ {16 * home[0] + 8}\t; the storage helper's home (feet)\n")
                f.write(f"HL_HY\tequ {16 * home[1] + 12}\n")
            break
    write_objects(f"{args.out}_objs.asm", args.level, tables, kstations, len(cook0), paths, cpaths, hpaths, hidx)
    write_stations(f"{args.out}_stations.asm", args.level, stations)
    print(f"{args.out}: {len(used)} tiles ({solid_first} walkable), {len(tables)} tables "
          f"({sum(len(t[0]) for t in tables)} seats), {len(stations)} stations", file=sys.stderr)


if __name__ == "__main__":
    main()
