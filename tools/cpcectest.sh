#!/bin/bash
# Scroll regression suite on CPCEC (accurate CRTC emulation, types 0-4).
# Static positions: 3 consecutive frames each. Motion: bounce builds, every
# frame of a run is checked (position found automatically).
# Usage: tools/cpcectest.sh [crtc types, default "0 1 2 3 4"]
cd "$(dirname "$0")/.."
mkdir -p build/cpcec
TYPES="${1:-0 1 2 3 4}"
fail=0
check() { # check <x|-1> <y|-1> <frames>
	local out=""
	for f in build/cpcec/t*.bmp; do
		r=$(python3 tools/scrollcheck.py "$f" "$1" "$2" --emu cpcec 2>&1 | tail -1)
		case "$r" in *OK) out="$out.";; *) out="$out X"; fail=1; echo "  $(basename $f): $r";; esac
	done
	echo -n "$out"
}
for g in $TYPES; do
	echo "== CRTC $g"
	for xy in "0 0" "0 1" "0 2" "0 3" "0 4" "0 5" "0 6" "0 7" "1 7" "77 250" "240 504"; do
		set -- $xy
		make -s en EXTRA="-DTEST_X=$1 -DTEST_Y=$2" >/dev/null 2>&1
		rm -f build/cpcec/t*.bmp; tools/cpcecshot.sh build/cwl_en.dsk build/cpcec/t "850,851,852" $g
		echo -n "static [$1,$2]"; check $1 $2; echo
	done
	make -s en EXTRA="-DTEST_PATH=3 -DTEST_X=0 -DTEST_Y=40" >/dev/null 2>&1
	rm -f build/cpcec/t*.bmp; tools/cpcecshot.sh build/cwl_en.dsk build/cpcec/t "$(seq -s, 870 1 930)" $g
	echo -n "bounce V"; check 0 -1; echo
	make -s en EXTRA="-DTEST_PATH=3 -DTEST_X=12 -DTEST_Y=0" >/dev/null 2>&1
	rm -f build/cpcec/t*.bmp; tools/cpcecshot.sh build/cwl_en.dsk build/cpcec/t "$(seq -s, 870 1 900)" $g
	echo -n "bounce H"; check -1 0; echo
done
make -s en >/dev/null 2>&1
exit $fail
