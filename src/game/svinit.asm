; The HUD of the service at the start (src/game/service.asm): part of the
; boot code (runs once, from the boot with bank 5 mapped).
service_init:
	if TB_LOCK_N			; the expansion's tables: locked
	ld hl,tb_busy
	ld b,TB_LOCK_N
.lk:	ld (hl),TB_LOCKED
	inc hl
	djnz .lk
	endif
	ifdef TEST_XP			; test: expansions bought (sv_exp bits;
	ld a,TEST_XP			; the maps stay closed), the hired ones at
	ld (sv_exp),a			; the pass (as hw_morning, src/ovl/prep.asm:
	ld ix,wt_rec			; TEST_FILL starts with the service)
	ld hl,PASS_BX
	ld de,PASS_BY
	ld a,EXP_WAITER
	call .hw
	ld ix,ck_rec
	ld hl,PASS_KX
	ld a,EXP_COOK
	call .hw
	ld ix,hl_rec
	ld hl,HL_HX
	ld de,HL_HY
	ld a,EXP_HELPER
	call .hw
	jr .xd
.hw:	ld (ix+HW_HX),l
	ld (ix+HW_HX+1),h
	ld (ix+AC_X),l
	ld (ix+AC_X+1),h
	ld (ix+HW_HY),e
	ld (ix+HW_HY+1),d
	ld (ix+AC_Y),e
	ld (ix+AC_Y+1),d
	ld hl,sv_exp
	and (hl)
	ret z
	ld (ix+HW_STATE),WT_HOME
	ret
.xd:
	endif
	if TEST_FILL			; test: 8 portions of each, open, the
	ld hl,sv_stock			; hatch full (Hard)
	ld b,DISH_N
.st:	ld (hl),8
	inc hl
	djnz .st
	ld hl,st_hatch
	ld b,ING_N
.sh:	ld (hl),HATCH_CAP
	inc hl
	djnz .sh
	ifdef TEST_DOOR			; test: TEST_DOOR boxes of group 0 at
	ld a,TEST_DOOR			; the door, none of it at the hatch
	ld (st_door),a
	xor a
	ld (st_hatch),a
	endif
	xor a
	call sv_status
	call sv_hud_stock
	else
	ld a,SP_PREP			; the first morning: the overlay
	ld (sv_phase),a
	ld a,1
	ld (ovl_req),a
	endif
	ld a,8				; icons
	ld b,HUD_BG
	call hud_colors
	ld a,G_COIN_L
	ld bc,(1<<8)+HUD_ROW
	call hud_char
	ld a,G_COIN_R
	ld bc,(2<<8)+HUD_ROW
	call hud_char
	ld a,13
	ld b,HUD_BG
	call hud_colors
	ld a,G_CLOCK_L
	ld bc,((HUD_TIME-3)<<8)+HUD_ROW
	call hud_char
	ld a,G_CLOCK_R
	ld bc,((HUD_TIME-2)<<8)+HUD_ROW
	call hud_char
	ld a,G_PERSON_L
	ld bc,((HUD_SERVED-3)<<8)+HUD_ROW
	call hud_char
	ld a,G_PERSON_R
	ld bc,((HUD_SERVED-2)<<8)+HUD_ROW
	call hud_char
	ld a,4				; angry: red
	ld b,HUD_BG
	call hud_colors
	ld a,G_ANGRY_L
	ld bc,((HUD_LOST-3)<<8)+HUD_ROW
	call hud_char
	ld a,G_ANGRY_R
	ld bc,((HUD_LOST-2)<<8)+HUD_ROW
	call hud_char
	ld a,5				; day: orange
	ld b,HUD_BG
	call hud_colors
	ld a,G_SUN_L
	ld bc,(1<<8)+HUD_ROW2
	call hud_char
	ld a,G_SUN_R
	ld bc,(2<<8)+HUD_ROW2
	call hud_char
	call sv_hud_money
	jp sv_hud_day
