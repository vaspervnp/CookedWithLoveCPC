#!/bin/bash
# The expansions bought from a real evening, in CPCEC (~2 min): Easy, a
# 3-minute day with 700 to start (TEST_MONEY), nobody served; in the
# evening up buys the room (300), up again the kitchen (250: its wall row
# 31 becomes floor), the next day Bill walks up into the room.
# Checks RAM dumps (tools/cpcram.py). Keys: 0 up, 76 fire; VBLs.
set -e
cd "$(dirname "$0")/.."
. tools/scenario.sh
OUT=build/cpcec/exp
mkdir -p build/cpcec
make -s en OVLEXTRA=-DTITLE_WAIT=50 EXTRA="-DDAY_MIN=3 -DTEST_MONEY=700" >/dev/null
cp build/cwl_en.sym $OUT.sym
K="76:1250-1258,76:1300-1308,0:5200-5208,0:5300-5308,76:5600-5608,76:5800-5808,0:5900-6500"
scenario $OUT "$K" "5150,5250,5450,6500" 6500 600
make -s en >/dev/null
python3 - "$OUT" <<'PY'
import sys
sys.path.insert(0, "tools")
from cpcram import dump
o = sys.argv[1]
ok = True
def check(frame, name, want, n=1, word=False, f=None):
    global ok
    got = dump(o, frame).get(name, n, word)
    if f: got = f(got)
    good = got == want
    ok &= good
    print(f"{'ok  ' if good else 'FAIL'} {frame:5d} {name:10s} {got}" + ("" if good else f" (want {want})"))
check(5150, "sv_money", 650, word=True)
check(5150, "tb_busy", [64] * 6, 6)
check(5250, "sv_exp", 1)
check(5250, "sv_money", 350, word=True)
check(5250, "tb_busy", [0] * 6, 6)
check(5450, "sv_exp", 3)
check(5450, "sv_money", 100, word=True)
kitchen = lambda v: v[31 * 40 + 20] == v[30 * 40 + 20]	# the wall's row as the floor above
check(5150, "map_data", False, 42 * 40, f=kitchen)
check(5450, "map_data", True, 42 * 40, f=kitchen)
check(6500, "bill_x", True, 5, f=lambda v: v[3] + 256 * v[4] < 100)	# feet y < 100: in the room
sys.exit(0 if ok else 1)
PY
