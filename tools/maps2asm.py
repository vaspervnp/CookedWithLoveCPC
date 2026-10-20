#!/usr/bin/env python3
"""Compress a tile map (80x84 tiles of 8x8, one byte each) into 16x16
metatiles of 2x2 tiles, the format the scroll engine reads:

  <out>_map.bin    40x42 metatile indices (row by row)
  <out>_meta.bin   4 planes of 256 bytes, plane k = tile of quadrant k of
                   every metatile (k = 2*(tile row & 1) + (tile column & 1)),
                   so the engine finds a tile with ld l,metatile : ld h,plane
  <out>_tiles.bin  the tile graphics, copied (32 bytes per tile)
  <out>_tilemap.bin the plain tile map again (for the screenshot checkers)

Usage: maps2asm.py <tiles.bin> <tilemap.bin> <out prefix>
"""

import argparse
import sys

MAP_W, MAP_H = 80, 84


def compress(tmap):
    """-> (metatile map, list of metatiles as (tl, tr, bl, br))"""
    metas, index, out = [], {}, bytearray()
    for my in range(MAP_H // 2):
        for mx in range(MAP_W // 2):
            t = (tmap[(2 * my) * MAP_W + 2 * mx], tmap[(2 * my) * MAP_W + 2 * mx + 1],
                 tmap[(2 * my + 1) * MAP_W + 2 * mx], tmap[(2 * my + 1) * MAP_W + 2 * mx + 1])
            if t not in index:
                index[t] = len(metas)
                metas.append(t)
            out.append(index[t])
    return out, metas


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("tiles")
    ap.add_argument("tilemap")
    ap.add_argument("out")
    args = ap.parse_args()
    tiles = open(args.tiles, "rb").read()
    tmap = open(args.tilemap, "rb").read()
    if len(tmap) != MAP_W * MAP_H:
        sys.exit(f"{args.tilemap}: {len(tmap)} bytes, expected {MAP_W * MAP_H}")
    mmap, metas = compress(tmap)
    if len(metas) > 256:
        sys.exit(f"{len(metas)} metatiles (at most 256)")
    planes = bytearray(4 * 256)
    for i, m in enumerate(metas):
        for k in range(4):
            planes[k * 256 + i] = m[k]
    for suffix, data in (("map", mmap), ("meta", planes), ("tiles", tiles), ("tilemap", tmap)):
        with open(f"{args.out}_{suffix}.bin", "wb") as f:
            f.write(data)
    print(f"{args.out}: {len(tiles) // 32} tiles, {len(metas)} metatiles, map {len(mmap)} bytes",
          file=sys.stderr)


if __name__ == "__main__":
    main()
