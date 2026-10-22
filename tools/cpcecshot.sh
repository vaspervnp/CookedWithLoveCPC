#!/bin/bash
# Headless CPCEC (accurate emulator, locally patched with frame shots).
# Usage: tools/cpcecshot.sh <disk.dsk> <outprefix> <frames "f1,f2,..."> [crtc type]
# Writes <outprefix>NNNNN.bmp for each frame, then exits (CPCEC_TIMEOUT: seconds,
# default 120, for late frames). Also passed on: CPCEC_KEYS="key:from-to,..."
# (keys held, key = matrix line * 8 + bit); CPCEC_WAV=file.wav needs a run
# without -S.
DSK="$(realpath "$1")"; PFX="$2"; FR="$3"; CRTC="${4:-0}"
LAST="${FR##*,}"
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy CPCEC_SHOTS="$FR" CPCEC_PREFIX="$PFX" CPCEC_EXIT="$LAST" \
	timeout "${CPCEC_TIMEOUT:-120}" "${CPCEC:-$HOME/tools/cpcec/cpcec}" -S -r0 -O -m2 -k1 -g"$CRTC" "$DSK" >/dev/null 2>&1
