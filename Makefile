# Cooked with Love - Amstrad CPC build

RASM   ?= rasm
IDSK   ?= iDSK
CPC    ?= caprice32.launcher
PYTHON ?= python3

BUILD  := build
SRC    := $(shell find src -name '*.asm')
GEN    := $(BUILD)/palette.asm $(BUILD)/hudfont.asm $(BUILD)/recicons.asm $(BUILD)/recipes.asm $(BUILD)/text_en.asm $(BUILD)/text_gr.asm $(BUILD)/testtiles.bin $(BUILD)/test_map.bin $(BUILD)/lvl1_map.bin $(BUILD)/spr.asm

LOAD   := 0100
EXEC   := 0100

ifeq ($(DEBUG),1)
RASMFLAGS += -DDEBUG=1
endif
# extra assembler defines, e.g. make en EXTRA="-DTEST_X=1 -DTEST_Y=7"
# (the overlay: OVLEXTRA="-DTEST_EXP=1")
RASMFLAGS += $(EXTRA)

FORCE:

.SECONDARY: $(BUILD)/prep_en.bin $(BUILD)/prep_gr.bin $(BUILD)/title_en.scr $(BUILD)/title_gr.scr

.PHONY: FORCE parts staff items tiles all en gr run-en run-gr shot-en shot-gr palette clean

all: en gr
en: $(BUILD)/cwl_en.dsk
gr: $(BUILD)/cwl_gr.dsk

palette: $(BUILD)/palette.asm

$(BUILD):
	mkdir -p $@

$(BUILD)/palette.asm: data/palette.txt tools/palette.py tools/cpc.py | $(BUILD)
	$(PYTHON) tools/palette.py --asm $@ --gpl assets/palette/cwl.gpl

$(BUILD)/hudfont.asm: tools/mkfont.py tools/cpc.py | $(BUILD)
	$(PYTHON) tools/mkfont.py $@ $(BUILD)/recicons.asm
$(BUILD)/recicons.asm: $(BUILD)/hudfont.asm ;

# HUD texts of each language and the letters they use
$(BUILD)/text_%.asm: data/text/strings.tsv tools/text2asm.py tools/mkfont.py | $(BUILD)
	$(PYTHON) tools/text2asm.py $< $* $(BUILD)/text_$*_font.asm $@

$(BUILD)/recipes.asm: data/recipes/recipes.tsv tools/recipes2asm.py | $(BUILD)
	$(PYTHON) tools/recipes2asm.py $< $@

$(BUILD)/testtiles.bin: tools/mktestmap.py tools/cpc.py | $(BUILD)
	$(PYTHON) tools/mktestmap.py $@ $(BUILD)/testmap.bin $(BUILD)/testhud.bin --asm $(BUILD)/test.asm

# Map in 16x16 metatiles: build/<map>_map.bin, _meta.bin, _tiles.bin (and
# the plain _tilemap.bin for the screenshot checkers)
$(BUILD)/test_map.bin: $(BUILD)/testtiles.bin tools/maps2asm.py
	$(PYTHON) tools/maps2asm.py $(BUILD)/testtiles.bin $(BUILD)/testmap.bin $(BUILD)/test

# Level 1: the map (assets/maps/level1.txt) on the restaurant tileset
# (assets/tiles/restaurant.png/.txt, drawn by tools/mktileset.py: make tiles),
# with its objects (tables, stations: build/lvl1_objs.asm)
$(BUILD)/lvl1_map.bin: assets/maps/level1.txt assets/maps/level1_open.txt assets/maps/level1_kitchen.txt assets/tiles/restaurant.png assets/tiles/restaurant.txt tools/buildmap.py tools/maps2asm.py | $(BUILD)
	$(PYTHON) tools/buildmap.py assets/tiles/restaurant.png assets/maps/level1.txt $(BUILD)/lvl1 --open assets/maps/level1_open.txt --kopen assets/maps/level1_kitchen.txt
	$(PYTHON) tools/maps2asm.py $(BUILD)/lvl1_src_tiles.bin $(BUILD)/lvl1_src_map.bin $(BUILD)/lvl1 $(BUILD)/lvl1_src_open.bin $(BUILD)/lvl1_src_kopen.bin

tiles:
	$(PYTHON) tools/mktileset.py assets/tiles

