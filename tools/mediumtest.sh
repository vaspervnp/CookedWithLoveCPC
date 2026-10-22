#!/bin/bash
# Medium in CPCEC, with scripted keys (~2 min): the groups sit by themselves
# (TEST_FILL, no patience lost), Bill starts at table 6 and takes the order
# of its single customer (cod: a stove); Liberty cooks it, lets it burn,
# takes it to the pass; Bill takes it there and serves it, and the burnt
# dish costs 64 patience after the refill. Checks RAM dumps (tools/cpcram.py).
# Keys: line*8+bit (0 up, 1 right, 2 down, 8 left, 47 space, 76 fire), VBLs.
set -e
cd "$(dirname "$0")/.."
OUT=build/cpcec/medium
mkdir -p build/cpcec
make -s en EXTRA="-DTEST_FILL=1 -DTEST_MODE=1 -DBILL_X0=56 -DBILL_Y0=366" >/dev/null
cp build/cwl_en.sym $OUT.sym
K=(
	76:1600-1608 47:1700-1708			# the order, to Liberty
	1:2000-2100 76:2150-2158			# to the stove: cook
	76:3000-3008					# burnt: take it
	8:3050-3150 2:3170-3326 8:3350-3450 76:3480-3488	# to the pass
	47:3550-3558 2:3600-3644 1:3650-4700 76:4730-4738	# Bill: the pass
	8:4780-5600 1:5620-5689 0:5720-5900 76:5930-5938	# table 6: serve
)
rm -f $OUT*.ram
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy CPCEC_KEYS="$(IFS=,; echo "${K[*]}")" \
	CPCEC_DUMPS="1650,2200,2400,2950,3040,3520,4760,5980" CPCEC_PREFIX=$OUT CPCEC_EXIT=5980 \
	timeout 600 "${CPCEC:-$HOME/tools/cpcec/cpcec}" -S -r0 -O -m2 -k1 -g0 build/cwl_en.dsk >/dev/null 2>&1 || true
make -s en >/dev/null
python3 - "$OUT" <<'PY'
import sys
sys.path.insert(0, "tools")
from cpcram import Ram
o = sys.argv[1]
ok = True
def check(frame, what, got, want):
    global ok
    good = got == want
    ok &= good
    print(f"{'ok  ' if good else 'FAIL'} {frame:5d} {what:16s} {got}" + ("" if good else f" (want {want})"))
def g1(frame):			# group 1: the single customer at table 6
    r = Ram(f"{o}{frame:05d}.ram", o + ".sym")
    return r, r.get("groups", 32)[16:32]
r, g = g1(1650); check(1650, "ordered", (g[0], g[3]), (6, 6))
r, g = g1(2200); check(2200, "cooking", r.get("ks_slots", 54)[36:39], [1, 1, 2])
r, g = g1(2400); check(2400, "done", r.get("ks_slots", 54)[36], 2)
r, g = g1(2950); check(2950, "burnt", r.get("ks_slots", 54)[36], 3)
r, g = g1(3040); check(3040, "Liberty carries", (r.get("lib_carry"), r.get("lib_cburnt")), (2, 1))
r, g = g1(3520); check(3520, "ready, 1 burnt", (g[0], g[9]), (7, 1))
r, g = g1(4760); check(4760, "on Bill's tray", (g[0], r.get("bill_carry")), (8, 2))
r, g = g1(5980); check(5980, "eating, P", (g[0], g[6]), (9, 255 - 64))
sys.exit(0 if ok else 1)
PY
