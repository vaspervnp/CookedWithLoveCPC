#!/bin/bash
# Screenshots for docs/img (PNG, the picture cropped from CPCEC's frame):
# the title in both languages and moments of the scenario tests (tools/
# *test.sh, which still check their values), ~12 min.
set -e
cd "$(dirname "$0")/.."
OUT=docs/img
mkdir -p $OUT build/cpcec
make -s en gr >/dev/null
for l in en gr; do
	rm -f build/cpcec/title_$l*.bmp
	tools/cpcecshot.sh build/cwl_$l.dsk build/cpcec/title_$l 1500
done
SHOTS=1650,2400,3520,4760,5980 tools/mediumtest.sh
SHOTS=1550,9100,12600,14150 tools/hardtest.sh
SHOTS=5150,6500 tools/exptest.sh
SHOTS=5650,5850,9250 tools/recipetest.sh
python3 - $OUT <<'PY'
import os, sys
from PIL import Image
out = sys.argv[1]
boot = int(os.environ.get("BOOT", "210"))
shots = [			# name, file (prefix, VBL: + BOOT for the scenarios)
    ("title_en", "title_en", 1500, 0), ("title_gr", "title_gr", 1500, 0),
    ("dining_order", "medium", 1650, 1), ("kitchen_cooking", "medium", 2400, 1),
    ("kitchen_pass", "medium", 3520, 1), ("dining_tray", "medium", 4760, 1),
    ("dining_served", "medium", 5980, 1),
    ("hard_morning", "hard", 1550, 1), ("hard_supplier", "hard", 9100, 1),
    ("storage_door", "hard", 12600, 1), ("storage_hatch", "hard", 14150, 1),
    ("evening_offers", "exp", 5150, 1), ("expansion_room", "exp", 6500, 1),
    ("recipe_choose", "recipe", 5650, 1), ("recipe_menu", "recipe", 5850, 1),
    ("bankrupt", "recipe", 9250, 1),
]
for name, pre, f, shifted in shots:
    src = f"build/cpcec/{pre}{f + boot * shifted:05d}.bmp"
    Image.open(src).convert("RGB").crop((64, 40, 704, 480)).save(f"{out}/{name}.png")
    print(f"{out}/{name}.png")
PY
