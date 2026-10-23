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
	ifndef DEMO			; (-DDEMO=1 from the Makefile's EXTRA)
DEMO	equ 0
	endif

	org OVL_BASE
	if SERVICE==0			; (test builds without the service)
	ret
	else
	jp ov_init
	jp ov_tick

	include "lvl1_patch.asm"	; the expansion (tools/maps2asm.py)

PREP_START	equ 10*60	; the morning
PREP_MIN	equ 120
PORTION_MAX	equ 9		; per dish (one digit)
OV_COL		equ 8		; HUD row 2: dish d at column OV_COL + 4 d
OV_COST		equ 2+TXT_COST_LEN	; row 3: cost and price of the dish
OV_PRICE	equ OV_COST+3+TXT_PRICE_LEN
	if 6+TXT_EXP_LEN+TXT_DOWN_LEN+5<39-TXT_NEXT_LEN	; the evening: the recipe
OV_RCCOL	equ 6+TXT_EXP_LEN		; after the room's price
	else
OV_RCCOL	equ 5+TXT_EXP_LEN		; (no space: Greek)
	endif
	assert OV_RCCOL+TXT_DOWN_LEN+5<39-TXT_NEXT_LEN,"row 3: the two offers do not fit"

ov_cur:		db 0		; the dish chosen
ov_sel:		db 0		; the first morning: Easy, Medium or Hard first
ov_sup:		db 0		; Hard, the evening: the supplier's order
ov_scur:	db 0		; its group
ov_used:	db 0		; minutes of the morning used
ov_stars:	db 0

ov_init:
	ld a,(sv_phase)
	cp SP_PREP
	jp z,ov_first			; (the first day)
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
	; fall through
; Row 3 of the evening: the day over; on offer if affordable the expansion
; (up) and the next recipe (down: src/game/menu.asm).
ov_evening:
	ld a,(sv_exp)
	or a
	jr nz,.n
	ld hl,(sv_money)
	ld de,EXP_COST
	or a
	sbc hl,de
	jr c,.n
	ld a,8
	ld hl,txt_exp
	ld de,txt_next
	call ov_line
	ld hl,EXP_COST
	ld d,3
	ld bc,((2+TXT_EXP_LEN)<<8)+HUD_ROW3
	call hud_number
	ld b,OV_RCCOL
	jr ov_rcdraw
.n:	call ov_rcprice
	ld a,13
	ld hl,txt_day_end
	jr c,.d
	ld hl,txt_down
.d:	ld de,txt_next
	call ov_line
	ld b,1
	; fall through
; The recipe on offer at column B of row 3: down, its icon, its price.
ov_rcdraw:
	call ov_rcprice
	ret c
	ld a,b
	ld (ov_rcol),a
	ld a,13
	ld b,HUD_BG
	call hud_colors
	ld a,(ov_rcol)
	ld b,a
	ld c,HUD_ROW3
	ld hl,txt_down
	call hud_text
	call ov_rcicon
	ld a,(ov_rcol)
	add a,TXT_DOWN_LEN		; (no space: room for both offers
	ld b,a				; in Greek too)
	call ov_rcchar
	ld a,8
	ld b,HUD_BG
	call hud_colors
	call ov_rcprice
	ld a,(ov_rcol)
	add a,TXT_DOWN_LEN+2
	ld b,a
	ld c,HUD_ROW3
	ld d,3
	jp hud_number
; The next recipe's icon in G_NEW, its ink set.
ov_rcicon:
	ld a,(rc_cnt)
	call rc_show
	ld a,(rc_cnt)
	ld hl,rc_ink
	call st_add
	ld a,(hl)
	ld b,HUD_BG
	jp hud_colors
; G_NEW at columns B, B+1 of row 3.
ov_rcchar:
	ld c,HUD_ROW3
	push bc
	ld a,G_NEW_L
	call hud_char
	pop bc
	inc b
	ld a,G_NEW_R
	jp hud_char
; Carry: no recipe on offer (one bought already, none left, too dear);
; else HL = its price.
ov_rcprice:
	ld a,(rc_new)
	or a
	scf
	ret nz
	ld a,(rc_cnt)
	cp RC_N
	ccf
	ret c
	ld hl,RC_COST0
	ld de,RC_STEP
	inc a
.p:	dec a
	jr z,.m
	add hl,de
	jr .p
.m:	push hl
	ex de,hl
	ld hl,(sv_money)
	or a
	sbc hl,de
	pop hl
	ret
ov_rcol:	db 0

; Down in the evening: the recipe bought (on the menu in the morning).
ov_rcbuy:
	call ov_rcprice
	ret c
	ex de,hl
	ld hl,(sv_money)
	or a
	sbc hl,de
	ld (sv_money),hl
	call sv_hud_money
	ld a,1
	ld (rc_new),a
	jp ov_evening

; Up in the evening: the expansion bought (its map, its tables).
ov_buy:
	ld a,(sv_exp)
	or a
	ret nz
	ld hl,(sv_money)
	ld de,EXP_COST
	or a
	sbc hl,de
	ret c
	ld (sv_money),hl
	call sv_hud_money
	ld a,1
	ld (sv_exp),a
	ld hl,patch_open
	xor a				; the tables free
	call ov_patch
	call ov_evening
	jr ov_view

; A new game: the expansion closed again.
ov_unbuy:
	ld a,(sv_exp)
	or a
	ret z
	xor a
	ld (sv_exp),a
	ld hl,patch_close
	ld a,TB_LOCKED
	call ov_patch
ov_view:
	ld a,1				; (the main loop draws the view again)
	ld (view_req),a
	ret

; Apply map patch HL (tools/maps2asm.py) and set the expansion's tables to A.
ov_patch:
	push af
.e:	ld e,(hl)
	inc hl
	ld d,(hl)
	inc hl
	ld a,d
	and e
	inc a
	jr z,.t
	push hl
	ld hl,map_data
	add hl,de
	ex de,hl
	pop hl
	ld b,(hl)			; metatiles in the row
	inc hl
.r:	ld c,(hl)			; runs: count, metatile
	inc hl
	ld a,(hl)
	inc hl
.f:	ld (de),a
	inc de
	dec b
	dec c
	jr nz,.f
	ld a,b
	or a
	jr nz,.r
	jr .e
.t:	pop af
	ld hl,tb_busy
	ld b,TB_LOCK_N
.l:	ld (hl),a
	inc hl
	djnz .l
	ret

; The boot: the title screen (TITLE.SCR, tools/mktitle.py: 16K less 128
; bytes, with its header 32 whole sectors for fdc_load) until fire,
; then the first morning. (Not in the DEMO builds: no one presses fire.)
ov_first:
	if DEMO==0
	di
	call crtc_plain			; (black while it loads)
.try:	ld hl,ov_tname
	ld de,#C000-AREA_HDR		; (with it 32 whole sectors, to &FFFF)
	call fdc_load
	jr c,.try
	call wait_vsync
	ld hl,#3000			; a standard frame of &C000
	call crtc_set_ma
	ld bc,#BC09			; R9 = 7
	out (c),c
	ld bc,#BD07
	out (c),c
	ld hl,palette_hw
	call set_palette
	ifdef TITLE_WAIT		; test: TITLE_WAIT VBLs instead of fire
	ld b,TITLE_WAIT
.tw:	push bc
	call wait_vsync
	pop bc
	djnz .tw
	jr .end
	endif
.up:	call read_input			; fire: pressed and let go
	and 1<<KEY_FIRE
	jr nz,.up
.dn:	call read_input
	and 1<<KEY_FIRE
	jr z,.dn
.up2:	call read_input
	and 1<<KEY_FIRE
	jr nz,.up2
.end:	call view_restart		; the game's view again (interrupts on)
	ld bc,GA_PORT*256+RAM_C5	; (it leaves the base RAM at &4000)
	out (c),c
	endif
	jp ov_morning
	if DEMO==0
ov_tname:	db "TITLE   SCR"
	endif

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
	jp z,ov_keys
	ld a,(ov_sup)			; the supplier (Hard, the evening)
	or a
	jp nz,ov_sup_keys
	ld a,(sv_phase)			; up: the expansion
	cp SP_OVER
	jr nz,.f
	bit KEY_UP,c
	jp nz,ov_buy
	bit KEY_DOWN,c
	jp nz,ov_rcbuy
.f:	bit KEY_FIRE,c
	ret z
	ld a,(sv_phase)
	cp SP_BROKE
	jr z,.new
	ld a,(sv_mode)
	cp 2
	jp z,ov_supplier
	jr ov_morning
.new:	call ov_unbuy
	call rc_reset			; (the first menu again)
	ld hl,START_MONEY		; a new game
	ld (sv_money),hl
	xor a
	ld (sv_day),a
	ld hl,st_stock			; (Hard: the storage as at the start)
	ld b,ING_N
.st:	ld (hl),ST_START
	inc hl
	djnz .st
	ld b,ING_N*3			; st_hatch, st_door, st_order
.sz:	ld (hl),a
	inc hl
	djnz .sz
	; fall through

; The morning of the next day.
ov_morning:
	ifdef TEST_EXP			; test: the expansion bought at once
	ld hl,9999
	ld (sv_money),hl
	call ov_buy
	endif
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
	ld (ctl_who),a			; the day starts with Bill
	ld (lib_carry),a		; the kitchen empty
	ld (blo_carry),a		; (Hard: what stayed at the door went off)
	ld a,#FE
	ld (st_wlast),a			; (the warning drawn again)
	xor a
	ld (st_deliv),a
	ld hl,st_door
	ld b,ING_N
.dr:	ld (hl),a
	inc hl
	djnz .dr
	ld hl,bill_x
	ld (ctl_rec),hl
	ld hl,ks_slots
	ld b,KS_SIZE
.k:	ld (hl),a
	inc hl
	djnz .k
	ld (sv_menu),a
	ld hl,0
	ld (sv_cook_t),hl
	ld hl,sv_stock			; and sv_cook (portions cooking)
	ld b,DISH_N*2
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
	ld a,(sv_day)			; the first morning: Easy or Medium
	dec a
	jr nz,ov_rcmorn
	inc a
	ld (ov_sel),a
	call ov_draw
	jp ov_mode

; A recipe bought: row 3 shows it; left/right the dish it replaces, fire.
ov_rcmorn:
	ld a,(rc_new)
	or a
	jr z,ov_prepline
	ld a,13
	ld hl,txt_new
	ld de,txt_mode_ok
	call ov_line
	call ov_rcicon
	ld b,2+TXT_NEW_LEN
	call ov_rcchar
	jp ov_draw

; Row 3 of the morning: cost and price of the dish, fire: open.
ov_prepline:
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

; Easy, Medium or Hard (row 3): left/right, fire.
ov_mode:
	ld a,0
	call .ink
	ld hl,txt_mode_easy
	ld de,txt_mode_ok
	call ov_line
	ld a,1
	call .ink
	ld b,HUD_BG
	call hud_colors
	ld hl,txt_mode_medium
	ld bc,((2+TXT_MODE_EASY_LEN)<<8)+HUD_ROW3
	call hud_text
	ld a,2
	call .ink
	ld b,HUD_BG
	call hud_colors
	ld hl,txt_mode_hard
	ld bc,((3+TXT_MODE_EASY_LEN+TXT_MODE_MEDIUM_LEN)<<8)+HUD_ROW3
	jp hud_text
.ink:	ld b,a				; A = mode -> A = yellow if chosen, grey
	ld a,(sv_mode)
	cp b
	ld a,8
	ret z
	ld a,12
	ret

ov_keys:
	ld a,(ov_sel)
	or a
	jr z,.prep
	ld a,(sv_mode)
	bit KEY_RIGHT,c
	jr z,.l
	inc a
	cp 3
	jr c,.md
	xor a
	jr .md
.l:	bit KEY_LEFT,c
	jr z,.ok
	dec a
	jp p,.md
	ld a,2
.md:	ld (sv_mode),a
	jp ov_mode
.ok:	bit KEY_FIRE,c
	ret z
	xor a
	ld (ov_sel),a
	call ov_prepline
	ret
.prep:	ld hl,ov_cur
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
.u:	ld a,(rc_new)			; a recipe bought: fire puts it there
	or a
	jr z,.pp
	bit KEY_FIRE,c
	ret z
	ld a,(hl)
	call rc_place
	jp ov_prepline
.pp:	ld e,(hl)			; DE = the dish
	ld d,0
	bit KEY_UP,c
	jr nz,ov_more
	bit KEY_DOWN,c
	jp nz,ov_less
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
	ld a,(sv_mode)			; Hard: its ingredients from the storage
	cp 2
	jr nz,.money
	push hl
	ld a,e
	ld hl,st_stock
	call st_have
	jr nz,.no2
	ld a,e
	ld hl,st_stock
	call st_take
	pop hl
	jr .ok
.no2:	pop hl
	jr .no
.money:	push hl
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
.ok:	inc (hl)
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
	ld a,(sv_mode)			; Hard: the ingredients back
	cp 2
	jr nz,.money
	ld a,e
	ld hl,st_stock
	call st_back
	jr ov_draw
.money:	ld hl,dish_cost
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
	ld a,(rc_new)			; (a recipe to place: its line stays)
	or a
	jp nz,sv_hud_money
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
	ld a,(sv_mode)			; (Hard: the storage's, no money)
	cp 2
	jr nz,.c
	ld l,h
.c:	ld d,1
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

	assert $<=SAVE_AREA1,"the overlay's first half is too big"
	print "overlay, first half: ",{hex}$
	org OVL_HI			; (the other half: src/game/area.asm)

; The supplier (Hard, after the summary): boxes of each group for tomorrow
; (BOX_UNITS units, BOX_COST each, up to 9). Row 2: each group, its units
; on the shelves (grey) and the boxes ordered; row 3: the price of a box.
ov_supplier:
	ld a,1
	ld (ov_sup),a
	xor a
	ld (ov_scur),a
	ld a,13
	ld hl,txt_order
	ld de,txt_mode_ok
	call ov_line
	ld a,8
	ld b,HUD_BG
	call hud_colors
	ld hl,BOX_COST
	ld d,2
	ld bc,((2+TXT_ORDER_LEN)<<8)+HUD_ROW3
	call hud_number
	; fall through
ov_sup_draw:
	ld a,HUD_BG
	ld b,a
	call hud_colors
	ld bc,(OV_COL<<8)+HUD_ROW2
	ld e,40
	call hud_spaces
	ld c,0
.g:	push bc
	ld hl,ing_ink			; the chosen one in its colour
	call st_add_c
	ld a,(ov_scur)
	cp c
	ld a,(hl)
	jr z,.i
	ld a,12
.i:	ld b,HUD_BG
	call hud_colors
	pop bc
	push bc
	ld a,c				; column OV_COL + 6 g
	add a,a
	add a,c
	add a,a
	add a,OV_COL
	ld b,a
	ld a,c
	add a,a
	add a,G_ING0
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
	ld a,12
	ld b,HUD_BG
	call hud_colors
	pop bc
	inc b
	push bc
	ld hl,st_stock
	call st_add_c
	ld l,(hl)
	ld h,0
	ld d,2
	ld c,HUD_ROW2
	call hud_number
	ld a,8
	ld b,HUD_BG
	call hud_colors
	pop bc
	inc b
	inc b
	ld hl,st_order
	call st_add_c
	ld l,(hl)
	ld h,0
	ld d,1
	ld c,HUD_ROW2
	call hud_number
	pop bc
	inc c
	ld a,c
	cp ING_N
	jr nz,.g
	jp sv_hud_money
; HL += C (the group)
st_add_c:
	ld a,c
	jp st_add

ov_sup_keys:
	ld hl,ov_scur
	bit KEY_LEFT,c
	jr z,.r
	ld a,(hl)
	dec a
	jp p,.w
	ld a,ING_N-1
	jr .w
.r:	bit KEY_RIGHT,c
	jr z,.u
	ld a,(hl)
	inc a
	cp ING_N
	jr c,.w
	xor a
.w:	ld (hl),a
	jp ov_sup_draw
.u:	ld a,(hl)
	push bc
	ld c,a
	ld hl,st_order
	call st_add_c
	pop bc
	bit KEY_UP,c
	jr z,.d
	ld a,(hl)			; a box more, if the money is there
	cp 9
	ret nc
	push hl
	ld hl,(sv_money)
	ld de,BOX_COST
	or a
	sbc hl,de
	pop de
	ret c
	ld (sv_money),hl
	ex de,hl
	inc (hl)
	jp ov_sup_draw
.d:	bit KEY_DOWN,c
	jr z,.f
	ld a,(hl)
	or a
	ret z
	dec (hl)
	ld hl,(sv_money)
	ld de,BOX_COST
	add hl,de
	ld (sv_money),hl
	jp ov_sup_draw
.f:	bit KEY_FIRE,c
	ret z
	xor a
	ld (ov_sup),a
	jp ov_morning

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

	include "ovl/menu.asm"		; the recipes bought (src/game/menu.asm)
	endif
	assert $<=OVL_HI+#800,"the overlay is too big"
	print "overlay end: ",{hex}$