# Sprite sheets, compiled together (shared banks, identical lines and frames
# stored once): common code in banks 4, 6 -> build/spr_<bank>.dat, area
# images for bank 7 -> build/spr_<image>.dat
# and the frame descriptors build/spr.asm. Sheet: PREFIX:PNG:HEIGHT:GROUP:MIRROR[:COLUMNS[:YOFF[:IMAGE]]]
#   bill        rows down / up / right, 5 frames each (idle, walk 1-4), of which
#               idle, walk 1 and walk 3 are used; left = mirror
#   cust_*      customer parts (head 20, body 14, legs 14 lines; YOFF = line of the
#               part in the figure), one style per row with the same 9 frames;
#               any head + body + legs combine
#   tray        Bill's tray with 1-3 plates: front (facing down), side (right; left =
#               mirror); bubble: mood bubbles (heart, angry, waiting, food, pay)
#               (tools/items.py, make items)
#   liberty     the cook: rows down / up / right x idle, walk 1, walk 2; left = mirror
#   liberty_act chop 1-2, stir 1-2, oven 1-2 facing right, then the same mirrored
#   blossom     the storage keeper: walk as liberty; blossom_carry the same with a
#               box, rows down / right (left = mirror; going up the box is hidden,
#               the walk is used); blossom_act putting a box on a shelf to her
#               right (2 frames, not mirrored: the storage image is full)
# IMAGE (last field): the sheet goes into that area image of bank 7, a disk
# file <IMAGE>.SPR loaded when the camera enters the area (src/game/area.asm);
# image b5 is the top of bank 5 (&6F00), always resident (B5.SPR)
SHEETS := bill:assets/sprites/bill.png:48:9:6:0,1,3 \
	cust_head:assets/sprites/cust_head.png:20:9:6 \
	cust_body:assets/sprites/cust_body.png:14:9:6::20 \
	cust_legs:assets/sprites/cust_legs.png:14:9:6::34 \
	cust_sit:assets/sprites/cust_sit.png:14:1:0::34 \
	tray:assets/sprites/tray.png:12:6:3:::b5 \
	bubble:assets/sprites/bubble.png:14:::::b5 \
	mouth:assets/sprites/mouth.png:20:1:0:::b5 \
	liberty:assets/sprites/liberty.png:48:9:6:::kitchen \
	liberty_act:assets/sprites/liberty_act.png:48:6:0:::kitchen \
	blossom:assets/sprites/blossom.png:48:9:6:::storage \
	blossom_carry:assets/sprites/blossom_carry.png:48:6:3:::storage \
	blossom_act:assets/sprites/blossom_act.png:48:2::::storage
$(BUILD)/spr.asm: $(foreach s,$(SHEETS),$(word 2,$(subst :, ,$(s)))) tools/spritec.py tools/png2cpc.py tools/cpc.py data/palette.txt | $(BUILD)
	$(PYTHON) tools/spritec.py $(BUILD)/spr $(foreach s,$(SHEETS),--sheet $(s)) --banks 4,6 --area-bank 7 --fixed b5:5:0x6F78:0x1088

# Customer part sheets from the customer renders (assets/blender/customer_build.py)
parts:
	$(PYTHON) tools/custparts.py $(BUILD)/render/cust assets/sprites

# Small add-on sprites (tray, mood bubbles), pixel art by code
items:
	$(PYTHON) tools/items.py assets/sprites

# Staff sheets from their renders (assets/blender/<name>_build.py)
staff:
	$(PYTHON) tools/charsheet.py liberty $(BUILD)/render/liberty assets/sprites
	$(PYTHON) tools/charsheet.py blossom $(BUILD)/render/blossom assets/sprites

$(BUILD)/cwl_en.bin: $(SRC) $(GEN) FORCE
	$(RASM) src/main.asm -Isrc -I$(BUILD) -DLANG_EN=1 $(RASMFLAGS) -ob $@ -os $(BUILD)/cwl_en.sym -s -sq

$(BUILD)/cwl_gr.bin: $(SRC) $(GEN) FORCE
	$(RASM) src/main.asm -Isrc -I$(BUILD) -DLANG_GR=1 $(RASMFLAGS) -ob $@ -os $(BUILD)/cwl_gr.sym -s -sq

