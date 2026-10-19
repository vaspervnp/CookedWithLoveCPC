# Cooked with Love - Amstrad CPC build

RASM   ?= rasm
IDSK   ?= iDSK
CPC    ?= caprice32.launcher
PYTHON ?= python3

BUILD  := build
SRC    := $(shell find src -name '*.asm')
GEN    := $(BUILD)/palette.asm

LOAD   := 0100
EXEC   := 0100

ifeq ($(DEBUG),1)
RASMFLAGS += -DDEBUG=1
endif

.PHONY: all en gr run-en run-gr shot-en shot-gr palette clean

all: en gr
en: $(BUILD)/cwl_en.dsk
gr: $(BUILD)/cwl_gr.dsk

palette: $(BUILD)/palette.asm

$(BUILD):
	mkdir -p $@

$(BUILD)/palette.asm: data/palette.txt tools/palette.py tools/cpc.py | $(BUILD)
	$(PYTHON) tools/palette.py --asm $@ --gpl assets/palette/cwl.gpl

$(BUILD)/cwl_en.bin: $(SRC) $(GEN)
	$(RASM) src/main.asm -Isrc -I$(BUILD) -DLANG_EN=1 $(RASMFLAGS) -ob $@ -os $(BUILD)/cwl_en.sym -s

$(BUILD)/cwl_gr.bin: $(SRC) $(GEN)
	$(RASM) src/main.asm -Isrc -I$(BUILD) -DLANG_GR=1 $(RASMFLAGS) -ob $@ -os $(BUILD)/cwl_gr.sym -s

# Disk name on the CPC is always CWL.BIN -> RUN"CWL
$(BUILD)/cwl_%.dsk: $(BUILD)/cwl_%.bin
	rm -f $@ $(BUILD)/CWL.BIN
	cp $< $(BUILD)/CWL.BIN
	$(IDSK) $@ -n
	$(IDSK) $@ -i $(BUILD)/CWL.BIN -t 1 -c $(LOAD) -e $(EXEC)
	rm -f $(BUILD)/CWL.BIN

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
