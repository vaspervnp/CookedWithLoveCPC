#!/bin/bash
# Headless CPCEC (accurate emulator, locally patched with frame shots).
# Usage: tools/cpcecshot.sh <disk.dsk> <outprefix> <frames "f1,f2,..."> [crtc type]
# Writes <outprefix>NNNNN.bmp for each frame, then exits.
DSK="$(realpath "$1")"; PFX="$2"; FR="$3"; CRTC="${4:-0}"
LAST="${FR##*,}"
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy CPCEC_SHOTS="$FR" CPCEC_PREFIX="$PFX" CPCEC_EXIT="$LAST" \
	timeout 120 "${CPCEC:-$HOME/tools/cpcec/cpcec}" -S -r0 -O -m2 -k1 -g"$CRTC" "$DSK" >/dev/null 2>&1
