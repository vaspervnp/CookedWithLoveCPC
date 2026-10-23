#!/bin/bash
# The Hard storage in CPCEC, with scripted keys (~5 min, in real time):
# day 1 in Hard (portions from the storage), the evening's supplier (2 boxes
# of veg, 1 of meat/fish), day 2: the delivery at 13:00, Blossom takes a box
# at the door, puts it on a shelf, takes 5 units, leaves them at the hatch.
# Checks the variables in RAM dumps (tools/cpcram.py); the EN disc is built
# with DAY_MIN=100 and TITLE_WAIT=50, then built again as usual.
# Keys: line*8+bit (0 up, 1 right, 2 down, 8 left, 47 space, 76 fire), VBLs.
set -e
cd "$(dirname "$0")/.."
. tools/scenario.sh
OUT=build/cpcec/hard
mkdir -p build/cpcec
make -s en OVLEXTRA=-DTITLE_WAIT=50 EXTRA=-DDAY_MIN=100 >/dev/null
cp build/cwl_en.sym $OUT.sym
K=(
	1:1150-1158 1:1200-1208 76:1250-1258		# Medium, Hard, OK
	0:1300-1308 0:1340-1348 0:1380-1388 1:1420-1428 0:1460-1468 0:1500-1508
	76:1560-1568					# 3 + 2 portions, open
	76:8800-8808					# evening: the supplier
	0:8900-8908 0:8950-8958 1:9000-9008 0:9050-9058	# 2 veg, 1 meat
	76:9150-9158 0:9250-9258 76:9300-9308		# day 2: a portion, open
	47:9400-9408 47:9500-9508			# Liberty, Blossom
	1:9800-9900 2:9920-10000 1:10020-10120 2:10140-10260	# to the door: shelf, crate, wall, door
	76:12550-12558					# a box (after 13:00)
	8:12650-12689 0:12720-12900 76:12940-12948	# up to a shelf: put
	76:12980-12988					# take 5
	8:13020-13250 0:13270-13950 2:13990-14029	# left wall, top, down
	76:14110-14118					# the hatch
)

scenario $OUT "$(IFS=,; echo "${K[*]}")" "9100,9700,12500,12600,12960,13000,14150" 14150 900
make -s en >/dev/null
python3 - "$OUT" <<'PY'
import sys
sys.path.insert(0, "tools")
from cpcram import dump
o = sys.argv[1]
ok = True
def check(frame, name, want, n=1, word=False):
    global ok
    got = dump(o, frame).get(name, n, word)
    good = got == want
    ok &= good
    print(f"{'ok  ' if good else 'FAIL'} {frame:5d} {name:10s} {got}" + ("" if good else f" (want {want})"))
check(9100, "st_order", [2, 1, 0, 0, 0], 5)
check(9100, "sv_money", 76, word=True)
check(9100, "st_stock", [27, 25, 25, 30, 30], 5)
check(9700, "ctl_who", 2)
check(12500, "st_door", [2, 1, 0, 0, 0], 5)
check(12600, "st_door", [1, 1, 0, 0, 0], 5)
check(12600, "blo_carry", 1)
check(12960, "st_stock", [31, 24, 24, 30, 30], 5)
check(13000, "blo_units", 5)
check(13000, "st_stock", [26, 24, 24, 30, 30], 5)
check(14150, "st_hatch", [5, 0, 0, 0, 0], 5)
sys.exit(0 if ok else 1)
PY
