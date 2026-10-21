; HUD text: glyphs of 4 x 8 pixels (tools/mkfont.py, 40 columns x 4 rows)
; written into the four HUD sets of the base &4000 page (set s at byte
; s*512; the sets of R3 phase 1 hold the HUD one byte to the left, so it
; stays still). Called from the game code in bank 5: maps the base RAM and
; bank 5 again before returning. Colours and numbers: src/game/hudtext.asm
; (bank 5).

HUD_BG		equ 0		; HUD background pen
HUD_LINE	equ 12		; the line under the HUD

; Glyph A at column B (0-39), row C (0-3).
hud_char:
	ld l,a
	ld h,0
	add hl,hl
	add hl,hl
	add hl,hl
	ld de,hud_font
	add hl,de
	ex de,hl			; DE = glyph
	ld a,c				; HL = row*80 + column*2
	add a,a
	add a,a
	add a,a
	add a,a
	ld l,a
	ld h,0
	add hl,hl
	add hl,hl
	ld a,c
	add a,a
	add a,a
	add a,a
	add a,a
	add a,l
	ld l,a
	ld a,h
	adc a,0
	ld h,a
	ld a,b
	add a,a
	add a,l
	ld l,a
	ld a,h
	adc a,#40
	ld h,a
	RAM RAM_C0
	ld b,8				; lines: +&800
.line:	push bc
	ld a,(de)			; left pixels: bits 3, 2; right: 1, 0
	inc de
	push de
	push hl
	ld e,a
	rrca
	rrca
	and 3
	call .pair
	ld c,a
	ld a,e
	and 3
	call .pair
	ld b,a				; C, B = the two bytes
	pop hl
	push hl
	ld de,512
	ld (hl),c			; sets 0, 1
	inc hl
	ld (hl),b
	dec hl
	add hl,de
	ld (hl),c
	inc hl
	ld (hl),b
	add hl,de			; sets 2, 3: one byte to the left
	dec hl
	dec hl
	ld (hl),c
	inc hl
	ld (hl),b
	dec hl
	add hl,de
	ld (hl),c
	inc hl
	ld (hl),b
	pop hl
	ld a,h
	add a,8
	ld h,a
	pop de
	pop bc
	djnz .line
	RAM RAM_C5
	ret
.pair:	push hl
	ld hl,hud_pair
	add a,l
	ld l,a
	ld a,h
	adc a,0
	ld h,a
	ld a,(hl)
	pop hl
	ret

hud_pair:	ds 4,0

	include "hudfont.asm"
