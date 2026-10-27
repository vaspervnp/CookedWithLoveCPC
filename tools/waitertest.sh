#!/bin/bash
# The hired waiter in CPCEC (~1 min): Easy, a waiter (TEST_XP=8), the groups
# sit by themselves (TEST_FILL); Bill at table 6 takes its single
# customer's order (cod, TEST_DISH); the kitchen cooks it, the waiter takes
# it at the pass, walks to the table, serves it, walks back
# (src/game/waiter.asm). Checks RAM dumps (tools/cpcram.py).
set -e
cd "$(dirname "$0")/.."
. tools/scenario.sh
OUT=build/cpcec/waiter
mkdir -p build/cpcec
make -s $CWL_LANG EXTRA="-DTEST_FILL=1 -DTEST_XP=8 -DTEST_DISH=1 -DBILL_X0=56 -DBILL_Y0=366" >/dev/null
cp build/cwl_$CWL_LANG.sym $OUT.sym
scenario $OUT "76:1600-1608" "1550,1700,1850,2300,2750" 2750 300
make -s $CWL_LANG >/dev/null
python3 - "$OUT" <<'PY'
import sys
sys.path.insert(0, "tools")
from cpcram import dump
o = sys.argv[1]
ok = True
def check(frame, what, f, want):
    global ok
    r = dump(o, frame)
    w = r.get("wt_rec", 5)
    got = f(r, (w[0] + 256 * w[1], w[3] + 256 * w[4]), r.get("groups", 32)[16:32])
    good = got == want
    ok &= good
    print(f"{'ok  ' if good else 'FAIL'} {frame:5d} {what:22s} {got}" + ("" if good else f" (want {want})"))
check(1550, "at the pass", lambda r, p, g: (r.get("wt_state"), p), (1, (296, 408)))
check(1700, "ordered", lambda r, p, g: g[0], 6)
check(1850, "his: to table 6", lambda r, p, g: (r.get("wt_state"), r.get("wt_grp"), r.get("wt_tab"), g[0]), (2, 2, 6, 8))
check(2300, "served, back", lambda r, p, g: (r.get("wt_state"), r.get("wt_grp"), g[0]), (3, 0, 9))
check(2750, "at the pass again", lambda r, p, g: (r.get("wt_state"), abs(p[0] - 296) <= 1 and abs(p[1] - 408) <= 1), (1, True))
sys.exit(0 if ok else 1)
PY
