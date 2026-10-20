; Areas: the sprites of the staff of an area (kitchen: Liberty, storage:
; Blossom) are an image of bank 7 (tools/spritec.py, IMAGE field), a file
; <NAME>.SPR on the disc. When the camera enters another area its image is
; loaded with the FDC (src/engine/fdc.asm): the display stops (black, plain
; CRTC frame) for about a second and the view is rebuilt.
;
; Test level: the kitchen is the left of the map, the storage the right;
; between the two thresholds the loaded area stays (no ping-pong).

AREA_SX_KITCHEN	equ 60		; scroll x below: kitchen
AREA_SX_STORAGE	equ 140		; scroll x above: storage
AREA_HDR	equ 128		; AMSDOS header in front of the image

area_cur:	db AREA_KITCHEN	; loaded at boot (load_banks)

; Once per frame (game): load the area the camera is in, if needed.
area_check:
	ld a,(scr_sx)
	ld b,AREA_KITCHEN
	cp AREA_SX_KITCHEN
	jr c,.want
	ld b,AREA_STORAGE
	cp AREA_SX_STORAGE+1
	ret c
.want:	ld a,(area_cur)
	cp b
	ret z
	ld a,b
	; fall through

; Load area A into bank 7 and restart the view.
area_load:
	ld (area_cur),a
	di
	call crtc_plain			; black, stable frame without interrupts
	ld a,(area_cur)			; name = spr_area_files + 11*A
	ld l,a
	ld h,0
	ld d,h
	ld e,l
	add hl,hl
	add hl,hl
	add hl,de
	add hl,hl
	add hl,de
	ld de,spr_area_files
	add hl,de
	RAM RAM_C7
.try:	push hl
	ld de,#4000-AREA_HDR		; header below the bank window
	call fdc_load
	pop hl
	jr nc,.ok
	ld bc,GA_PORT*256+GA_PEN_BORDER	; read error: red border, again
	out (c),c
	ld a,#4C
	out (c),a
	jr .try
.ok:	RAM RAM_C0
	jp view_restart