# The overlay between the days (src/ovl/prep.asm), with the symbols of the
# game of the same language
$(BUILD)/prep_%.bin: src/ovl/prep.asm $(BUILD)/cwl_%.bin
	awk '$$1 !~ /\./ && $$1 !~ /^(BUILDCPC|SYNCHRO|RASM_VERSION)$$/ {print $$1 "\tequ " $$2}' $(BUILD)/cwl_$*.sym > $(BUILD)/syms_$*.asm
	$(RASM) src/ovl/prep.asm -Isrc -I$(BUILD) -DOVERLAY=1 -DLANG_$(shell echo $* | tr a-z A-Z)=1 $(filter -DDEMO=%,$(EXTRA)) $(OVLEXTRA) -ob $@

# The title screen of each language (a Mode 0 screen, loaded at &C000)
$(BUILD)/title_%.scr: tools/mktitle.py tools/mkfont.py tools/png2cpc.py assets/sprites/bill.png assets/sprites/liberty.png assets/sprites/blossom.png data/palette.txt | $(BUILD)
	$(PYTHON) tools/mktitle.py $* $@ --png $(BUILD)/title_$*.png

# Disk name on the CPC is always CWL.BIN -> RUN"CWL
# the loader (CWL.BIN: the title at once, then the game)
$(BUILD)/loader.bin: src/loader.asm $(BUILD)/palette.asm | $(BUILD)
	$(RASM) src/loader.asm -I$(BUILD) -DLOADER=1 -ob $@ >/dev/null

$(BUILD)/cwl_%.dsk: $(BUILD)/cwl_%.bin $(BUILD)/prep_%.bin $(BUILD)/title_%.scr $(BUILD)/loader.bin
	rm -f $@ $(BUILD)/CWL.BIN $(BUILD)/GAME.BIN
	$(IDSK) $@ -n
	cp $(BUILD)/loader.bin $(BUILD)/CWL.BIN
	cd $(BUILD) && $(IDSK) $(notdir $@) -i CWL.BIN -t 1 -c 9000 -e 9000 >/dev/null && rm -f CWL.BIN
	cp $< $(BUILD)/GAME.BIN
	cd $(BUILD) && $(IDSK) $(notdir $@) -i GAME.BIN -t 1 -c $(LOAD) -e $(EXEC) -s >/dev/null && rm -f GAME.BIN
	cp $(BUILD)/prep_$*.bin $(BUILD)/PREP.OVL
	cd $(BUILD) && $(IDSK) $(notdir $@) -i PREP.OVL -t 1 -c 2800 -s >/dev/null && rm -f PREP.OVL
	cp $(BUILD)/title_$*.scr $(BUILD)/TITLE.SCR
	cd $(BUILD) && $(IDSK) $(notdir $@) -i TITLE.SCR -t 1 -c C000 -s >/dev/null && rm -f TITLE.SCR
	cd $(BUILD) && for f in spr_?.dat; do b=$${f#spr_}; b=$${b%.dat}; cp $$f SPR$$b.DAT; $(IDSK) $(notdir $@) -i SPR$$b.DAT -t 1 -c 4000 -s >/dev/null; rm -f SPR$$b.DAT; done
	cd $(BUILD) && for f in spr_??*.dat; do a=$${f#spr_}; a=$${a%.dat}; n=$$(echo $$a | tr a-z A-Z | cut -c1-8).SPR; cp $$f $$n; $(IDSK) $(notdir $@) -i $$n -t 1 -c 4000 -s >/dev/null; rm -f $$n; done
	head -c 1024 /dev/zero > $(BUILD)/SAVE.DAT		# the save (src/ovl/save.asm): raw, 1K
	cd $(BUILD) && $(IDSK) $(notdir $@) -i SAVE.DAT -t 2 >/dev/null && rm -f SAVE.DAT
	$(PYTHON) tools/edsk.py $@				# EXTENDED CPC DSK (the game writes to it)

run-en: en
	$(CPC) -a 'run"cwl' $(BUILD)/cwl_en.dsk

run-gr: gr
	$(CPC) -a 'run"cwl' $(BUILD)/cwl_gr.dsk

# Headless run + screenshot (~/snap/caprice32/current/screenshots/)
shot-en: en
	tools/cpcshot.sh $(BUILD)/cwl_en.dsk

shot-gr: gr
	tools/cpcshot.sh $(BUILD)/cwl_gr.dsk

clean:
	rm -rf $(BUILD)
