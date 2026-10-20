; HUD text: glyphs of 4 x 8 pixels (tools/mkfont.py, 40 columns x 4 rows)
; written into the four HUD sets of the base &4000 page (set s at byte
; s*512; the sets of R3 phase 1 hold the HUD one byte to the left, so it
; stays still). Called from the game code in bank 5: maps the base RAM and
; bank 5 again before returning.

HUD_BG		equ 0		; HUD background pen
HUD_LINE	equ 12		; the line under the HUD

; Colours of the next glyphs: A = ink, B = paper.
hud_colors:
	ld c,a
	ld hl,hud_pair
	ld e,0				; pair = (left pixel, right pixel) bits
.l:	ld a,e
	and 2
	ld a,c
	jr nz,.lf
	ld a,b
.lf:	push hl
	ld hl,m0_left
	call .pen
	pop hl
	ld d,a
	ld a,e
	and 1
	ld a,c
	jr nz,.rf
	ld a,b
.rf:	push hl
	ld hl,m0_right
	call .pen
	pop hl
	or d
	ld (hl),a
	inc hl
	inc e
	ld a,e
	cp 4
	jr nz,.l
	ret
.pen:	add a,l				; A = (HL + A)
	ld l,a
	ld a,h
	adc a,0
	ld h,a
	ld a,(hl)
	ret

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

; Number HL as D digits (leading zeros as spaces, at least one digit) at
; column B, row C; hud_number0: with the leading zeros.
hud_number0:
	ld a,0
	jr hud_num
hud_number:
	ld a,1
hud_num:
	ld (hn_lead),a
	push bc
	ld ix,hn_digits+5		; 5 decimal digits, last first
	ld b,5
.dv:	push bc
	ld c,10				; HL / 10, remainder in A
	xor a
	ld b,16
.d:	add hl,hl
	rla
	cp c
	jr c,.n
	sub c
	inc l
.n:	djnz .d
	dec ix
	ld (ix+0),a
	pop bc
	djnz .dv
	pop bc
	ld a,5				; the last D digits
	sub d
	ld e,a
	ld d,0
	ld ix,hn_digits
	add ix,de
	ld a,5
	sub e
	ld d,a
	ld a,(hn_lead)			; leading zero: space
	ld e,a
.o:	ld a,(ix+0)
	or a
	jr nz,.nz
	ld a,d
	dec a
	jr z,.nz			; (the last digit)
	ld a,e
	or a
	ld a,G_SPACE
	jr nz,.put
	xor a
.nz:	ld e,0
.put:	push bc
	push de
	push ix
	call hud_char
	pop ix
	pop de
	pop bc
	inc b
	inc ix
	dec d
	jr nz,.o
	ret

; The game's HUD: all four sets in the background colour, a line under it.
; Needs RAM_C0.
hud_clear:
	ld hl,#4000			; line l of the sets: &4000 + l*&800, 2K
	ld b,8
.l:	push bc
	push hl
	ld d,h
	ld e,l
	inc de
	ld (hl),0			; (HUD_BG = pen 0)
	ld bc,#7FF
	ldir
	pop hl
	pop bc
	ld a,b
	dec a
	jr nz,.n
	push hl				; last line: row 3 of every set
	ld de,3*80
	add hl,de
	ld c,4
.s:	push hl
	ld b,80
.b:	ld (hl),(HUD_LINE&1)*#C0 | ((HUD_LINE>>1)&1)*#0C | ((HUD_LINE>>2)&1)*#30 | ((HUD_LINE>>3)&1)*#03
	inc hl
	djnz .b
	pop hl
	ld de,512
	add hl,de
	dec c
	jr nz,.s
	pop hl
	ret				; (that was the last line)
.n:	ld a,h
	add a,8
	ld h,a
	djnz .l
	ret

hud_pair:	ds 4,0
hn_digits:	ds 5,0
hn_lead:	db 0

	include "hudfont.asm"
