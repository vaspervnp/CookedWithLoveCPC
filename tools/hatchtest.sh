#!/bin/bash
# Hard: portions made at the pass during the day take their ingredients
# from the hatch, in CPCEC (~30 s). TEST_FILL (8 portions of each, the hatch
# full), Bill starts at the pass: fire (the menu), up (a dolmades: veg,
# meat, grain), right twice, up (dish 2: meat, grain, dairy).
set -e
cd "$(dirname "$0")/.."
. tools/scenario.sh
OUT=build/cpcec/hatch
mkdir -p build/cpcec
make -s $CWL_LANG EXTRA="-DTEST_FILL=1 -DTEST_MODE=2 -DBILL_X0=296 -DBILL_Y0=396" >/dev/null
cp build/cwl_$CWL_LANG.sym $OUT.sym
scenario $OUT "76:1000-1008,0:1100-1108,1:1200-1208,1:1250-1258,0:1300-1308" "1150,1350" 1350 300
make -s $CWL_LANG >/dev/null
python3 - "$OUT" <<'PY'
import sys
sys.path.insert(0, "tools")
from cpcram import dump
o = sys.argv[1]
ok = True
for frame, cook, hatch in ((1150, [1, 0, 0], [8, 8, 8, 9, 9]), (1350, [1, 0, 1], [8, 7, 7, 8, 9])):
    r = dump(o, frame)
    got = (r.get("sv_cook", 3), r.get("st_hatch", 5))
    good = got == (cook, hatch)
    ok &= good
    print(f"{'ok  ' if good else 'FAIL'} {frame:5d} cooking, hatch {got}" + ("" if good else f" (want {(cook, hatch)})"))
sys.exit(0 if ok else 1)
PY
