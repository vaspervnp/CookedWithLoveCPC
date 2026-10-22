#!/bin/bash
# The expansion bought from a real evening, in CPCEC (~2 min): Easy, a
# 3-minute day with 400 to start (TEST_MODE / TEST_MONEY), nobody served;
# in the evening up buys it (300), the next day Bill walks up into it.
# Checks RAM dumps (tools/cpcram.py). Keys: 0 up, 76 fire; VBLs.
set -e
cd "$(dirname "$0")/.."
OUT=build/cpcec/exp
mkdir -p build/cpcec
make -s en OVLEXTRA=-DTITLE_WAIT=50 EXTRA="-DDAY_MIN=3 -DTEST_MONEY=400" >/dev/null
cp build/cwl_en.sym $OUT.sym
K="76:1250-1258,76:1300-1308,0:5200-5208,76:5600-5608,76:5800-5808,0:5900-6500"
rm -f $OUT*.ram
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy CPCEC_KEYS="$K" \
	CPCEC_DUMPS="5150,5450,6500" CPCEC_PREFIX=$OUT CPCEC_EXIT=6500 \
	timeout 600 "${CPCEC:-$HOME/tools/cpcec/cpcec}" -S -r0 -O -m2 -k1 -g0 build/cwl_en.dsk >/dev/null 2>&1 || true
make -s en >/dev/null
python3 - "$OUT" <<'PY'
import sys
sys.path.insert(0, "tools")
from cpcram import Ram
o = sys.argv[1]
ok = True
def check(frame, name, want, n=1, word=False, f=None):
    global ok
    got = Ram(f"{o}{frame:05d}.ram", o + ".sym").get(name, n, word)
    if f: got = f(got)
    good = got == want
    ok &= good
    print(f"{'ok  ' if good else 'FAIL'} {frame:5d} {name:10s} {got}" + ("" if good else f" (want {want})"))
check(5150, "sv_money", 350, word=True)
check(5150, "tb_busy", [64] * 6, 6)
check(5450, "sv_exp", 1)
check(5450, "sv_money", 50, word=True)
check(5450, "tb_busy", [0] * 6, 6)
check(6500, "bill_x", True, 5, f=lambda v: v[3] + 256 * v[4] < 100)	# feet y < 100: in the room
sys.exit(0 if ok else 1)
PY
