#!/bin/bash
# Two hired cooks in CPCEC (~1 min): Medium, both cooks and both waiters
# (TEST_XP=216), the groups sit by themselves (TEST_FILL); Bill takes the
# orders at tables 6 and 7 (cod, TEST_DISH: a stove each); the cooks walk to
# two stoves (not the same: ck_taken), cook, bring them to the pass
# (src/game/cook.asm); the waiters serve them. Checks RAM dumps
# (tools/cpcram.py).
set -e
cd "$(dirname "$0")/.."
. tools/scenario.sh
OUT=build/cpcec/cook2
mkdir -p build/cpcec
make -s en EXTRA="-DTEST_FILL=1 -DTEST_MODE=1 -DTEST_XP=216 -DTEST_DISH=1 -DBILL_X0=56 -DBILL_Y0=366" >/dev/null
cp build/cwl_en.sym $OUT.sym
scenario $OUT "76:1600-1608,1:1650-1800,76:1830-1838" "1650,2150,2450,2950,3550" 3550 400
make -s en >/dev/null
python3 - "$OUT" <<'PY'
import sys
sys.path.insert(0, "tools")
from cpcram import dump
o = sys.argv[1]
ok = True
def check(frame, what, f, want):
    global ok
    r = dump(o, frame)
    c = [r.get(n, 26) for n in ("ck_rec", "ck2_rec")]
    g = r.get("groups", 144)
    got = f([x[10] for x in c], [x[25] for x in c], [x[21] for x in c], r.get("ks_slots", 12)[::6],
            {g[16 * i + 3]: g[16 * i] for i in range(9) if g[16 * i]})
    good = got == want
    ok &= good
    print(f"{'ok  ' if good else 'FAIL'} {frame:5d} {what:22s} {got}" + ("" if good else f" (want {want})"))
check(1650, "to two stoves", lambda s, n, c, k, t: (s, n), ([2, 2], [0, 1]))
check(2150, "cooking both", lambda s, n, c, k, t: (s, k), ([4, 4], [1, 1]))
check(2450, "back with them", lambda s, n, c, k, t: (s, c), ([3, 3], [2, 4]))
check(2950, "at the pass: waiters", lambda s, n, c, k, t: (s, c, t[6], t[7]), ([1, 1], [0, 0], 8, 8))
check(3550, "served", lambda s, n, c, k, t: (t[6], t[7]), (9, 9))
sys.exit(0 if ok else 1)
PY
