; The storage in Hard (sv_mode = 2): ingredients in 5 groups (ING_*: veg,
; meat/fish, grain, dairy, pulses; tools/recipes2asm.py dish_need), in
; units. The morning's portions take one unit of each of their groups from
; the shelves and fridges (st_stock, src/ovl/prep.asm); the portions made
; at the pass during the day take them from the hatch (st_hatch), where
; Blossom brings them. In the evening the player orders boxes from the
; supplier (st_order, the overlay); they come the next day at DELIV_MIN to
; the delivery door (st_door) and stay there until Blossom shelves them
; (what is left there at night goes off).
;
; Fire with Blossom (storage_stn, tools/buildmap.py):
;   at the door, empty-handed: a box (BOX_UNITS of a group);
;   at a shelf (fridge for meat/fish and dairy): carrying, she puts it
;     there; empty-handed, she takes BOX_UNITS of the group of that kind
;     the hatch has least of;
;   at the hatch, carrying: she leaves it there for the kitchen.
; HUD row 3 while she is the player's: the groups, the units on the
; shelves and at the hatch (grey).

BOX_UNITS	equ 5
ST_CAP		equ 60		; units of a group on the shelves / fridges
HATCH_CAP	equ 9		; (one digit on the HUD)
ST_START	equ 30		; units of each group at a new game
DELIV_MIN	equ 13*60
BOX_COST	equ 8		; the supplier's price of a box

st_stock:	ds ING_N,ST_START
st_hatch:	ds ING_N,0
st_door:	ds ING_N,0	; boxes
st_order:	ds ING_N,0	; boxes ordered for tomorrow
st_deliv:	db 0		; today's delivery came
blo_carry:	db 0		; group + 1 of what Blossom carries
blo_units:	db 0
st_kind:	db 0		; (blo_fire)

; A tick (Hard): the delivery.
storage_tick:
	ld a,(sv_mode)
	cp 2
	ret nz
	ld a,(st_deliv)
	or a
	ret nz
	ld hl,(sv_min)
	ld de,DELIV_MIN
	or a
	sbc hl,de
	ret c
	ld a,1
	ld (st_deliv),a
	ld hl,st_order
	ld de,st_door
	ld b,ING_N
.d:	ld a,(de)
	add a,(hl)
	ld (de),a
	ld (hl),0
	inc hl
	inc de
	djnz .d
	ret

; Fire with Blossom (Hard).
blo_fire:
	ld a,(sv_mode)
	cp 2
	ret nz
	ld iy,storage_stn
	ld b,SS_N
.f:	push bc
	ld e,(iy+1)
	ld d,(iy+2)
	ld hl,(blo_rec+AC_X)
	ld c,KNEAR_X
	call sv_near
	jr nc,.nx
	ld e,(iy+3)
	ld d,(iy+4)
	ld hl,(blo_rec+AC_Y)
	ld c,KNEAR_Y
	call sv_near
	jr c,.at
.nx:	ld de,5
	add iy,de
	pop bc
	djnz .f
	ret
.at:	pop bc
	ld a,(iy+0)
	cp 2
	jr z,.door
	jr nc,.hatch
	ld (st_kind),a			; a shelf (0) or a fridge (1)
	ld a,(blo_carry)
	or a
	jr z,.take
	dec a				; put it there, if it is of that kind
	call st_cold
	ld hl,st_kind
	cp (hl)
	ret nz
	ld a,(blo_carry)
	dec a
	ld hl,st_stock
	call st_add
	ld c,ST_CAP
	jr .put
.hatch:	ld a,(blo_carry)
	or a
	ret z
	dec a
	ld hl,st_hatch
	call st_add
	ld c,HATCH_CAP
.put:	ld a,(blo_units)		; (up to the room there)
	add a,(hl)
	cp c
	jr c,.p
	ld a,c
.p:	ld (hl),a
	xor a
	ld (blo_carry),a
	jp sv_hud_stock
.door:	ld a,(blo_carry)		; a box from the door
	or a
	ret nz
	ld hl,st_door
	ld b,0
