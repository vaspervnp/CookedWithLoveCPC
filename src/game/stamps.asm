; Stamps (src/engine/sprite.asm): which ones to draw into the back buffer
; this frame. Runs in bank 5, from sprites_draw.
;
; The stamps of the sprite list (in draw order) are compared with the ones
; this buffer holds (position and a hash of the entry): the ones gone are
; erased (their rectangles in sd_erase: redraw_tiles), the new ones drawn;
; one that touches an erased or a drawn one is drawn again, and so on (in
; depth order, so overlapping figures stay right). After buffer_sync drew
; new tiles all are drawn. More than STAMP_MAX: the rest as normal sprites.

SD_W		equ 32		; a stamp's rectangle (figure, sitting drop)
SD_H		equ 52
SD_ENT		equ 6		; x, y, hash
SDR_SIZE		equ 1+STAMP_MAX*SD_ENT
SDC_SIZE		equ 8		; x, y, hash, entry index, flags

sd_rec:		ds 2*SDR_SIZE,0	; per buffer: count, stamps
sd_erase:	ds STAMP_MAX*4,0	; rectangles (x, y) to erase
sd_nerase:	db 0
sd_cur:		ds STAMP_MAX*SDC_SIZE,0
sd_ncur:	db 0
sd_drew:	db 0
sd_chg:		db 0

SDF_MATCH	equ 1		; flags: was in the buffer already
SDF_DRAW	equ 2		; to draw

; Out: NZ if there is something to erase or draw.
stamp_diff:
	call buffer_drew		; new tiles in this buffer?
	ld (sd_drew),a
	xor a
	ld (sd_ncur),a
	ld (sd_nerase),a
	ld (sd_chg),a
	; the current stamps
	ld a,(spr_n)
	or a
	jr z,.prev
	ld b,a
	ld hl,spr_order
.c:	push bc
	push hl
	ld a,(hl)
	push af
	call spr_entry
	pop af
	ld c,a
	ld a,(ix+SE_STAMP)
	or a
	jr z,.cn
	ld a,(sd_ncur)
	cp STAMP_MAX
	jr c,.ok
	ld (ix+SE_STAMP),0		; too many: a normal sprite
	jr .cn
.ok:	inc a
	ld (sd_ncur),a
	dec a
	call sd_cur_at			; IY = its record
	ld a,(ix+SE_X)
	ld (iy+0),a
	ld a,(ix+SE_X+1)
	ld (iy+1),a
	ld a,(ix+SE_Y)
	ld (iy+2),a
	ld a,(ix+SE_Y+1)
	ld (iy+3),a
	call sd_hash
	ld (iy+4),l
	ld (iy+5),h
	ld (iy+6),c
	ld (iy+7),0
.cn:	pop hl
	pop bc
	inc hl
	djnz .c
.prev:	; the buffer's ones: still there, or to erase
	call sd_buf			; HL = record
	ld a,(hl)
	or a
	jr z,.mark
	ld b,a
	inc hl
.p:	push bc
	push hl
	ld e,(hl)			; x, y, hash
	inc hl
	ld d,(hl)
	inc hl
	ld c,(hl)
	inc hl
	ld b,(hl)
	inc hl
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	ld (sd_hv),hl
	call sd_find			; IY = the same current one (not matched)
	jr z,.pm
	ld hl,(sd_nerase)		; not there any more: erase
	ld h,0
	add hl,hl
	add hl,hl
	push de
	ld de,sd_erase
	add hl,de
	pop de
	ld (hl),e
	inc hl
	ld (hl),d
	inc hl
	ld (hl),c
	inc hl
	ld (hl),b
	ld hl,sd_nerase
	inc (hl)
	jr .pn
.pm:	set 0,(iy+7)			; SDF_MATCH
.pn:	pop hl
	ld de,SD_ENT
	add hl,de
	pop bc
	djnz .p
.mark:	; to draw: all after new tiles, else the new ones and the ones
	; touching an erased rectangle
	ld a,(sd_ncur)
	or a
	jp z,.rec
	ld b,a
	xor a
.m:	push bc
	push af
	call sd_cur_at
	ld a,(sd_drew)
	or a
	jr nz,.md
	bit 0,(iy+7)
	jr z,.md
	ld a,(sd_nerase)		; touches an erased one?
	or a
	jr z,.mn
	ld b,a
	ld hl,sd_erase
.e:	push bc
	ld e,(hl)
	inc hl
	ld d,(hl)
	inc hl
	ld c,(hl)
	inc hl
	ld b,(hl)
	inc hl
	push hl
	call sd_overlap
	pop hl
	pop bc
	jr c,.md
	djnz .e
	jr .mn
.md:	set 1,(iy+7)			; SDF_DRAW
.mn:	pop af
	pop bc
	inc a
	djnz .m
