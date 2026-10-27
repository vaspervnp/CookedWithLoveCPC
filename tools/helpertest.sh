#!/bin/bash
# The storage helper in CPCEC (~1 min): Hard (TEST_MODE=2), a helper
# (TEST_XP=32), a box of vegetables at the door and none of them at the
# hatch (TEST_DOOR, TEST_FILL); with no keys he takes the box to the
# nearest shelf, then 5 units from there to the hatch
# (src/game/helper.asm). The player is Blossom from 1000 (the camera in
# the storage). Checks RAM dumps (tools/cpcram.py).
set -e
cd "$(dirname "$0")/.."
. tools/scenario.sh
OUT=build/cpcec/helper
mkdir -p build/cpcec
make -s $CWL_LANG EXTRA="-DTEST_FILL=1 -DTEST_MODE=2 -DTEST_XP=32 -DTEST_DOOR=1" >/dev/null
cp build/cwl_$CWL_LANG.sym $OUT.sym
scenario $OUT "47:900-908,47:1000-1008" "${DUMPS:-1000,1300,1500,2100,2400}" ${LAST:-2400} 400
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
    h = r.get("hl_rec", 11)
    got = f(r, (h[0] + 256 * h[1], h[3] + 256 * h[4]), h[10])
    good = got == want
    ok &= good
    print(f"{'ok  ' if good else 'FAIL'} {frame:5d} {what:22s} {got}" + ("" if good else f" (want {want})"))
check(1000, "to the door", lambda r, p, s: (s, r.get("hl_kind")), (2, 2))
check(1300, "on his way", lambda r, p, s: (s, p[0]), (2, 616))
check(1500, "a box: back", lambda r, p, s: (s, r.get("hl_carry", 2), r.get("st_door", 1)), (3, [1, 5], 0))
check(2100, "on the shelf", lambda r, p, s: (r.get("hl_kind"), r.get("st_stock", 1)), (0, 35))
check(2400, "5 at the hatch, home", lambda r, p, s: (s, r.get("hl_carry", 1), r.get("st_stock", 1), r.get("st_hatch", 1), p), (1, 0, 30, 5, (488, 107)))
sys.exit(0 if ok else 1)
PY
