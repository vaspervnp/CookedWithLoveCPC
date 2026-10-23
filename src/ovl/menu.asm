; The recipes bought (src/game/menu.asm: the data in bank 5), in the
; overlay's second half. The icons and inks here are loaded with it each
; time as made (tools/mkfont.py): the new recipe's are copied to the menu
; (the replaced one's are not needed again until a new game, which copies
; the first menu's back).

	include "recicons.asm"		; rc_/mn_ ink, icons

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
	ld hl,mn_ink			; the first menu's icons, inks
	ld de,dish_ink
	ld bc,DISH_N
	ldir
	ld hl,mn_icons
	ld de,hud_font+G_DISH0*4
	ld bc,DISH_N*8
	ldir
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

; Dish B of the menu and recipe DISH_N + C change places in the tables;
; the recipe's icon and ink to dish B.
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
	ld a,(rc_b)			; the ink, the icon (2 glyphs of 4 bytes)
	ld hl,rc_ink			; copied
	call st_add
	ld a,(hl)
	push af
	ld a,(rc_b+1)
	ld hl,dish_ink
	call st_add
	pop af
	ld (hl),a
	ld a,(rc_b+1)
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
	ld bc,8
	ldir
	ret
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
