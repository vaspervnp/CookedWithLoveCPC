#!/usr/bin/env python3
"""Cycle profiler: runs the game binary on a Z80 emulator (the z80 package)
and reports where the time of a frame goes.

The build must have the debug band (make en EXTRA="-DDEBUG=1 -DDBGPOS=1 ...").
The binary and the sprite banks are loaded as from the disk (load_banks is
skipped), the gate array RAM banking is emulated, interrupts are not: the main
loop is let through at once (nxt_ready = 0) with 2 VBLs per frame.

Output: T-states per render stage (restore, sync, draw, build) averaged over
the frames, and a PC-sampled profile by routine (code in the sprite banks is
"compiled sprites"). T-states, not CPC time (the CPC rounds every instruction
up to whole microseconds = 4 T).

Usage: z80prof.py [--frames N] [--skip N] [--top N]
"""

import argparse
import bisect
import os
import re

import z80

from cpc import ROOT

BUILD = os.path.join(ROOT, "build")
SAMPLE = 97                       # T-states between PC samples


def load_symbols():
    syms = []
    for line in open(os.path.join(BUILD, "cwl_en.sym")):
        m = re.match(r"(\S+) #([0-9A-F]+) B0", line)
        if m and "." not in m[1]:
            syms.append((int(m[2], 16), m[1].lower()))
    syms.sort()
    return syms


class CPC:
    def __init__(self):
        self.m = z80.Z80Machine()
        self.base = bytearray(0x10000)
        self.banks = {n: bytearray(0x4000) for n in range(4, 8)}
        self.mapped = None            # bank at &4000 (None = base RAM)
        self.vsync = 0
        bin_ = open(os.path.join(BUILD, "cwl_en.bin"), "rb").read()
        self.base[0x100:0x100 + len(bin_)] = bin_
        for n in (4, 6, 7):
            p = os.path.join(BUILD, f"spr_{n}.dat")
            if os.path.exists(p):
                d = open(p, "rb").read()
                self.banks[n][:len(d)] = d
        self.m.set_memory_block(0, bytes(self.base))
        self.m.set_output_callback(self.out)
        self.m.set_input_callback(self.inp)

    def map(self, bank):
        if bank == self.mapped:
            return
        mem = self.m.memory
        cur = self.banks[self.mapped] if self.mapped is not None else None
        if cur is not None:
            cur[:] = mem[0x4000:0x8000]
        else:
            self.base[0x4000:0x8000] = mem[0x4000:0x8000]
        src = self.banks[bank] if bank is not None else self.base[0x4000:0x8000]
        self.m.set_memory_block(0x4000, bytes(src))
        self.mapped = bank

    def out(self, port, value):
        if (port >> 8) == 0x7F and value & 0xC0 == 0xC0:     # RAM config
            cfg = value & 7
            self.map(cfg if cfg >= 4 else None)

    def inp(self, port):
        if (port >> 8) == 0xF5:                              # PPI B: VSYNC toggles
            self.vsync ^= 1
            return 0xFE | self.vsync
        return 0xFF


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--frames", type=int, default=40)
    ap.add_argument("--skip", type=int, default=10, help="frames run before measuring")
    ap.add_argument("--top", type=int, default=25)
    args = ap.parse_args()

    syms = load_symbols()
    addr = {n: a for a, n in syms}
    keys = [a for a, _ in syms]
    cpc = CPC()
    m = cpc.m
    # skip load_banks (firmware): the call at start
    start = addr["start"]
    for i in range(3):
        m.memory[start + i] = 0
    m.pc = start
    m.sp = 0x100
    for a in (addr["main_loop"], addr["prof_start"], addr["prof_mark"]):
        m.set_breakpoint(a)

    ticks = 0
    frame = -1
    stage_t = None
    stages = []
    hist = {}
    nfc, nnr = addr["frame_count"], addr["nxt_ready"]

    def name(pc):
        if 0x4000 <= pc < 0x8000 and cpc.mapped is not None:
            return "(compiled sprites)"
        i = bisect.bisect_right(keys, pc) - 1
        return syms[i][1] if i >= 0 else "?"

    while frame < args.skip + args.frames:
        m.ticks_to_stop = SAMPLE
        ev = m.run()
        used = SAMPLE - m.ticks_to_stop if not ev & 1 else SAMPLE
        ticks += used
        pc = m.pc
        measuring = args.skip <= frame < args.skip + args.frames
        if ev & 2:                                # breakpoint
            if pc == addr["main_loop"]:
                frame += 1
                m.memory[nnr] = 0
                m.memory[nfc] = (m.memory[nfc] + 2) & 255
            elif pc == addr["prof_start"]:
                stage_t = [ticks]
            elif pc == addr["prof_mark"] and stage_t is not None:
                stage_t.append(ticks)
                if len(stage_t) == 5 and measuring:
                    stages.append([b - a for a, b in zip(stage_t, stage_t[1:])])
            m.clear_breakpoint(pc)                # step over it
            m.ticks_to_stop = 1
            m.run()
            ticks += 1
            m.set_breakpoint(pc)
        elif measuring:
            n = name(pc)
            hist[n] = hist.get(n, 0) + used

    if stages:
        avg = [sum(s[k] for s in stages) / len(stages) for k in range(4)]
        tot = sum(avg)
        print(f"{len(stages)} frames, T-states per render: "
              + ", ".join(f"{n} {v:,.0f}" for n, v in zip(("restore", "sync", "draw", "build"), avg))
              + f"; total {tot:,.0f} (~{tot / 4 / 3333:.1f}/300 s at 1 T = 1/4 us, more on a CPC)")
    tot = sum(hist.values()) or 1
    print(f"profile ({tot / max(1, args.frames):,.0f} T per frame):")
    for n, v in sorted(hist.items(), key=lambda kv: -kv[1])[:args.top]:
        print(f"  {v * 100 / tot:5.1f}%  {v / args.frames:9,.0f}  {n}")


if __name__ == "__main__":
    main()
