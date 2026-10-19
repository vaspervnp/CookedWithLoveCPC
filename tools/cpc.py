"""Shared Amstrad CPC helpers: palette, colours, Mode 0 encoding."""

import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PALETTE_FILE = os.path.join(ROOT, "data", "palette.txt")

# Firmware colour number -> gate array hardware colour (with bit 6 set).
FW_TO_HW = [
    0x54, 0x44, 0x55, 0x5C, 0x58, 0x5D, 0x4C, 0x45, 0x4D,
    0x56, 0x46, 0x57, 0x5E, 0x40, 0x5F, 0x4E, 0x47, 0x4F,
    0x52, 0x42, 0x53, 0x5A, 0x59, 0x5B, 0x4A, 0x43, 0x4B,
]

_LEVEL = (0x00, 0x80, 0xFF)


def fw_to_rgb(fw):
    """Firmware colour = 9*G + 3*R + B, each component 0..2."""
    g, rest = divmod(fw, 9)
    r, b = divmod(rest, 3)
    return (_LEVEL[r], _LEVEL[g], _LEVEL[b])


def load_palette(path=PALETTE_FILE):
    """Return (pens, border) where pens is a list of (fw, name) for pens 0..15."""
    pens = {}
    border = 0
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.split("#", 1)[0].strip()
            if not line:
                continue
            parts = line.split()
            if parts[0] == "border":
                border = int(parts[1])
                continue
            pens[int(parts[0])] = (int(parts[1]), parts[2] if len(parts) > 2 else "")
    if sorted(pens) != list(range(16)):
        raise ValueError(f"{path}: need exactly pens 0..15")
    return [pens[i] for i in range(16)], border


def mode0_byte(left, right):
    """Pack two Mode 0 pens (0..15) into one screen byte."""
    b = 0
    # pixel bit -> screen bit for left pixel; right pixel is one bit lower.
    for bit, pos in ((0, 7), (1, 3), (2, 5), (3, 1)):
        if left & (1 << bit):
            b |= 1 << pos
        if right & (1 << bit):
            b |= 1 << (pos - 1)
    return b
