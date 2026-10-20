#!/bin/bash
# Sprite regression on CPCEC (Bill, no customers): demo walk with 0 and 3
# clones, Bill in the partial top row, and fixed positions at the map edge and
# across the end of a 2K block.
# Every line should read OK. Leaves a normal build behind.

for c in 0 3; do
  make -s en EXTRA="-DCUSTOMERS=0 -DSTAFF=0 -DAREAS=0 -DDEMO=1 -DDEBUG=1 -DCLONES=$c" >/dev/null 2>&1
  rm -f build/cpcec/k*.bmp; tools/cpcecshot.sh build/cwl_en.dsk build/cpcec/k $(seq -s, 700 23 3000)
  echo "demo C=$c: $(for f in build/cpcec/k*.bmp; do python3 tools/gamecheck.py $f --emu cpcec --clones $c 2>&1 | tail -1 | awk '{print $1}'; done | sort | uniq -c | tr '\n' ' ')"
done
# Bill in the partial top row (camera follows him closer to the top)
make -s en EXTRA="-DCUSTOMERS=0 -DSTAFF=0 -DAREAS=0 -DDEMO=1 -DDEBUG=1 -DCAM_T=40" >/dev/null 2>&1
rm -f build/cpcec/k*.bmp; tools/cpcecshot.sh build/cwl_en.dsk build/cpcec/k $(seq -s, 700 23 3000)
echo "top row: $(for f in build/cpcec/k*.bmp; do python3 tools/gamecheck.py $f --emu cpcec 2>&1 | tail -1 | awk '{print $1}'; done | sort | uniq -c | tr '\n' ' ')"
for p in "14 110" "20 110" "84 232" "100 232" "111 232"; do set -- $p
  make -s en EXTRA="-DCUSTOMERS=0 -DSTAFF=0 -DAREAS=0 -DDEBUG=1 -DDBGPOS=1 -DBILL_X0=$1 -DBILL_Y0=$2" >/dev/null 2>&1
  rm -f build/cpcec/w*.bmp; tools/cpcecshot.sh build/cwl_en.dsk build/cpcec/w 900
  echo "pos $1,$2: $(python3 tools/gamecheck.py build/cpcec/w00900.bmp --emu cpcec 2>&1 | tail -1)"
done
make -s en >/dev/null 2>&1
