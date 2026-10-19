; Boot: move the data staged in the loaded binary into the extra 64K.
;
; The disk binary is loaded by AMSDOS into base RAM (&0100 up to ~&A000):
;   &4000..   contents of bank 4 (sprites), already at its runtime address
;   &8000..   contents of bank 5 (map, tiles), assembled for &4000
; Both pages are reused afterwards (HUD page, screen buffers).

mem_relocate:
	RAM RAM_C5			; bank 5: &8000 (base) -> &4000 (bank)
	ld hl,#8000
	ld de,#4000
	ld bc,bank5_end-bank5_start
	ldir
	RAM RAM_C0			; bank 4: &4000 (base) -> &8000 -> &4000 (bank)
	ld hl,#4000
	ld de,#8000
	ld bc,bank4_end-bank4_start
	ldir
	RAM RAM_C4
	ld hl,#8000
	ld de,#4000
	ld bc,bank4_end-bank4_start
	ldir
	RAM RAM_C0
	ld hl,#4000			; clear base &4000-&FFFF (HUD page, screens)
	ld de,#4001
	ld bc,#BFFF
	ld (hl),0
	ldir
	ret
