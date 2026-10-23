#!/usr/bin/env python3
"""Read the game's variables from a CPCEC RAM dump (CPCEC_DUMPS: 128K, the
base 64K then banks 4-7), with the addresses of the rasm symbol file.
&4000-&7FFF is read from bank 5 (the game's code and variables there).

Usage: cpcram.py <dump.ram> <cwl.sym> name[:count[:w]] ...
  (count values from the symbol on, bytes or with :w words)
As a module: Ram(dump, sym).get("name", n=1, word=False)
"""

import os
import sys


class Ram:
    def __init__(self, dump, symfile):
        self.ram = open(dump, "rb").read()
        self.sym = {}
        for line in open(symfile):
            p = line.split()
            if len(p) >= 2 and p[1].startswith("#"):
                self.sym[p[0].lower()] = int(p[1][1:], 16)

    def byte(self, a):
        if 0x4000 <= a < 0x8000:
            return self.ram[0x14000 + a - 0x4000]
        return self.ram[a]

    def get(self, name, n=1, word=False):
        a = self.sym[name.lower()]
        if word:
            v = [self.byte(a + 2 * i) | self.byte(a + 2 * i + 1) << 8 for i in range(n)]
        else:
            v = [self.byte(a + i) for i in range(n)]
        return v if n > 1 else v[0]


def dump(prefix, frame, sym=None):
    """The dump of a scenario (tools/scenario.sh) at VBL frame + BOOT."""
    boot = int(os.environ.get("BOOT", "0"))
    return Ram(f"{prefix}{frame + boot:05d}.ram", sym or prefix + ".sym")


def main():
    r = Ram(sys.argv[1], sys.argv[2])
    for arg in sys.argv[3:]:
        f = arg.split(":")
        n = int(f[1]) if len(f) > 1 and f[1] else 1
        print(f"{f[0]:12s} {r.get(f[0], n, len(f) > 2)}")


if __name__ == "__main__":
    main()
