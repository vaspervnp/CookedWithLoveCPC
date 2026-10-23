; The recipes bought (src/game/menu.asm: the data in bank 5), in the
; overlay's second half.

; Recipe DISH_N + rc_cnt (rc_new) replaces dish A of the menu.
rc_place:
	ld b,a
	ld a,(rc_cnt)
	ld c,a
	ld hl,rc_log
	call st_add
	ld (hl),b
	call rc_swap
	ld hl,rc_cnt
	inc (hl)
	xor a
	ld (rc_new),a
	ret

; A new game: the menu as at the start (the last swap undone first).
rc_reset:
	ld a,(rc_cnt)
	or a
	jr z,.e
	dec a
	ld (rc_cnt),a
	ld c,a
	ld hl,rc_log
	call st_add
	ld b,(hl)
	call rc_swap
	jr rc_reset
.e:	ld (rc_new),a
	ret

; The icon of recipe DISH_N + A into G_NEW_L/R (to show it).
rc_show:
	add a,a
	add a,a
	add a,a
	ld hl,rc_icons
	call st_add
	ld de,hud_font+G_NEW_L*4
	ld bc,8
	ldir
	ret

; Dish B of the menu and recipe DISH_N + C change places.
rc_swap:
	ld (rc_b),bc
	ld ix,rc_tabs
.t:	ld l,(ix+0)			; the byte tables
	ld h,(ix+1)
	ld a,h
	or l
	jr z,.w
	push hl
	ld a,(rc_b+1)
	call st_add
	ex de,hl
	pop hl
	ld a,(rc_b)
	add a,DISH_N
	call st_add
	ld b,1
	call rc_xchg
	inc ix
	inc ix
	jr .t
.w:	ld a,(rc_b+1)			; the cooking time (words)
	add a,a
	ld hl,dish_ticks
	call st_add
	ex de,hl
	ld a,(rc_b)
	add a,DISH_N
	add a,a
	ld hl,dish_ticks
	call st_add
	ld b,2
	call rc_xchg
	ld a,(rc_b+1)			; the ink
	ld hl,dish_ink
	call st_add
	ex de,hl
	ld a,(rc_b)
	ld hl,rc_ink
	call st_add
	ld b,1
	call rc_xchg
	ld a,(rc_b+1)			; the icon: 2 glyphs of 4 bytes
	add a,a
	add a,a
	add a,a
	ld hl,hud_font+G_DISH0*4
	call st_add
	ex de,hl
	ld a,(rc_b)
	add a,a
	add a,a
	add a,a
	ld hl,rc_icons
	call st_add
	ld b,8
	; fall through
; B bytes at HL and DE change places.
rc_xchg:
	ld a,(de)
	ld c,(hl)
	ld (hl),a
	ld a,c
	ld (de),a
	inc hl
	inc de
	djnz rc_xchg
	ret
rc_tabs:	dw dish_price,dish_cost,dish_need,dish_stn,dish_prep,0
rc_b:		dw 0		; (rc_swap: C, B)
