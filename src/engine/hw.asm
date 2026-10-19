; Amstrad CPC low-level helpers (constants and macros: engine/defs.asm).

; Wait for the start of VSYNC.
; Destroys: A, B
wait_vsync:
	ld b,PPI_B
.leave:	in a,(c)		; wait until any running VSYNC ends
	rra
	jr c,.leave
.enter:	in a,(c)
	rra
	jr nc,.enter
	ret

; Set the 16 pens and the border from a 17-byte table of hardware colours.
; In: HL = table
; Destroys: A, BC, HL
set_palette:
	ld bc,GA_PORT*256
.loop:	out (c),c		; select pen C
	ld a,(hl)
	out (c),a		; set colour
	inc hl
	inc c
	ld a,c
	cp GA_PEN_BORDER+1
	jr nz,.loop
	ret
