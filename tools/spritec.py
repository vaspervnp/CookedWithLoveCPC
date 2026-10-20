#!/usr/bin/env python3
"""Sprite compiler: sprite sheet PNG -> Z80 code that draws each frame.

Each distinct sprite line (32 pixels, pen 0 transparent) becomes a routine:

    call SAVE_s_n        ; HL = IX + s (first covered byte); save-under
                         ; segment [n][HL][bytes] written at DE (LDI)
    ld a,(hl) / and m / or d / ld (hl),a     masked byte
    ld (hl),d                                 opaque byte
    (nothing)                                 transparent byte
    inc hl                                    between bytes
    jp STEP              ; IX = next line (IXH + 8, next_row on a new char row)

Identical lines are stored once per bank, so parts that do not change
between frames (head, body, empty lines, shoes...) are shared, and so are the
SAVE stubs (one per start/count pair). An empty line is STEP itself. A frame
is a program of calls, one per line, ending with RET:

    call line_routine
    ...
    ret

The engine enters at program + 3 * skipped lines and stops after the visible
lines by writing a RET over the next call for the duration of the run.
While it runs: IX = screen address of the line's byte 0, DE = save pointer,
BC and A are free (LDI). A span table (start, count per line) goes with each
frame for the clipped path. The compiled code is only used when the whole sprite
width is visible and no row crosses the end of a 2K screen block; otherwise
the engine runs the same line routines on a copy of each line (in base RAM)
and writes back the visible bytes.

Outputs:
  <out>_<bank>.dat   bank images (loaded at &4000 with that RAM config)
  <out>.asm          frame descriptors for the engine:
      <prefix>_frames: dw desc0, desc1, ...   (per sheet)
      desc: db bank ; dw program, span_table ; db height, dy
Empty lines are trimmed (dy = lines trimmed at the top); frames identical
after trimming, also between sheets, are stored once.
"""

import argparse
import glob
import os
import sys

from PIL import Image

from cpc import mode0_byte
from png2cpc import to_pens

BANK_BASE = 0x4000
BANK_SIZE = 0x4000
NR_VECTOR = 0x0103           # jp next_row, fixed at the start of the main binary


# STEP, at the start of every bank: next line, IXH + 8; on a new char row
# (raster bits back to 0) the engine's next_row sets IX
STEP_CODE = bytes((0xDD, 0x7C, 0xC6, 0x08, 0xDD, 0x67, 0xE6, 0x38, 0xC0,
                   0xC3, NR_VECTOR & 255, NR_VECTOR >> 8))


def save_code(s, n):
    """SAVE stub: HL = IX + s; a save-under segment [n][HL][n bytes] at DE
    (restored with a plain copy); HL = IX + s again."""
    return (bytes((0x3E, n, 0x12, 0x13,                       # ld a,n : ld (de),a : inc de
                   0xDD, 0x7D, 0xC6, s, 0x6F, 0x12, 0x13,     # ld a,ixl : add a,s : ld l,a : ld (de),a : inc de
                   0xDD, 0x7C, 0xCE, 0x00, 0x67, 0x12, 0x13,  # ld a,ixh : adc a,0 : ld h,a : ld (de),a : inc de
                   0xE5))                                     # push hl
            + b"\xED\xA0" * n + bytes((0xE1, 0xC9)))         # ldi * n : pop hl : ret


