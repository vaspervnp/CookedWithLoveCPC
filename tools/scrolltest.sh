#!/bin/bash
# M1 scroll regression suite: builds test variants, screenshots them in
# Caprice32 and compares each with the expected picture.
# Usage: tools/scrolltest.sh            (full suite)
#        tools/scrolltest.sh "<defines>" "sx sy" ...
set -u
cd "$(dirname "$0")/.."
mkdir -p build/shots
fail=0
run() {
	local extra="$1"; shift
	local line=""
	for xy in "$@"; do
		set -- $xy
		make -s en EXTRA="$extra -DTEST_X=$1 -DTEST_Y=$2" >/dev/null 2>&1 || { echo "build failed: $extra"; exit 1; }
		tools/cpcshot.sh build/cwl_en.dsk build/shots/test.png >/dev/null
		r=$(python3 tools/scrollcheck.py build/shots/test.png "$1" "$2")
		[ "$r" = OK ] || fail=1
		line="$line [$1,$2]${r%% *}"
	done
	echo "${extra:-static}:$line"
}
if [ $# -gt 0 ]; then
	run "$@"
else
	run "" "0 0" "1 1" "2 2" "3 3" "4 4" "5 5" "6 6" "7 7" "77 250" "239 503" "240 504"
	run "-DTEST_PATH=1" "57 99" "240 504"
	run "-DTEST_PATH=2" "13 3" "0 0"
	run "-DTEST_PATH=1 -DFINE_X=0 -DFINE_Y=0" "120 256"
fi
make -s en >/dev/null 2>&1
exit $fail