.dd:	ld a,(hl)
	or a
	jr nz,.dg
	inc hl
	inc b
	ld a,b
	cp ING_N
	jr nz,.dd
	ret
.dg:	dec (hl)
	ld a,b
	inc a
	ld (blo_carry),a
	ld a,BOX_UNITS
	ld (blo_units),a
	ret
.take:	ld c,#FF			; the group of this kind with stock and
	ld b,0				; the least at the hatch
	ld e,#FF			; (E: its hatch units)
.tg:	ld a,b
	call st_cold
	ld hl,st_kind
	cp (hl)
	jr nz,.tn
	ld a,b
	ld hl,st_stock
	call st_add
	ld a,(hl)
	or a
	jr z,.tn
	ld a,b
	ld hl,st_hatch
	call st_add
	ld a,(hl)
	cp e
	jr nc,.tn
	ld e,a
	ld c,b
.tn:	inc b
	ld a,b
	cp ING_N
	jr nz,.tg
	ld a,c
	inc a
	ret z				; nothing of this kind
	ld (blo_carry),a
	ld a,c
	ld hl,st_stock
	call st_add
	ld a,(hl)
	cp BOX_UNITS
	jr c,.tl
	ld a,BOX_UNITS
.tl:	ld (blo_units),a
	ld c,a
	ld a,(hl)
	sub c
	ld (hl),a
	jp sv_hud_stock

; A = group -> A = 1 if it goes into the fridges, else 0
st_cold:
	push bc
	ld b,a
	inc b
	ld a,ING_COLD*2
.c:	rrca
	djnz .c
	and 1
	pop bc
	ret

; HL += A
st_add:
	add a,l
	ld l,a
	ret nc
	inc h
	ret

; Can the ingredients of dish A be taken from table HL (st_stock or
; st_hatch)? Z if yes; then st_take takes them.
st_have:
	call st_need
.h:	srl c
	jr nc,.n
	ld a,(hl)
	or a
	jr z,.no
.n:	inc hl
	djnz .h
	xor a
	ret
.no:	or 1
	ret
st_take:
	call st_need
.t:	srl c
	jr nc,.n
	dec (hl)
.n:	inc hl
	djnz .t
	ret
; the same, giving them back
st_back:
	call st_need
.b:	srl c
	jr nc,.n
	inc (hl)
.n:	inc hl
	djnz .b
	ret
; C = dish_need of dish A, B = ING_N
st_need:
	push hl
	ld hl,dish_need
	call st_add
	ld c,(hl)
	ld b,ING_N
	pop hl
	ret

; HUD row 3 from column 12 while Blossom is the player's: each group, its
; units on the shelves (in its colour) and at the hatch (grey).
st_hud:
	ld a,HUD_BG
	ld b,a
	call hud_colors
	ld bc,(HUD_ING<<8)+HUD_ROW3
	ld e,40
	call hud_spaces
	ld c,0
.g:	push bc
	ld hl,ing_ink
	ld a,c
	call st_add
	ld a,(hl)
	ld b,HUD_BG
	call hud_colors
	pop bc
	push bc
	ld a,c				; column: HUD_ING + 5 g
	add a,a
	add a,a
	add a,c
	add a,HUD_ING
	ld b,a
	ld a,c
	add a,a
	add a,G_ING0
	push bc
	push af
	ld c,HUD_ROW3
	call hud_char
	pop af
	pop bc
	inc a
	inc b
	push bc
	ld c,HUD_ROW3
	call hud_char
	pop bc
	inc b
	push bc
	ld a,c
	ld hl,st_stock
	call st_add
	ld l,(hl)
	ld h,0
	ld d,2
	ld c,HUD_ROW3
	call hud_number
	ld a,12
	ld b,HUD_BG
	call hud_colors
	pop bc
	inc b
	inc b
	ld a,c
	ld hl,st_hatch
	call st_add
	ld l,(hl)
	ld h,0
	ld d,1
	ld c,HUD_ROW3
	call hud_number
	pop bc
	inc c
	ld a,c
	cp ING_N
	jr nz,.g
	ret
HUD_ING		equ 12