def line_body(r):
    """Drawing code of one sprite line and its (start, count), or None."""
    w = len(r)
    used = [i for i in range(w // 2) if r[2 * i] or r[2 * i + 1]]
    if not used:
        return None, (0, 0)
    s, e = used[0], used[-1] + 1
    code = bytearray()
    for i in range(s, e):
        lp, rp = r[2 * i], r[2 * i + 1]
        b = mode0_byte(lp, rp)
        if lp and rp:
            code += bytes((0x36, b))                          # ld (hl),b
        elif lp or rp:
            m = (0xAA if not lp else 0) | (0x55 if not rp else 0)
            code += bytes((0x7E, 0xE6, m, 0xF6, b, 0x77))     # masked
        if i != e - 1:
            code.append(0x23)                                 # inc hl
    return bytes(code), (s, e - s)


class Bank:
    def __init__(self, num, base=BANK_BASE, size=BANK_SIZE):
        self.num = num
        self.base = base
        self.size = size
        self.img = bytearray(STEP_CODE)
        self.lines = {}                      # (span, body) -> address
        self.saves = {}                      # span -> address

    def addr(self):
        return self.base + len(self.img)

    def need(self, rows):
        """Bytes needed to add a frame (new routines + program + spans)."""
        size, lines, saves = 0, set(), set()
        for r in rows:
            body, span = line_body(r)
            if body is None:
                continue
            if span not in self.saves and span not in saves:
                saves.add(span)
                size += len(save_code(*span))
            if (span, body) not in self.lines and (span, body) not in lines:
                lines.add((span, body))
                size += 3 + len(body) + 3
        return size + 3 * len(rows) + 1 + 2 * len(rows)

    def add(self, rows):
        calls, spans = [], []
        for r in rows:
            body, span = line_body(r)
            spans.append(span)
            if body is None:
                calls.append(self.base)       # STEP only
                continue
            if span not in self.saves:
                self.saves[span] = self.addr()
                self.img += save_code(*span)
            key = (span, body)
            if key not in self.lines:
                self.lines[key] = self.addr()
                sv = self.saves[span]
                self.img += bytes((0xCD, sv & 255, sv >> 8)) + body
                self.img += bytes((0xC3, self.base & 255, self.base >> 8))
            calls.append(self.lines[key])
        prog = self.addr()
        for c in calls:
            self.img += bytes((0xCD, c & 255, c >> 8))
        self.img.append(0xC9)
        span_addr = self.addr()
        for st, n in spans:
            self.img += bytes((st, n))
        return prog, span_addr


def load_sheet(path, fw, fh, group, mirror_from, pick=None):
    """Frames of a sheet in reading order (only the columns in `pick`, if
    given). Every `group` frames form one variant (a figure or a part style);
    within each, the frames from `mirror_from` on are appended again mirrored
    (left = mirrored right)."""
    img = Image.open(path).convert("RGBA")
    pens = to_pens(img, False, sprite=True)
    frames = []
    for fy in range(img.height // fh):
        for fx in pick if pick is not None else range(img.width // fw):
            frames.append([pens[fy * fh + y][fx * fw:(fx + 1) * fw] for y in range(fh)])
    group = group or len(frames)
    out = []
    for g in range(0, len(frames), group):
        v = frames[g:g + group]
        out += v
        if mirror_from >= 0:
            out += [[list(reversed(r)) for r in f] for f in v[mirror_from:]]
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("out", help="output prefix (path without extension)")
    ap.add_argument("--sheet", action="append", required=True,
                    help="PREFIX:PNG:HEIGHT[:GROUP[:MIRROR_FROM[:COLUMNS[:YOFF[:IMAGE]]]]] (width 32, "
                         "COLUMNS '0,1,3' keeps those columns of each row, YOFF = line of a part "
                         "within its figure, added to dy, IMAGE = area image of the area bank "
                         "instead of the common banks)")
    ap.add_argument("--banks", default="4,6", help="common banks for compiled code")
    ap.add_argument("--area-bank", type=int, default=7, help="bank of the area images")
    ap.add_argument("--fixed", action="append", default=[],
                    help="NAME:BANK:BASE:SIZE: the image NAME is a fixed part of a bank (always "
                         "resident, e.g. b5:5:0x7000:0x1000), not an area")
    args = ap.parse_args()

    sheets = []
    for spec in args.sheet:
        f = spec.split(":")
        prefix, path, h = f[0], f[1], int(f[2])
        group = int(f[3]) if len(f) > 3 and f[3] else 0
        mirror = int(f[4]) if len(f) > 4 and f[4] else -1
        pick = [int(c) for c in f[5].split(",")] if len(f) > 5 and f[5] else None
        yoff = int(f[6]) if len(f) > 6 and f[6] else 0
        image = f[7].lower() if len(f) > 7 and f[7] else None
        sheets.append((prefix, path, h, yoff, image, load_sheet(path, 32, h, group, mirror, pick)))

    # unique frames per image (common banks or one area image), with empty
    # lines trimmed at the top and bottom (the descriptor keeps the offset),
    # so frames that only move up or down (a head bobbing while walking) are
    # stored once
    images = [None] + sorted({sh[4] for sh in sheets if sh[4]})
    uniq = {g: [] for g in images}
    uidx = {g: {} for g in images}
    index = {}
    for prefix, path, h, yoff, image, frames in sheets:
        index[prefix] = []
        for f in frames:
            rows = [i for i, r in enumerate(f) if any(r)] or [0]
            dy = rows[0]
            key = tuple(tuple(r) for r in f[dy:rows[-1] + 1])
            if key not in uidx[image]:
                uidx[image][key] = len(uniq[image])
                uniq[image].append(key)
            index[prefix].append((image, uidx[image][key], dy + yoff))

    def place(frames, banks):
        placed, bi = [], 0
        for f in frames:
            f = [list(r) for r in f]
            while len(banks[bi].img) + banks[bi].need(f) > banks[bi].size:
                bi += 1
                if bi == len(banks):
                    return None
            prog, span = banks[bi].add(f)
            placed.append((banks[bi].num, prog, span, len(f)))
        return placed

    common = [Bank(int(b)) for b in args.banks.split(",")]
    placed = {None: place(uniq[None], common)}
    if placed[None] is None:
        sys.exit("compiled sprites do not fit in the common banks")
    fixed = {}
    for spec in args.fixed:
        name, bank, base, size = spec.split(":")
        fixed[name.lower()] = (int(bank), int(base, 0), int(size, 0))
    area = {}
    for g in images[1:]:
        if g in fixed:
            bank, base, size = fixed[g]
            area[g] = [Bank(bank, base, size)]
        else:
            area[g] = [Bank(args.area_bank)]
        placed[g] = place(uniq[g], area[g])
        if placed[g] is None:
            sys.exit(f"image {g} does not fit in its bank")
    areas = [g for g in images[1:] if g not in fixed]

    for p in glob.glob(f"{args.out}_*.dat"):     # stale banks/images
        os.remove(p)

    def write(name, bk):
        p = f"{args.out}_{name}.dat"
        if len(bk.img) > len(STEP_CODE):   # unused bank: no file
            with open(p, "wb") as f:
                f.write(bk.img)
    for bk in common:
        write(bk.num, bk)
    for g in images[1:]:
        write(g, area[g][0])
    used = [bk for bk in common if len(bk.img) > len(STEP_CODE)]
    bits = sum(1 << bk.num for bk in used)
    summary = (", ".join(f"bank {bk.num}: {len(bk.img)}" for bk in used)
               + "".join(f"; {'fixed' if g in fixed else 'area'} {g}: {len(area[g][0].img)}" for g in images[1:]))

    with open(f"{args.out}.asm", "w", encoding="utf-8") as f:
        f.write("; generated by tools/spritec.py\n; " + summary + "\n")
        f.write("SPR_BANKS\tequ " + str(bits) + "\t; bit n = common bank n has a file\n")
        f.write(f"SPR_AREAS\tequ {len(areas)}\t; area images (bank {args.area_bank}), files <NAME>.SPR\n")
        for k, g in enumerate(areas):
            f.write(f"AREA_{g.upper()}\tequ {k}\n")
        for g in fixed:
            bank, base, size = fixed[g]
            f.write(f"SPR_FIXED_{g.upper()}\tequ {int(g in images)}\t; file {g.upper()}.SPR at #{base:04X} of bank {bank}\n")
        f.write("spr_area_files:\t\t; directory names (8 + 3 characters)\n")
        for g in areas:
            f.write(f'\tdb "{g.upper()[:8]:<8}SPR"\n')
        def dname(g, u, dy):
            return f"spr_{g or 'c'}{u}_{dy}"
        descs = sorted({d for v in index.values() for d in v}, key=lambda d: (d[0] or "", d[1], d[2]))
        for prefix, path, h, yoff, image, frames in sheets:
            f.write(f"; {prefix}: {path}, {len(frames)} frames of 32x{h}"
                    + (f", area image {image}" if image else "") + f"\n{prefix}_frames:\n")
            for d in index[prefix]:
                f.write(f"\tdw {dname(*d)}\n")
        for g, u, dy in descs:
            bank, ent, span, h = placed[g][u]
            f.write(f"{dname(g, u, dy)}:\tdb #{0xC0 + bank:02X} : dw #{ent:04X},#{span:04X} : db {h},{dy}\n")
    print(summary, file=sys.stderr)


if __name__ == "__main__":
    main()
