#!/bin/bash
# Two hired waiters in CPCEC (~1 min): Easy, both (TEST_XP=72), the groups
# sit by themselves (TEST_FILL); Bill takes the orders at tables 6 and 7
# (cod, TEST_DISH); the kitchen cooks them, the first waiter takes table
# 6's at the pass, the second (at home above him) table 7's; both serve,
# walk back (src/game/waiter.asm). Checks RAM dumps (tools/cpcram.py).
set -e
cd "$(dirname "$0")/.."
. tools/scenario.sh
OUT=build/cpcec/waiter2
mkdir -p build/cpcec
make -s en EXTRA="-DTEST_FILL=1 -DTEST_XP=72 -DTEST_DISH=1 -DBILL_X0=56 -DBILL_Y0=366" >/dev/null
cp build/cwl_en.sym $OUT.sym
scenario $OUT "76:1600-1608,1:1650-1773,76:1800-1808" "1550,1950,2150,2650,3150" 3150 400
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
    w = [r.get(n, 24) for n in ("wt_rec", "wt2_rec")]
    st = [(x[10], x[21], x[22]) for x in w]
    pos = [(x[0] + 256 * x[1], x[3] + 256 * x[4]) for x in w]
    g = r.get("groups", 144)
    got = f(st, pos, {g[16 * i + 3]: g[16 * i] for i in range(9) if g[16 * i]})
    good = got == want
    ok &= good
    print(f"{'ok  ' if good else 'FAIL'} {frame:5d} {what:22s} {got}" + ("" if good else f" (want {want})"))
check(1550, "at the pass", lambda s, p, t: ([x[0] for x in s], p), ([1, 1], [(296, 408), (296, 392)]))
check(1950, "the first: table 6", lambda s, p, t: (s[0], s[1][0], t[6]), ((2, 2, 6), 1, 8))
check(2150, "the second: table 7", lambda s, p, t: (s[1], t[7]), ((2, 4, 7), 8))
check(2650, "served, back", lambda s, p, t: ([x[0] for x in s], t[6], t[7]), ([3, 3], 9, 9))
check(3150, "at the pass again", lambda s, p, t: ([x[0] for x in s], [abs(p[0][1] - 408) <= 1, p[1]]), ([1, 1], [True, (296, 392)]))
sys.exit(0 if ok else 1)
PY
