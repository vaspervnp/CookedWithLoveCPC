#!/bin/bash
# Headless Caprice32 run: RUN"CWL, wait, take a screenshot, exit.
# Usage: tools/cpcshot.sh <disk.dsk> [delay_keys]
# Screenshot ends up in ~/snap/caprice32/current/screenshots/
set -e
DSK="$(realpath "$1")"
N="${2:-400}"
PAD="$(printf 'z%.0s' $(seq 1 "$N"))"
SCRIPT="$HOME/snap/caprice32/current/cwl_shot.sh"
cat > "$SCRIPT" <<EOS
export SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy
exec timeout 60 "\$SNAP/usr/bin/cap32" --cfg_file="\$SNAP_USER_DATA/etc/cap32.cfg" \\
  -O system.limit_speed=0 -O system.model=2 -O system.ram_size=128 -O video.scr_fps=0 \\
  -a 'run"cwl
${PAD}\\(CAP32_SCRNSHOT)\\(CAP32_EXIT)' "$DSK"
EOS
snap run --shell caprice32.launcher -c 'sh $SNAP_USER_DATA/cwl_shot.sh' >/dev/null 2>&1 || true
ls -t "$HOME/snap/caprice32/current/screenshots/"* | head -1