.cl:	; and the ones touching one to draw, until nothing changes
	xor a
	ld (sd_chg),a
	ld a,(sd_ncur)
	ld b,a
	xor a
.ci:	push bc
	push af
	call sd_cur_at
	bit 1,(iy+7)
	jr z,.cin
	ld e,(iy+0)			; IY to draw: the others it touches
	ld d,(iy+1)
	ld c,(iy+2)
	ld b,(iy+3)
	ld a,(sd_ncur)
	ld l,a
	xor a
.ck:	push hl
	push af
	call sd_cur_at
	bit 1,(iy+7)
	jr nz,.ckn
	call sd_overlap
	jr nc,.ckn
	set 1,(iy+7)
	ld a,1
	ld (sd_chg),a
.ckn:	pop af
	pop hl
	inc a
	cp l
	jr nz,.ck
.cin:	pop af
	pop bc
	inc a
	djnz .ci
	ld a,(sd_chg)
	or a
	jr nz,.cl
	; mark the entries
	ld a,(sd_ncur)
	ld b,a
	xor a
.se:	push bc
	push af
	call sd_cur_at
	bit 1,(iy+7)
	jr z,.sn
	ld a,(iy+6)
	call spr_entry
	ld (ix+SE_STAMP),2
	ld a,1
	ld (sd_chg),a			; (something to draw)
.sn:	pop af
	pop bc
	inc a
	djnz .se
.rec:	; the buffer holds the current ones now
	call sd_buf
	ld a,(sd_ncur)
	ld (hl),a
	or a
	jr z,.end
	inc hl
	ex de,hl
	ld b,a
	xor a
.r:	push bc
	push af
	call sd_cur_at
	push iy
	pop hl
	ld bc,SD_ENT
	ldir
	pop af
	pop bc
	inc a
	djnz .r
.end:	ld a,(sd_chg)			; NZ: erase or draw
	ld hl,sd_nerase
	or (hl)
	ret

; IY = current stamp A
sd_cur_at:
	add a,a
	add a,a
	add a,a
	ld iyl,a
	ld iyh,0
	push de
	ld de,sd_cur
	add iy,de
	pop de
	ret

; HL = record of the back buffer
sd_buf:
	ld hl,sd_rec
	ld a,(back)
	or a
	ret z
	ld hl,sd_rec+SDR_SIZE
	ret

; HL = hash of entry IX: its words rotated and added
sd_hash:
	push bc
	push ix
	pop de
	ld hl,0
	ld b,SE_STAMP/2			; frame, x, y, z, f2, f3
.w:	add hl,hl
	jr nc,.n
	inc l
.n:	ld a,(de)
	inc de
	add a,l
	ld l,a
	ld a,(de)
	inc de
	adc a,h
	ld h,a
	djnz .w
	pop bc
	ret

; Z, IY = the current stamp at x DE, y BC with hash sd_hv, not matched yet
sd_find:
	ld a,(sd_ncur)
	or a
	jr z,.no
	push hl
	ld l,a
	xor a
.f:	push af
	call sd_cur_at
	pop af
	bit 0,(iy+7)
	jr nz,.n
	push hl
	ld hl,(sd_hv)
	ld a,(iy+4)
	cp l
	jr nz,.nh
	ld a,(iy+5)
	cp h
	jr nz,.nh
	ld a,(iy+0)
	cp e
	jr nz,.nh
	ld a,(iy+1)
	cp d
	jr nz,.nh
	ld a,(iy+2)
	cp c
	jr nz,.nh
	ld a,(iy+3)
	cp b
.nh:	pop hl
	jr z,.yes
.n:	push hl				; next (A = index, L = count)
	call .idx
	inc a
	pop hl
	cp l
	jr nz,.f
	pop hl
.no:	or 1				; NZ: none
	ret
.yes:	pop hl
	xor a
	ret
.idx:	push iy				; A = index of IY
	pop hl
	push de
	ld de,sd_cur
	or a
	sbc hl,de
	pop de
	ld a,l
	rrca
	rrca
	rrca
	and #1F
	ret

; Carry if the rectangles at (DE, BC) and stamp IY overlap.
sd_overlap:
	push bc
	push de
	ld l,(iy+0)			; |x - x'| < SD_W
	ld h,(iy+1)
	or a
	sbc hl,de
	call .abs
	ld a,h
	or a
	jr nz,.no
	ld a,l
	cp SD_W
	jr nc,.no
	ld l,(iy+2)			; |y - y'| < SD_H
	ld h,(iy+3)
	or a
	sbc hl,bc
	call .abs
	ld a,h
	or a
	jr nz,.no
	ld a,l
	cp SD_H
	pop de
	pop bc
	ret
.no:	pop de
	pop bc
	or a
	ret
.abs:	bit 7,h
	ret z
	ex de,hl
	ld hl,0
	or a
	sbc hl,de
	ret

sd_hv:	dw 0
