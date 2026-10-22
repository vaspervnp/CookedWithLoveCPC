; Boot: move the data staged in the loaded binary into the extra 64K.
;
; The disk binary is loaded by AMSDOS into base RAM (&0100 up to ~&A000):
;   &4000..   contents of bank 5 (map, tiles), at its runtime address
; The sprite banks (4, 6, 7) come from their own files (load_banks).
; The pages are reused afterwards (HUD page, screen buffers).

mem_relocate:
	ld hl,#4000			; bank 5: &4000 (base) -> &8000 -> &4000 (bank)
	ld de,#8000
	ld bc,bank5_end-bank5_start
	ldir
	RAM RAM_C5
	ld hl,#8000
	ld de,#4000
	ld bc,bank5_end-bank5_start
	ldir
	RAM RAM_C0
	ld hl,tiles_src			; the tiles: to SAVE_AREA0 for tiles_place
	ld de,SAVE_AREA0
	ld bc,TILE_N_HUD*32
	ldir
	ld hl,#4000			; clear base &4000-&FFFF (HUD page, screens)
	ld de,#4001
	ld bc,#BFFF
	ld (hl),0
	ldir
	ret
