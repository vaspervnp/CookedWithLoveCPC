; Between the days: an overlay (PREP.OVL), loaded by ovl_load
; (src/game/area.asm) at OVL_BASE when the room is empty, assembled on its
; own with the symbols of the game (build/syms_<lang>.asm, made from
; build/cwl_<lang>.sym by the Makefile). Runs with bank 5 mapped, from service_tick.
;
; The end of the day: rent and wages (DAY_COST) are paid, the stars and
; the earnings of the day; not enough money: game over. Fire: the morning
; of the next day, 10:00-12:00: the portions of each dish of the menu
; (HUD row 2: icon and portions; up/down: one more/less, left/right: the
; dish). A portion costs its ingredients (dish_cost) and minutes of the two
; hours (dish_prep: the clock moves on); the customers order only what is
; left (src/game/service.asm). Fire: open.

	ifdef LANG_EN			; the game's symbols (build/syms_<lang>.asm)
	include "syms_en.asm"
	else
	include "syms_gr.asm"
	endif

	org OVL_BASE
	if SERVICE==0			; (test builds without the service)
	ret
	else
	jp ov_init
	jp ov_tick

	include "recipes.asm"		; dish_cost, dish_prep (OVERLAY)

PREP_START	equ 10*60	; the morning
PREP_MIN	equ 120
PORTION_MAX	equ 9		; per dish (one digit)
OV_COL		equ 8		; HUD row 2: dish d at column OV_COL + 4 d
OV_COST		equ 2+TXT_COST_LEN	; row 3: cost and price of the dish
OV_PRICE	equ OV_COST+3+TXT_PRICE_LEN

ov_cur:		db 0		; the dish chosen
ov_used:	db 0		; minutes of the morning used
ov_stars:	db 0

ov_init:
	ld a,(sv_phase)
	cp SP_PREP
	jp z,ov_morning			; (the first day)
	ld hl,(sv_money)		; the day is over: rent and wages
	ld de,DAY_COST
	or a
	sbc hl,de
	jr nc,.paid
	ld hl,0				; not enough: game over
	ld (sv_money),hl
	call sv_hud_money
	ld a,SP_BROKE
	ld (sv_phase),a
	ld a,4
	ld hl,txt_broke
	ld de,txt_new_game
	jp ov_line
.paid:	ld (sv_money),hl
	call sv_hud_money
	call ov_summary
	ld a,13
	ld hl,txt_day_end
	ld de,txt_next
	jp ov_line

; A tick: fire (and in the morning the cursor keys) pressed this tick.
ov_tick:
	ld a,(input)
	ld b,a
	ld a,(sv_prev)
	cpl
	and b
	ld c,a
	ld a,b
	ld (sv_prev),a
	ld a,(sv_phase)
	cp SP_PREP
	jr z,ov_keys
	bit KEY_FIRE,c
	ret z
	cp SP_BROKE
	jr nz,ov_morning
	ld hl,START_MONEY		; a new game
	ld (sv_money),hl
	xor a
	ld (sv_day),a
	; fall through

; The morning of the next day.
ov_morning:
	ld hl,sv_day
	inc (hl)
	ld a,SP_PREP
	ld (sv_phase),a
	ld hl,(sv_money)
	ld (sv_money0),hl
	ld hl,PREP_START
	ld (sv_min),hl
	ld hl,0
	ld (sv_served),hl
	ld (sv_lost),hl
	xor a
	ld (ov_cur),a
	ld (ov_used),a
	ld hl,sv_stock
	ld b,DISH_N
.z:	ld (hl),a
	inc hl
	djnz .z
	ld a,HUD_BG			; row 2: the stars and earnings go
	ld b,a
	call hud_colors
	ld bc,(OV_COL<<8)+HUD_ROW2
	ld e,40
	call hud_spaces
	call sv_hud_day			; day, served, lost, time
	call sv_hud_money
	ld a,13
	ld hl,txt_cost
	ld de,txt_open_fire
	call ov_line
	ld a,13
	ld b,HUD_BG
	call hud_colors
	ld hl,txt_price
	ld bc,((OV_COST+2)<<8)+HUD_ROW3
	call hud_text
	jp ov_draw

