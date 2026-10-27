#!/bin/bash
# Screenshots for docs/img (PNG, the picture cropped from CPCEC's frame),
# for each language (<name>.png English, <name>_gr.png Greek: the manuals
# docs/manual_*.md): the title and moments of the scenario tests (tools/
# *test.sh, which still check their values), ~35 min.
#   tools/screenshots.sh [en] [gr]
set -e
cd "$(dirname "$0")/.."
OUT=docs/img
mkdir -p $OUT build/cpcec
# crop <lang> name:prefix:VBL[:raw] ...: from the scenario's frames (VBL +
# BOOT, not for raw, the plain runs)
crop() {
	python3 - "$OUT" "$@" <<'PY'
import os, sys
from PIL import Image
out, lang = sys.argv[1], sys.argv[2]
boot = int(os.environ.get("BOOT", "210"))
for s in sys.argv[3:]:
    name, pre, f, *raw = s.split(":")
    src = f"build/cpcec/{pre}{int(f) + (0 if raw else boot):05d}.bmp"
    dst = f"{out}/{name}{'' if lang == 'en' else '_' + lang}.png"
    Image.open(src).convert("RGB").crop((64, 40, 704, 480)).save(dst)
    print(dst)
PY
}
for l in ${@:-en gr}; do
	export CWL_LANG=$l
	make -s $l >/dev/null
	rm -f build/cpcec/title_$l*.bmp
	tools/cpcecshot.sh build/cwl_$l.dsk build/cpcec/title_$l 1500
	crop $l title:title_$l:1500:raw
	SHOTS=1650,2400,3520,4760,5980 tools/mediumtest.sh || echo "($l: mediumtest failed a check)"
	crop $l dining_order:medium:1650 kitchen_cooking:medium:2400 kitchen_pass:medium:3520 \
		dining_tray:medium:4760 dining_served:medium:5980
	SHOTS=1550,9100,12600,14150 tools/hardtest.sh || echo "($l: hardtest failed a check)"
	crop $l hard_morning:hard:1550 hard_supplier:hard:9100 storage_door:hard:12600 storage_hatch:hard:14150
	SHOTS=5150,6500 tools/exptest.sh || echo "($l: exptest failed a check)"
	crop $l evening_offers:exp:5150 expansion_room:exp:6500
	SHOTS=5650,5850,9250 tools/recipetest.sh || echo "($l: recipetest failed a check)"
	crop $l recipe_choose:recipe:5650 recipe_menu:recipe:5850 bankrupt:recipe:9250
	SHOTS=2450 tools/cooktest.sh || echo "($l: cooktest failed a check)"
	crop $l staff_cook:cook:2450
	SHOTS=2250 tools/waiter2test.sh || echo "($l: waiter2test failed a check)"
	crop $l staff_waiters:waiter2:2250
	SHOTS=1200 tools/savetest.sh || echo "($l: savetest failed a check)"
	crop $l continue:save:1200
	. tools/scenario.sh		# the kitchen's expansion: room and kitchen
	make -s $l OVLEXTRA=-DTITLE_WAIT=50 EXTRA="-DDAY_MIN=3 -DTEST_MONEY=700" >/dev/null
	SHOTS=6300 scenario build/cpcec/kexp "76:1250-1258,76:1300-1308,0:5200-5208,0:5300-5308,76:5600-5608,76:5800-5808,47:5900-5908,2:6000-6700" "" 6300 600
	make -s $l >/dev/null
	crop $l kitchen_expansion:kexp:6300
done
