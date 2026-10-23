; Routines of the service (src/game/service.asm) that live in the free ends
; of the metatile planes, after the tables (src/game/vars.asm).

	if VARS_BLK==2
; The kitchen, between the orders: the portions ordered at the pass, one
; after the other, each in its dish's time; done: one more left.
sv_cook_tick:
	ld hl,(sv_cook_t)
	ld a,h
	or l
	jr z,.next
	dec hl
	ld (sv_cook_t),hl
	ld a,h
	or l
	ret nz
	ld a,(sv_cook_d)		; done
	ld e,a
	ld d,0
	ld hl,sv_stock
	add hl,de
	inc (hl)
	ld hl,sv_cook
	add hl,de
	dec (hl)
	jp sv_hud_stock
.next:	ld hl,sv_cook			; the next one ordered
	ld b,DISH_N
	ld e,0
.f:	ld a,(hl)
	or a
	jr nz,.st
	inc hl
	inc e
	djnz .f
	ret
.st:	ld a,e
	ld (sv_cook_d),a
	ld d,0
	ld hl,dish_ticks
	add hl,de
	add hl,de
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	call kx_fast
	ld (sv_cook_t),hl
	ret
	endif

	if VARS_BLK==3
; (VARS_BLK 3) HUD row 3: the customers waiting at the entrance (arriving, in the
; queue), drawn when the number changes.
sv_hud_queue:
	ld ix,groups
	ld b,G_MAX
	ld c,0
.g:	ld a,(ix+GR_STATE)
	dec a				; GS_ARRIVE, GS_QUEUE
	cp 2
	jr nc,.n
	ld a,c
	add a,(ix+GR_N)
	ld c,a
.n:	ld de,GR_SIZE
	add ix,de
	djnz .g
	ld hl,sv_qlast
	ld a,(hl)
	cp c
	ret z
	ld (hl),c
	push bc
	ld a,13
	ld b,HUD_BG
	call hud_colors
	ld a,G_PERSON_L
	ld bc,(HUD_QUEUE<<8)+HUD_ROW3
	call hud_char
	ld a,G_PERSON_R
	ld bc,((HUD_QUEUE+1)<<8)+HUD_ROW3
	call hud_char
	pop hl
	ld h,0
	ld d,1
	ld bc,((HUD_QUEUE+2)<<8)+HUD_ROW3
	jp hud_number

sv_qlast:	db #FF		; (#FF: draw it again)
	endif