ov_keys:
	ld hl,ov_cur
	bit KEY_LEFT,c
	jr z,.r
	dec (hl)
	jr .wrap
.r:	bit KEY_RIGHT,c
	jr z,.u
	inc (hl)
.wrap:	ld a,(hl)
	and DISH_N-1
	ld (hl),a
	jp ov_draw
.u:	ld e,(hl)			; DE = the dish
	ld d,0
	bit KEY_UP,c
	jr nz,ov_more
	bit KEY_DOWN,c
	jr nz,ov_less
	bit KEY_FIRE,c
	ret z
	; fire: open
	ld hl,12*60
	ld (sv_min),hl
	xor a
	ld (sv_sec),a
	ld (sv_phase),a			; SP_OPEN
	ld hl,50
	ld (sv_spawn_t),hl
	ld a,HUD_BG			; row 3: status, queue, portions
	ld b,a
	call hud_colors
	ld bc,(1<<8)+HUD_ROW3
	ld e,40
	call hud_spaces
	ld a,#FF
	ld (sv_qlast),a
	call sv_hud_stock
	xor a				; SP_OPEN
	call sv_status
	call sv_hud_tickets		; (row 2 cleared)
	jp sv_hud_time

ov_more:				; one portion more of dish DE, if
	ld hl,sv_stock			; there is room, time and money
	add hl,de
	ld a,(hl)
	cp PORTION_MAX
	ret nc
	push hl
	ld hl,dish_prep
	add hl,de
	ld a,(ov_used)
	add a,(hl)
	pop hl
	cp PREP_MIN+1
	ret nc
	push af
	push hl
	ld hl,dish_cost
	add hl,de
	ld c,(hl)
	ld b,0
	ld hl,(sv_money)
	or a
	sbc hl,bc
	pop de
	jr c,.no
	ld (sv_money),hl
	ex de,hl
	inc (hl)
	pop af
	ld (ov_used),a
	jr ov_draw
.no:	pop af
	ret

ov_less:				; one portion less: time and money back
	ld hl,sv_stock
	add hl,de
	ld a,(hl)
	or a
	ret z
	dec (hl)
	ld hl,dish_prep
	add hl,de
	ld a,(ov_used)
	sub (hl)
	ld (ov_used),a
	ld hl,dish_cost
	add hl,de
	ld c,(hl)
	ld b,0
	ld hl,(sv_money)
	add hl,bc
	ld (sv_money),hl
	; fall through

; Row 2: the dishes (the chosen one in its colour) and their portions;
; row 3: cost and price of the chosen one; money and clock.
ov_draw:
	ld c,0				; dish
.d:	push bc
	ld hl,dish_ink
	ld b,0
	add hl,bc
	ld a,(ov_cur)
	cp c
	ld a,(hl)
	jr z,.ink
	ld a,12				; the others: grey
.ink:	ld b,HUD_BG
	call hud_colors
	pop bc
	push bc
	ld a,c				; column
	add a,a
	add a,a
	add a,OV_COL
	ld b,a
	ld a,c
	add a,a
	add a,G_DISH0
	push bc
	push af
	ld c,HUD_ROW2
	call hud_char
	pop af
	pop bc
	inc a
	inc b
	push bc
	ld c,HUD_ROW2
	call hud_char
	pop bc
	inc b
	ld hl,sv_stock			; portions
	ld e,c
	ld d,0
	add hl,de
	ld l,(hl)
	ld h,0
	ld d,1
	ld c,HUD_ROW2
	call hud_number
	pop bc
	inc c
	ld a,c
	cp DISH_N
	jr nz,.d
	ld a,13				; cost, price
	ld b,HUD_BG
	call hud_colors
	ld a,(ov_cur)
	ld e,a
	ld d,0
	ld hl,dish_cost
	add hl,de
	ld l,(hl)
	ld h,0
	ld d,1
	ld bc,(OV_COST<<8)+HUD_ROW3
	call hud_number
	ld a,(ov_cur)
	ld e,a
	ld d,0
	ld hl,dish_price
	add hl,de
	ld l,(hl)
	ld h,0
	ld d,2
	ld bc,(OV_PRICE<<8)+HUD_ROW3
	call hud_number
	call sv_hud_money
	ld a,(ov_used)
	ld l,a
	ld h,0
	ld de,PREP_START
	add hl,de
	ld (sv_min),hl
	jp sv_hud_time

