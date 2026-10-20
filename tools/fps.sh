#!/bin/bash
# Frame rate on CPCEC: builds with the debug band showing the render count
# (DBGFPS) and reads it 200 VBLs apart. Extra defines as arguments, e.g.
#   tools/fps.sh -DCLONES=3
# Leaves a normal build behind.
make -s en EXTRA="-DDEBUG=1 -DDBGPOS=1 -DDBGFPS=1 $*" >/dev/null 2>&1 || exit 1
rm -f build/cpcec/fps*.bmp
tools/cpcecshot.sh build/cwl_en.dsk build/cpcec/fps 1000,1200
python3 - <<'PY'
from PIL import Image
def count(f, shift):
    px = Image.open(f).convert("RGB").load()
    bits = [1 if px[64 + (i + shift) * 8 + 1, 44] != (0, 0, 0) else 0 for i in range(80)]
    sx = int("".join(map(str, bits[0:8])), 2)
    return sx, int("".join(map(str, bits[56:64])), 2), [int("".join(map(str, bits[8 + 8 * k:16 + 8 * k])), 2) for k in (1, 0, 3, 2, 4, 5)]
def read(f):
    for shift in (1, 0):          # odd sx: band one byte to the right
        sx, n, prof = count(f, shift)
        if sx % 2 == shift:
            return n, prof
a, pa = read("build/cpcec/fps01000.bmp")
b, pb = read("build/cpcec/fps01200.bmp")
d = (b - a) % 256
print(f"{d} renders in 200 VBLs = {d / 4:.1f} fps; stages (restore, sync, draw, build; 1/300 s) {pa[:4]} {pb[:4]}; sprites {pb[4]}, clipped path {pb[5]}")
PY
make -s en >/dev/null 2>&1
