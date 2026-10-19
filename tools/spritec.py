#!/usr/bin/env python3
"""Sprite compiler: sprite sheet PNG -> Z80 code that draws each frame.

Each distinct sprite line (32 pixels, pen 0 transparent) becomes a small
routine that writes the line's bytes with immediate values, then returns:

    ld a,(hl) / and m / or d / ld (hl),a     masked byte
    ld (hl),d                                 opaque byte
    (nothing)                                 transparent byte
    inc hl                                    between bytes
    ret

Identical lines are stored once per bank, so parts that do not change
between frames (head, body, empty lines, shoes...) are shared. A frame is a
program of 6-byte steps, one per line:

    call NL_VECTOR       ; line helper (src/engine/sprite.asm): HL = screen
                         ; address of the line's first covered byte, saves
                         ; those bytes; stops after the visible lines
    call line_routine    ; (empty lines call a shared RET)
    ...
    ret

so the entry for a sprite cut at the top is program + 6 * skipped lines.
A span table (start, count per line) goes with each frame (line helper and
restore). The compiled code is only used when the whole sprite width is
visible (lines crossing the end of a 2K screen block are handled by the line
helper); sprites cut at the left/right edge are drawn from the span data (format of tools/sprite2asm.py) in another
bank.

Outputs:
  <out>_<bank>.dat   bank images (loaded at &4000 with that RAM config)
  <out>.asm          frame descriptors for the engine:
      <prefix>_frames: dw desc0, desc1, ...
      desc: db bank ; dw program, span_table ; db data_bank ; dw data
"""

import argparse
import os
import sys

from PIL import Image

from cpc import mode0_byte
from png2cpc import to_pens
from sprite2asm import frame_lines

BANK_BASE = 0x4000
BANK_SIZE = 0x4000
NL_VECTOR = 0x0103           # jp nl_save, fixed at the start of the main binary


def line_code(r):
    """Routine for one sprite line (pixel row r), or None if empty."""
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
    code.append(0xC9)                                         # ret
    return bytes(code), (s, e - s)


class Bank:
    def __init__(self, num):
        self.num = num
        self.img = bytearray(b"\xC9")        # shared RET for empty lines
        self.lines = {}

    def addr(self):
        return BANK_BASE + len(self.img)

    def need(self, rows):
        """Bytes needed to add a frame (new line routines + program + spans)."""
        new = {}
        for r in rows:
            code, _ = line_code(r)
            if code and code not in self.lines and code not in new:
                new[code] = len(code)
        return sum(new.values()) + 6 * len(rows) + 1 + 2 * len(rows)

    def add(self, rows):
        calls, spans = [], []
        for r in rows:
            code, span = line_code(r)
            spans.append(span)
            if code is None:
                calls.append(BANK_BASE)       # the shared RET
                continue
            if code not in self.lines:
                self.lines[code] = self.addr()
                self.img += code
            calls.append(self.lines[code])
        prog = self.addr()
        for c in calls:
            self.img += bytes((0xCD, NL_VECTOR & 255, NL_VECTOR >> 8, 0xCD, c & 255, c >> 8))
        self.img.append(0xC9)
        span_addr = self.addr()
        for s, n in spans:
            self.img += bytes((s, n))
        return prog, span_addr


def data_frame(rows):
    out = bytearray()
    for st, nl, no, nr, bs in frame_lines(rows):
        out += bytes([st, nl, no, nr] + bs)
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("sheet")
    ap.add_argument("out", help="output prefix (path without extension)")
    ap.add_argument("--prefix", required=True)
    ap.add_argument("--size", default="32x48")
    ap.add_argument("--mirror-from", type=int, default=-1)
    ap.add_argument("--banks", default="4,7", help="banks for compiled code")
    ap.add_argument("--data-bank", type=int, default=6)
    args = ap.parse_args()

    fw, fh = (int(v) for v in args.size.split("x"))
    img = Image.open(args.sheet).convert("RGBA")
    pens = to_pens(img, False, sprite=True)
    frames = []
    for fy in range(img.height // fh):
        for fx in range(img.width // fw):
            frames.append([pens[fy * fh + y][fx * fw:(fx + 1) * fw] for y in range(fh)])
    if args.mirror_from >= 0:
        frames += [[list(reversed(r)) for r in f] for f in frames[args.mirror_from:]]

    # unique frames
    uniq, index = [], []
    for f in frames:
        key = tuple(tuple(r) for r in f)
        if key in uniq:
            index.append(uniq.index(key))
        else:
            index.append(len(uniq))
            uniq.append(key)

    banks = [Bank(int(b)) for b in args.banks.split(",")]
    data_img = bytearray()
    placed = []
    bi = 0
    for f in uniq:
        f = [list(r) for r in f]
        while len(banks[bi].img) + banks[bi].need(f) > BANK_SIZE:
            bi += 1
            if bi == len(banks):
                sys.exit("compiled sprites do not fit in the banks")
        prog, span = banks[bi].add(f)
        data_addr = BANK_BASE + len(data_img)
        data_img += data_frame(f)
        placed.append((banks[bi].num, prog, span, data_addr))
    if len(data_img) > BANK_SIZE:
        sys.exit("span data does not fit in its bank")

    for bk in banks:
        if os.path.exists(f"{args.out}_{bk.num}.dat"):
            os.remove(f"{args.out}_{bk.num}.dat")
        if len(bk.img) > 1:            # unused bank: no file
            with open(f"{args.out}_{bk.num}.dat", "wb") as f:
                f.write(bk.img)
    with open(f"{args.out}_{args.data_bank}.dat", "wb") as f:
        f.write(data_img)
    images = {bk.num: bk.img for bk in banks}
    banks = [bk.num for bk in banks]

    p = args.prefix
    with open(f"{args.out}.asm", "w", encoding="utf-8") as f:
        f.write(f"; generated by tools/spritec.py from {args.sheet}\n")
        f.write(f"; {len(frames)} frames, {len(uniq)} unique; banks: "
                + ", ".join(f"{b}={len(images[b])}" for b in banks)
                + f", data {args.data_bank}={len(data_img)}\n")
        f.write(f"{p}_frames:\n")
        for i in range(len(frames)):
            f.write(f"\tdw {p}_d{index[i]}\n")
        for u, (bank, ent, span, data) in enumerate(placed):
            f.write(f"{p}_d{u}:\tdb #{0xC0 + bank:02X} : dw #{ent:04X},#{span:04X} : "
                    f"db #{0xC0 + args.data_bank:02X} : dw #{data:04X}\n")
    print(f"{len(frames)} frames, {len(uniq)} unique; "
          + ", ".join(f"bank {b}: {len(images[b])}" for b in banks)
          + f"; data bank {args.data_bank}: {len(data_img)}", file=sys.stderr)


if __name__ == "__main__":
    main()