; Row 3: text HL in ink A at column 1, text DE in yellow at the right end.
ov_line:
	push de
	push hl
	push af
	ld a,HUD_BG
	ld b,a
	call hud_colors
	ld bc,(1<<8)+HUD_ROW3
	ld e,40
	call hud_spaces
	pop af
	ld b,HUD_BG
	call hud_colors
	pop hl
	ld bc,(1<<8)+HUD_ROW3
	call hud_text
	ld a,8
	ld b,HUD_BG
	call hud_colors
	pop hl
	push hl
	ld b,39				; column: 39 - length
.n:	ld a,(hl)
	inc hl
	inc a
	jr z,.e
	dec b
	jr .n
.e:	pop hl
	ld c,HUD_ROW3
	jp hud_text

; The stars and earnings of the day (row 2). 3 stars: nobody lost; 2:
; served at least 3 times the lost; 1: at least as many; else none.
; Earnings: money now - at the morning (after the ingredients and the
; rent): a loss in red.
ov_summary:
	ld hl,(sv_lost)
	ld de,(sv_served)
	ld c,0
	ld a,d				; nobody came: no stars
	or e
	jr z,.st
	ld a,h
	or l
	ld c,3
	jr z,.st
	ld c,0
	ex de,hl			; HL = served, DE = lost
	or a
	sbc hl,de
	jr c,.st			; fewer served than lost
	inc c
	or a
	sbc hl,de
	jr c,.st
	or a
	sbc hl,de
	jr c,.st			; served < 3 lost
	inc c
.st:	ld a,c
	ld (ov_stars),a
	ld a,8
	ld b,HUD_BG
	call hud_colors
	ld b,HUD_STARS			; three stars, the first C full
	ld c,0
.sl:	push bc
	ld a,(ov_stars)
	cp c
	ld a,G_STAR0_L
	jr z,.e
	jr c,.e
	ld a,G_STAR_L
.e:	push af
	ld c,HUD_ROW2
	call hud_char
	pop af
	pop bc
	push bc
	inc a
	inc b
	ld c,HUD_ROW2
	call hud_char
	pop bc
	inc b
	inc b
	inc b
	inc c
	ld a,c
	cp 3
	jr nz,.sl
	ld a,G_COIN_L			; earnings
	ld bc,((HUD_EARN-3)<<8)+HUD_ROW2
	call hud_char
	ld a,G_COIN_R
	ld bc,((HUD_EARN-2)<<8)+HUD_ROW2
	call hud_char
	ld hl,(sv_money)
	ld de,(sv_money0)
	or a
	sbc hl,de
	jr nc,.num
	ex de,hl			; a loss: -HL, red, a minus in front
	ld hl,0
	or a
	sbc hl,de
	push hl
	ld a,4
	ld b,HUD_BG
	call hud_colors
	pop hl
	push hl
	ld ix,ov_pow			; the minus before the first digit
	ld b,HUD_EARN+3
.dg:	ld e,(ix+0)
	ld d,(ix+1)
	ld a,d
	or e
	jr z,.mn
	push hl
	or a
	sbc hl,de
	pop hl
	jr c,.mn
	dec b
	inc ix
	inc ix
	jr .dg
.mn:	pop hl				; the number, then the minus (over
	push bc				; its leading spaces)
	ld d,5
	ld bc,(HUD_EARN<<8)+HUD_ROW2
	call hud_number
	pop bc
	ld c,HUD_ROW2
	ld hl,txt_minus
	jp hud_text
.num:	ld d,5
	ld bc,(HUD_EARN<<8)+HUD_ROW2
	jp hud_number
ov_pow:	dw 10,100,1000,10000,0

	endif
	assert $<=OVL_BASE+#800,"the overlay is too big"
	print "overlay end: ",{hex}$
