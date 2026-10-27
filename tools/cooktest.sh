#!/bin/bash
# The hired cook in CPCEC (~1 min): Medium (TEST_MODE=1), a cook and a
# waiter (TEST_XP=24), the groups sit by themselves (TEST_FILL); Bill at
# table 6 takes its single customer's order (cod, TEST_DISH: a stove); the
# cook walks to a stove, cooks it, brings it to the pass
# (src/game/cook.asm); the waiter serves it. The player is Liberty from
# 1700 (the camera in the kitchen: SHOTS=1950,2150 shows him there).
# Checks RAM dumps (tools/cpcram.py).
set -e
cd "$(dirname "$0")/.."
. tools/scenario.sh
OUT=build/cpcec/cook
mkdir -p build/cpcec
make -s $CWL_LANG EXTRA="-DTEST_FILL=1 -DTEST_MODE=1 -DTEST_XP=24 -DTEST_DISH=1 -DBILL_X0=56 -DBILL_Y0=366" >/dev/null
cp build/cwl_$CWL_LANG.sym $OUT.sym
scenario $OUT "76:1600-1608,47:1700-1708" "${DUMPS:-1550,1650,2050,2400,2750,3100}" ${LAST:-3100} 400
make -s $CWL_LANG >/dev/null
[ -n "$DUMPS" ] && exit 0
python3 - "$OUT" <<'PY'
import sys
sys.path.insert(0, "tools")
from cpcram import dump
o = sys.argv[1]
ok = True
def check(frame, what, f, want):
    global ok
    r = dump(o, frame)
    c = r.get("ck_rec", 5)
    got = f(r, (c[0] + 256 * c[1], c[3] + 256 * c[4]), r.get("groups", 32)[16:32])
    good = got == want
    ok &= good
    print(f"{'ok  ' if good else 'FAIL'} {frame:5d} {what:22s} {got}" + ("" if good else f" (want {want})"))
check(1550, "at the pass", lambda r, p, g: (r.get("ck_rec", 11)[10], p), (1, (328, 408)))
check(1650, "ordered: to a stove", lambda r, p, g: (r.get("ck_rec", 11)[10], g[0]), (2, 6))
check(2050, "there, cooking", lambda r, p, g: (r.get("ck_rec", 11)[10], r.get("ck_stn"), r.get("ks_slots", 2)[0]), (4, 0, 1))
check(2400, "back with it", lambda r, p, g: (r.get("ck_rec", 11)[10], r.get("ck_carry", 2)), (3, [2, 1]))
check(2750, "at the pass: waiter", lambda r, p, g: (r.get("ck_rec", 11)[10], r.get("ck_carry", 2)[0], r.get("wt_state"), g[0]), (1, 0, 2, 8))
check(3100, "served", lambda r, p, g: g[0], 9)
sys.exit(0 if ok else 1)
PY
