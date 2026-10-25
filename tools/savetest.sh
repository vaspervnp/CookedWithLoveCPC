#!/bin/bash
# The save in CPCEC (~2 min; the disc read-write: CPCEC_RW, a local patch):
# Easy, a 3-minute day with 700 (TEST_MONEY), saving on (SAVE_TEST); in the
# evening up buys the room, fire: the next morning writes SAVE.DAT. Then
# the same disc again: right three times at the modes is CONTINUE, fire:
# day 2, the room bought, 350 (src/ovl/save.asm). Checks the file on the
# disc (iDSK) and RAM dumps (tools/cpcram.py). SHOTS=1200: the modes' row.
set -e
cd "$(dirname "$0")/.."
. tools/scenario.sh
OUT=build/cpcec/save
mkdir -p build/cpcec
make -s en OVLEXTRA="-DTITLE_WAIT=50 -DSAVE_TEST=1" EXTRA="-DDAY_MIN=3 -DTEST_MONEY=700" >/dev/null
cp build/cwl_en.sym $OUT.sym
export CPCEC_RW=1
scenario ${OUT}a "76:1250-1258,76:1300-1308,0:5200-5208,76:5600-5608" "5700" 6000 300
rm -f build/SAVE.DAT
(cd build && iDSK cwl_en.dsk -g SAVE.DAT >/dev/null) && mv build/SAVE.DAT $OUT.dat
scenario $OUT "1:1100-1108,1:1130-1138,1:1160-1168,76:1250-1258" "1200,1400" 1400 300
make -s en >/dev/null
python3 - "$OUT" <<'PY'
import sys
sys.path.insert(0, "tools")
from cpcram import dump
o = sys.argv[1]
ok = True
def check(what, got, want):
    global ok
    good = got == want
    ok &= good
    print(f"{'ok  ' if good else 'FAIL'} {what:24s} {got}" + ("" if good else f" (want {want})"))
s = open(o + ".dat", "rb").read()
check("SAVE.DAT: magic", s[:4], b"CWL\x01")
check("money, day, mode, exp", (s[4] + 256 * s[5], s[6], s[7], s[8]), (350, 1, 0, 1))
r = dump(o, 1200)
check("1200 CONTINUE chosen", r.get("sv_mode"), 3)
r = dump(o, 1400)
check("1400 day 2, as saved", (r.get("sv_day"), r.get("sv_exp"), r.get("sv_money", 1, True), r.get("sv_mode")), (2, 1, 350, 0))
check("1400 the room's tables", r.get("tb_busy", 6), [0] * 6)
sys.exit(0 if ok else 1)
PY
