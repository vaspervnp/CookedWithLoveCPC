; Amstrad CPC hardware constants and macros (included first).

GA_PORT		equ #7F		; gate array (high byte of port)
GA_RMR_MODE0	equ #8C		; RMR: mode 0, upper & lower ROM off
GA_PEN_BORDER	equ #10

CRTC_SEL	equ #BC		; CRTC register select (high byte)
CRTC_DATA	equ #BD		; CRTC register data (high byte)

PPI_B		equ #F5		; PPI port B: bit 0 = VSYNC

SCREEN		equ #C000


; --- 128K memory configuration (gate array, bits 7-6 = 11) ---
RAM_C0		equ #C0		; base 64K
RAM_C4		equ #C4		; bank 4 at &4000: sprite graphics
RAM_C5		equ #C5		; bank 5 at &4000: map, tiles
RAM_C6		equ #C6		; bank 6 at &4000: sprite save-under
RAM_C7		equ #C7

; Select a RAM configuration. Destroys BC.
macro RAM cfg
	ld bc,GA_PORT*256+{cfg}
	out (c),c
mend
