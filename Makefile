# Cooked with Love - Amstrad CPC build

RASM   ?= rasm
IDSK   ?= iDSK
CPC    ?= caprice32.launcher
PYTHON ?= python3

BUILD  := build
SRC    := $(shell find src -name '*.asm')
GEN    := $(BUILD)/palette.asm $(BUILD)/testtiles.bin $(BUILD)/spr.asm

LOAD   := 0100
EXEC   := 0100

ifeq ($(DEBUG),1)
RASMFLAGS += -DDEBUG=1
endif
# extra assembler defines, e.g. make en EXTRA="-DTEST_X=1 -DTEST_Y=7"
RASMFLAGS += $(EXTRA)

FORCE:

.PHONY: FORCE parts all en gr run-en run-gr shot-en shot-gr palette clean

all: en gr
en: $(BUILD)/cwl_en.dsk
gr: $(BUILD)/cwl_gr.dsk

palette: $(BUILD)/palette.asm

$(BUILD):
	mkdir -p $@

$(BUILD)/palette.asm: data/palette.txt tools/palette.py tools/cpc.py | $(BUILD)
	$(PYTHON) tools/palette.py --asm $@ --gpl assets/palette/cwl.gpl

$(BUILD)/testtiles.bin: tools/mktestmap.py tools/cpc.py | $(BUILD)
	$(PYTHON) tools/mktestmap.py $@ $(BUILD)/testmap.bin $(BUILD)/testhud.bin

# Sprite sheets, compiled together (shared banks, identical lines and frames
# stored once): code in banks 4, 6, 7 -> build/spr_<bank>.dat
# and the frame descriptors build/spr.asm. Sheet: PREFIX:PNG:HEIGHT:GROUP:MIRROR[:COLUMNS[:YOFF]]
#   bill        rows down / up / right, 5 frames each (idle, walk 1-4), of which
#               idle, walk 1 and walk 3 are used; left = mirror
#   cust_*      customer parts (head 20, body 14, legs 14 lines; YOFF = line of the
#               part in the figure), one style per row with the same 9 frames;
#               any head + body + legs combine
SHEETS := bill:assets/sprites/bill.png:48:9:6:0,1,3 \
	cust_head:assets/sprites/cust_head.png:20:9:6 \
	cust_body:assets/sprites/cust_body.png:14:9:6::20 \
	cust_legs:assets/sprites/cust_legs.png:14:9:6::34
$(BUILD)/spr.asm: $(foreach s,$(SHEETS),$(word 2,$(subst :, ,$(s)))) tools/spritec.py tools/png2cpc.py tools/cpc.py data/palette.txt | $(BUILD)
	$(PYTHON) tools/spritec.py $(BUILD)/spr $(foreach s,$(SHEETS),--sheet $(s)) --banks 4,6,7

# Customer part sheets from the character renders (placeholder recolours)
parts:
	$(PYTHON) tools/mkparts.py $(BUILD)/render/bill assets/sprites

$(BUILD)/cwl_en.bin: $(SRC) $(GEN) FORCE
	$(RASM) src/main.asm -Isrc -I$(BUILD) -DLANG_EN=1 $(RASMFLAGS) -ob $@ -os $(BUILD)/cwl_en.sym -s

$(BUILD)/cwl_gr.bin: $(SRC) $(GEN) FORCE
	$(RASM) src/main.asm -Isrc -I$(BUILD) -DLANG_GR=1 $(RASMFLAGS) -ob $@ -os $(BUILD)/cwl_gr.sym -s

# Disk name on the CPC is always CWL.BIN -> RUN"CWL
$(BUILD)/cwl_%.dsk: $(BUILD)/cwl_%.bin
	rm -f $@ $(BUILD)/CWL.BIN
	cp $< $(BUILD)/CWL.BIN
	$(IDSK) $@ -n
	$(IDSK) $@ -i $(BUILD)/CWL.BIN -t 1 -c $(LOAD) -e $(EXEC)
	rm -f $(BUILD)/CWL.BIN
	cd $(BUILD) && for f in spr_?.dat; do b=$${f#spr_}; b=$${b%.dat}; cp $$f SPR$$b.DAT; $(IDSK) $(notdir $@) -i SPR$$b.DAT -t 1 -c 4000 -s >/dev/null; rm -f SPR$$b.DAT; done

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
