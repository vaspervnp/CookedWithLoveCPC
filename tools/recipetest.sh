#!/bin/bash
# A recipe bought in the evening, in CPCEC (~3.5 min): Easy, 3-minute days,
# 150 to start (TEST_MONEY), nobody served. The first evening (100 after
# the rent) down buys the curry (100); the morning right, fire: it replaces
# the cod (dish 1) in all the tables. The next evening the money is gone:
# bankrupt, fire: a new game, the first menu again (src/ovl/menu.asm).
# Checks RAM dumps (tools/cpcram.py). Keys: 1 right, 2 down, 76 fire; VBLs.
set -e
cd "$(dirname "$0")/.."
. tools/scenario.sh
OUT=build/cpcec/recipe
mkdir -p build/cpcec
make -s en OVLEXTRA=-DTITLE_WAIT=50 EXTRA="-DDAY_MIN=3 -DTEST_MONEY=150" >/dev/null
cp build/cwl_en.sym $OUT.sym
scenario $OUT "76:1250-1258,76:1300-1308,2:5200-5208,76:5600-5608,1:5700-5708,76:5800-5808,76:5900-5908,76:9500-9508" \
	"5150,5300,5850,9250,9600" 9600 900
make -s en >/dev/null
python3 - "$OUT" <<'PY'
import sys
sys.path.insert(0, "tools")
from cpcram import dump
o = sys.argv[1]
ok = True
def check(frame, what, f, want):
    global ok
    got = f(dump(o, frame))
    good = got == want
    ok &= good
    print(f"{'ok  ' if good else 'FAIL'} {frame:5d} {what:22s} {got}" + ("" if good else f" (want {want})"))
check(5150, "evening: money", lambda r: r.get("sv_money", 1, True), 100)
check(5300, "bought: money, new", lambda r: (r.get("sv_money", 1, True), r.get("rc_new")), (0, 1))
check(5850, "curry for the cod", lambda r: (r.get("rc_cnt"), r.get("rc_log"), r.get("dish_price", 9)[1::7],
                                             r.get("dish_ticks", 9, True)[1::7], r.get("dish_ink", 2)[1], r.get("rc_ink")),
      (1, 1, [12, 8], [375, 225], 8, 13))
check(9250, "bankrupt", lambda r: r.get("sv_phase"), 4)
check(9600, "new game: first menu", lambda r: (r.get("rc_cnt"), r.get("sv_money", 1, True), r.get("dish_price", 9)[1::7],
                                               r.get("dish_ticks", 9, True)[1::7], r.get("dish_ink", 2)[1], r.get("rc_ink")),
      (0, 150, [8, 12], [225, 375], 13, 8))
sys.exit(0 if ok else 1)
PY
