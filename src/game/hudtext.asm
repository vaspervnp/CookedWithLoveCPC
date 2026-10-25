; HUD text helpers that run in bank 5 (src/engine/hud.asm draws the glyphs).

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
.pen:	call st_add			; A = (HL + A)
	ld a,(hl)
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

hn_digits:	ds 5,0
hn_lead:	db 0
