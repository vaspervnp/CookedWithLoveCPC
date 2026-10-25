#!/usr/bin/env python3
"""A standard CPCEMU disc image (MV - CPCEMU, as iDSK makes it) to the
EXTENDED CPC DSK format, in place: the game writes its save (SAVE.DAT,
src/ovl/save.asm) to the disc, which the emulators keep in an extended
image. The tracks stay as they are; the header gets the size of each, the
sector infos the length of their data.

    tools/edsk.py <image.dsk>"""
import sys


def convert(data):
    if data[:8] != b"MV - CPC":
        if data[:8] == b"EXTENDED":
            return data
        sys.exit("not a CPCEMU disc image")
    tracks, sides = data[0x30], data[0x31]
    size = data[0x32] | data[0x33] << 8
    if size % 256:
        sys.exit(f"track size {size}: not a multiple of 256")
    head = bytearray(256)
    head[:34] = b"EXTENDED CPC DSK File\r\nDisk-Info\r\n"
    head[34:48] = b"CWL edsk.py".ljust(14)
    head[0x30], head[0x31] = tracks, sides
    head[0x34:0x34 + tracks * sides] = bytes([size >> 8]) * (tracks * sides)
    out = bytearray(head)
    for t in range(tracks * sides):
        tr = bytearray(data[256 + t * size:256 + (t + 1) * size])
        if tr[:10] != b"Track-Info":
            sys.exit(f"track {t}: no Track-Info")
        n, count = tr[0x14], tr[0x15]
        for s in range(count):
            e = 0x18 + 8 * s
            tr[e + 6:e + 8] = (128 << n).to_bytes(2, "little")
        out += tr
    return bytes(out)


if __name__ == "__main__":
    path = sys.argv[1]
    data = open(path, "rb").read()
    open(path, "wb").write(convert(data))
