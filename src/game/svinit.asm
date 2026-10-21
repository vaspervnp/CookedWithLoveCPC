; The HUD of the service at the start (src/game/service.asm): part of the
; boot code (runs once, from the boot with bank 5 mapped).
service_init:
	if TEST_FILL			; test: 9 portions of each, open
	ld hl,sv_stock
	ld b,DISH_N
.st:	ld (hl),9
	inc hl
	djnz .st
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
