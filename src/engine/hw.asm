; Amstrad CPC hardware constants and low-level helpers.

GA_PORT		equ #7F		; gate array (high byte of port)
GA_RMR_MODE0	equ #8C		; RMR: mode 0, upper & lower ROM off
GA_PEN_BORDER	equ #10

CRTC_SEL	equ #BC		; CRTC register select (high byte)
CRTC_DATA	equ #BD		; CRTC register data (high byte)

PPI_B		equ #F5		; PPI port B: bit 0 = VSYNC

SCREEN		equ #C000

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
