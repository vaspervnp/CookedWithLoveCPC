; Areas: the sprites of the staff of an area (kitchen: Liberty, storage:
; Blossom) are an image of bank 7 (tools/spritec.py, IMAGE field), a file
; <NAME>.SPR on the disc. When the camera enters another area its image is
; loaded with the FDC (src/engine/fdc.asm): the display stops (black, plain
; CRTC frame) for about a second and the view is rebuilt.
;
; Between the two thresholds the loaded area stays (no ping-pong). Level 1:
; dining room and kitchen are the kitchen area (screen columns 0-2), the
; storage screen column 3; storage loads when the camera is well into it
; (the kitchen is then out of view but for its right edge, where Liberty is
; not drawn), the kitchen when the storage is out of view.

	if MAP_TEST			; test map: kitchen left, storage right
AREA_SX_KITCHEN	equ 60		; scroll x below: kitchen
AREA_SX_STORAGE	equ 140		; scroll x above: storage
	else
AREA_SX_KITCHEN	equ 150		; camera left < 300 px: storage out of view
AREA_SX_STORAGE	equ 190		; camera left > 380 px
	endif
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

; The overlay between the days (src/ovl/prep.asm, PREP.OVL on the disc):
; the summary, the costs, the morning preparation. The service asks for it
; (ovl_req) when the room is empty: only Bill's figures are drawn then,
; whose save-unders stay below OVL_BASE in the second save area, so the
; overlay lives there until the service opens again.
OVL_BASE	equ SAVE_AREA1+#800	; (where the boot code ran: 2K)
OVL_INIT	equ OVL_BASE		; jump table: init (phase SP_OVER/SP_PREP)
OVL_TICK	equ OVL_BASE+3		; a tick between the days (bank 5 mapped)
ovl_req:	db 0
view_req:	db 0		; the map changed (the overlay): draw it again
ovl_name:	db "PREP    OVL"

; Load the overlay, restart the view, call its init (main loop, base RAM).
ovl_load:
	xor a
	ld (ovl_req),a
	di
	call crtc_plain
.try:	ld hl,ovl_name
	ld de,OVL_BASE-AREA_HDR
	call fdc_load
	jr nc,.ok
	ld bc,GA_PORT*256+GA_PEN_BORDER	; read error: red border, again
	out (c),c
	ld a,#4C
	out (c),a
	jr .try
.ok:	call view_restart
	RAM RAM_C5
	call OVL_INIT
	RAM RAM_C0
	ret
