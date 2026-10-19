#!/usr/bin/env python3
"""Sprite compiler: sprite sheet PNG -> Z80 code that draws each frame.

Each distinct sprite line (32 pixels, pen 0 transparent) becomes a routine:

    call SAVE_s_n        ; HL = IX + s (first covered byte), the n bytes
                         ; saved to (DE) with LDI, HL back to the first byte
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
frame for the restore. The compiled code is only used when the whole sprite
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
    """SAVE stub: HL = IX + s, save n bytes, HL = IX + s again."""
    return (bytes((0xDD, 0x7D, 0xC6, s, 0x6F, 0xDD, 0x7C, 0xCE, 0x00, 0x67, 0xE5))
            + b"\xED\xA0" * n + bytes((0xE1, 0xC9)))


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
    def __init__(self, num):
        self.num = num
        self.img = bytearray(STEP_CODE)
        self.lines = {}                      # (span, body) -> address
        self.saves = {}                      # span -> address

    def addr(self):
        return BANK_BASE + len(self.img)

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
                calls.append(BANK_BASE)       # STEP only
                continue
            if span not in self.saves:
                self.saves[span] = self.addr()
                self.img += save_code(*span)
            key = (span, body)
            if key not in self.lines:
                self.lines[key] = self.addr()
                sv = self.saves[span]
                self.img += bytes((0xCD, sv & 255, sv >> 8)) + body
                self.img += bytes((0xC3, BANK_BASE & 255, BANK_BASE >> 8))
            calls.append(self.lines[key])
        prog = self.addr()
        for c in calls:
            self.img += bytes((0xCD, c & 255, c >> 8))
        self.img.append(0xC9)
        span_addr = self.addr()
        for st, n in spans:
            self.img += bytes((st, n))
        return prog, span_addr


def load_sheet(path, fw, fh, group, mirror_from):
    """Frames of a sheet in reading order. Every `group` frames form one
    variant (a figure or a part style); within each, the frames from
    `mirror_from` on are appended again mirrored (left = mirrored right)."""
    img = Image.open(path).convert("RGBA")
    pens = to_pens(img, False, sprite=True)
    frames = []
    for fy in range(img.height // fh):
        for fx in range(img.width // fw):
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
                    help="PREFIX:PNG:HEIGHT[:GROUP[:MIRROR_FROM]] (width 32); all sheets share the banks")
    ap.add_argument("--banks", default="4,6,7", help="banks for compiled code")
    args = ap.parse_args()

    sheets = []
    for spec in args.sheet:
        f = spec.split(":")
        prefix, path, h = f[0], f[1], int(f[2])
        group = int(f[3]) if len(f) > 3 else 0
        mirror = int(f[4]) if len(f) > 4 else -1
        sheets.append((prefix, path, h, load_sheet(path, 32, h, group, mirror)))

    # unique frames over all sheets, with empty lines trimmed at the top and
    # bottom (the descriptor keeps the offset), so frames that only move up
    # or down (a head bobbing while walking) are stored once
    uniq, uidx = [], {}
    index = {}
    for prefix, path, h, frames in sheets:
        index[prefix] = []
        for f in frames:
            rows = [i for i, r in enumerate(f) if any(r)] or [0]
            dy = rows[0]
            key = tuple(tuple(r) for r in f[dy:rows[-1] + 1])
            if key not in uidx:
                uidx[key] = len(uniq)
                uniq.append(key)
            index[prefix].append((uidx[key], dy))

    banks = [Bank(int(b)) for b in args.banks.split(",")]
    placed = []
    bi = 0
    for f in uniq:
        f = [list(r) for r in f]
        while len(banks[bi].img) + banks[bi].need(f) > BANK_SIZE:
            bi += 1
            if bi == len(banks):
                sys.exit("compiled sprites do not fit in the banks")
        prog, span = banks[bi].add(f)
        placed.append((banks[bi].num, prog, span, len(f)))

    for bk in banks:
        if os.path.exists(f"{args.out}_{bk.num}.dat"):
            os.remove(f"{args.out}_{bk.num}.dat")
        if len(bk.img) > len(STEP_CODE):   # unused bank: no file
            with open(f"{args.out}_{bk.num}.dat", "wb") as f:
                f.write(bk.img)
    used = [bk for bk in banks if len(bk.img) > len(STEP_CODE)]
    bits = sum(1 << bk.num for bk in used)
    summary = (f"{len(uniq)} unique frames; "
               + ", ".join(f"bank {bk.num}: {len(bk.img)}" for bk in used))

    with open(f"{args.out}.asm", "w", encoding="utf-8") as f:
        f.write("; generated by tools/spritec.py\n; " + summary + "\n")
        f.write("SPR_BANKS\tequ " + str(bits) + "\t; bit n = bank n has a file\n")
        descs = sorted({d for v in index.values() for d in v})
        for prefix, path, h, frames in sheets:
            f.write(f"; {prefix}: {path}, {len(frames)} frames of 32x{h}\n{prefix}_frames:\n")
            for u, dy in index[prefix]:
                f.write(f"\tdw spr_d{u}_{dy}\n")
        for u, dy in descs:
            bank, ent, span, h = placed[u]
            f.write(f"spr_d{u}_{dy}:\tdb #{0xC0 + bank:02X} : dw #{ent:04X},#{span:04X} : db {h},{dy}\n")
    print(summary, file=sys.stderr)


if __name__ == "__main__":
    main()
