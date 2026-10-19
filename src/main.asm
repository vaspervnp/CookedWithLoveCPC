; Cooked with Love - Amstrad CPC 6128
; Build: rasm src/main.asm -Isrc -Ibuild -DLANG_EN=1 (or -DLANG_GR=1)

	ifndef LANG_EN
LANG_EN	equ 0
	endif
	ifndef LANG_GR
LANG_GR	equ 0
	endif
	assert LANG_EN+LANG_GR==1,"define exactly one of LANG_EN / LANG_GR"

STACK_TOP	equ #0100

	org #0100
	buildcpc
	run start

start:
	di
	ld sp,STACK_TOP
	im 1
	ld hl,#C9FB		; 'ei : ret' at #0038 -> our own IRQ handler
	ld (#0038),hl
	ld bc,GA_PORT*256+GA_RMR_MODE0
	out (c),c		; mode 0, ROMs off (firmware no longer used)

	call wait_vsync
	ld hl,palette_hw
	call set_palette
	call draw_test_bars
	ei

main_loop:
	call wait_vsync
	halt			; let the VSYNC interrupt pass
	jr main_loop

; M0 test picture: 16 vertical bars, one per pen (10 pixels = 5 bytes each).
draw_test_bars:
	ld hl,SCREEN
	ld b,8
.block:	push bc
	push hl
	ld c,25
.row:	ld de,pen_bytes
	ld b,16
.bar:	ld a,(de)
	ld (hl),a : inc hl
	ld (hl),a : inc hl
	ld (hl),a : inc hl
	ld (hl),a : inc hl
	ld (hl),a : inc hl
	inc de
	djnz .bar
	dec c
	jr nz,.row
	pop hl
	ld de,#0800		; next 2K block = next scanline in char row
	add hl,de
	pop bc
	djnz .block
	ret

; Mode 0 bytes with both pixels set to pen 0..15.
pen_bytes:
	db #00,#C0,#0C,#CC,#30,#F0,#3C,#FC,#03,#C3,#0F,#CF,#33,#F3,#3F,#FF

	include "engine/hw.asm"
	include "palette.asm"

	if LANG_EN
	; language-specific data will go here (text, font)
	endif
	if LANG_GR
	endif

code_end:
	print "code end: ",{hex}code_end
