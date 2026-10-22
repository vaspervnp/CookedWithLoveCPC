; The kitchen in Medium (sv_mode = 1): Liberty cooks the orders. Each dish
; has its station (dish_stn: stove or oven, tools/recipes2asm.py); the
; level's stoves and ovens are kitchen_stn (tools/buildmap.py), each a
; place for one dish (ks_slots). Fire with Liberty:
;   at a free station: the oldest order's next dish of its kind starts
;     there (cooks by itself for its dish_ticks; done, it waits BURN_T,
;     then it burns);
;   at a done (or burnt) one: she takes the plate (a plate bubble on her);
;   at the pass: she leaves it; an order whose dishes are all there is
;     ready for Bill. A burnt dish costs the group patience (the tip) when served.
; Over each busy station a bubble: ... cooking, the plate when done,
; angry when burnt. In Easy the kitchen stays automatic (service.asm).

KQ_ST		equ 0		; 0 free, 1 cooking, 2 done, 3 burnt
KQ_DISH		equ 1
KQ_GRP		equ 2		; group + 1
KQ_ORD		equ 3		; its order number (GR_ORD)
KQ_T		equ 4		; ticks left (word)
KQ_SIZE		equ 6
KS_SIZE		equ KS_N*KQ_SIZE
BURN_T		equ 500		; done: 10 s before it burns
KNEAR_X		equ 20		; Liberty's feet to a station's centre
KNEAR_Y		equ 26

sv_mode:	db TEST_MODE	; 0 Easy, 1 Medium, 2 Hard (the first morning)
sv_ordseq:	db 0		; order numbers (GR_ORD)
ks_slots:	ds KS_SIZE,0
lib_carry:	db 0		; group + 1 of the plate Liberty carries
lib_cdish:	db 0
lib_cord:	db 0
lib_cburnt:	db 0
ks_type:	db 0		; (lib_start)
ks_age:		db 0
ks_bg:		dw 0
ks_bm:		db 0
ks_bd:		db 0

; A tick of the stations.
kitchen_tick:
	ld a,(sv_mode)
	or a
	ret z
	ld ix,ks_slots
	ld b,KS_N
.s:	ld a,(ix+KQ_ST)
	or a
	jr z,.n
	cp 3
	jr z,.n				; burnt: stays so
	ld l,(ix+KQ_T)
	ld h,(ix+KQ_T+1)
	dec hl
	ld (ix+KQ_T),l
	ld (ix+KQ_T+1),h
	ld a,h
	or l
	jr nz,.n
	inc (ix+KQ_ST)			; cooking -> done -> burnt
	ld a,SFX_DONE+2			; done: SFX_DONE, burnt: SFX_BURN
	sub (ix+KQ_ST)
	call sfx_play
	ld (ix+KQ_T),BURN_T&255
	ld (ix+KQ_T+1),BURN_T>>8
.n:	ld de,KQ_SIZE
	add ix,de
	djnz .s
	ret

; Fire with Liberty (Medium).
lib_fire:
	ld a,(sv_mode)
	or a
	ret z
	ld a,(lib_carry)		; carrying: the pass
	or a
	jr z,.stn
	ld hl,(lib_rec+AC_X)
	ld de,PASS_KX
	ld c,KNEAR_X
	call sv_near
	ret nc
	ld hl,(lib_rec+AC_Y)
	ld de,PASS_BY
	ld c,KNEAR_Y
	call sv_near
	ret nc
	jp lib_place
.stn:	ld iy,kitchen_stn		; a station by her
	ld ix,ks_slots
	ld b,KS_N
.f:	push bc
	ld e,(iy+1)
	ld d,(iy+2)
	ld hl,(lib_rec+AC_X)
	ld c,KNEAR_X
	call sv_near
	jr nc,.nx
	ld e,(iy+3)
	ld d,(iy+4)
	ld hl,(lib_rec+AC_Y)
	ld c,KNEAR_Y
	call sv_near
	jr c,.at
.nx:	ld de,5
	add iy,de
	ld de,KQ_SIZE
	add ix,de
	pop bc
	djnz .f
	ret
.at:	pop bc
	ld a,(ix+KQ_ST)
	or a
	jr z,lib_start
	cp 2
	ret c				; still cooking
	sub 2				; done or burnt: she takes it
	ld (lib_cburnt),a
	ld a,(ix+KQ_DISH)
	ld (lib_cdish),a
	ld a,(ix+KQ_ORD)
	ld (lib_cord),a
	ld a,(ix+KQ_GRP)
	ld (lib_carry),a
	ld (ix+KQ_ST),0
	ret

; Station IY (its slot IX) is free: the dish of its kind waiting longest.
lib_start:
	ld a,(iy+0)
	ld (ks_type),a
	xor a
	ld (ks_age),a
	push ix
	ld ix,groups
	ld b,G_MAX
.g:	ld a,(ix+GR_STATE)
	cp GS_ORDERED
	jr nz,.gn
	ld a,(sv_ordseq)		; age = order numbers since
	sub (ix+GR_ORD)
	ld c,a
	ld a,(ks_age)
	cp c
	jr nc,.gn			; not older than the best one
	push ix
	pop hl
	ld de,GR_DISH
	add hl,de
	ld e,(ix+GR_N)
	ld d,1				; member bit (started: GR_KIT bits 0-3)
.m:	ld a,(ix+GR_KIT)
	and d
	jr nz,.mn
	ld a,(hl)
	call dish_station
	push hl
	ld hl,ks_type
	cp (hl)
	pop hl
	jr z,.fd
.mn:	inc hl
	sla d
	dec e
	jr nz,.m
	jr .gn
.fd:	ld a,c
	ld (ks_age),a
	ld (ks_bg),ix
	ld a,d
	ld (ks_bm),a
	ld a,(hl)
	ld (ks_bd),a
.gn:	ld de,GR_SIZE
	add ix,de
	djnz .g
	pop ix
	ld a,(ks_age)
	or a
	ret z				; nothing of this kind to cook
	ld iy,(ks_bg)
	ld a,(ks_bm)
	or (iy+GR_KIT)
	ld (iy+GR_KIT),a
	ld a,(iy+GR_ORD)
	ld (ix+KQ_ORD),a
	ld a,(ks_bd)
	ld (ix+KQ_DISH),a
	add a,a
	ld e,a
	ld d,0
	ld hl,dish_ticks
	add hl,de
	ld a,(hl)
	ld (ix+KQ_T),a
	inc hl
	ld a,(hl)
	ld (ix+KQ_T+1),a
	push iy				; group + 1 = (IY - groups) / 16 + 1
	pop hl
	ld de,groups
	or a
	sbc hl,de
	ld a,l
	rrca
	rrca
	rrca
	rrca
	and #0F
	inc a
	ld (ix+KQ_GRP),a
	ld (ix+KQ_ST),1
	ret

; A = dish -> A = its station kind
dish_station:
	push hl
	ld hl,dish_stn
	add a,l
	ld l,a
	ld a,h
	adc a,0
	ld h,a
	ld a,(hl)
	pop hl
	ret

; Liberty leaves her plate at the pass: the dish of its order is there; all
; of them: the order is ready. (The group gone, or a new one there: lost.)
lib_place:
	ld a,(lib_carry)
	dec a
	add a,a
	add a,a
	add a,a
	add a,a
	ld e,a
	ld d,0
	ld ix,groups
	add ix,de
	xor a
	ld (lib_carry),a
	ld a,(ix+GR_STATE)
	cp GS_ORDERED
	ret nz
	ld a,(lib_cord)
	cp (ix+GR_ORD)
	ret nz
	push ix
	pop hl
	ld de,GR_DISH
	add hl,de
	ld b,(ix+GR_N)
	ld d,1				; started bit; placed: d << 4
.m:	ld a,(lib_cdish)
	cp (hl)
	jr nz,.mn
	ld a,(ix+GR_KIT)
	and d
	jr z,.mn
	ld a,d
	rlca
	rlca
	rlca
	rlca
	ld e,a
	ld a,(ix+GR_KIT)
	and e
	jr z,.pl
.mn:	inc hl
	sla d
	djnz .m
	ret
.pl:	ld a,(ix+GR_KIT)
	or e
	ld (ix+GR_KIT),a
	ld a,(lib_cburnt)		; burnt: patience (the tip) down when
	or a				; served (GR_BURNT, src/game/service.asm)
	jr z,.ok
	inc (ix+GR_BURNT)
.ok:	ld b,(ix+GR_N)			; all placed?
	xor a
.b:	scf
	rla
	djnz .b
	rlca
	rlca
	rlca
	rlca
	ld c,a
	ld a,(ix+GR_KIT)
	and c
	cp c
	jp nz,sv_hud_tickets		; (the dish in colour on its ticket)
	ld (ix+GR_STATE),GS_READY
	ld a,SFX_READY
	call sfx_play
	jp sv_hud_tickets

; The bubbles over the busy stations.
kitchen_sprites:
	ld a,(sv_mode)
	or a
	ret z
	ld ix,ks_slots
	ld iy,kitchen_stn
	ld b,KS_N
.s:	ld a,(ix+KQ_ST)
	or a
	jr z,.n
	push bc
	ld hl,ks_mood-1
	add a,l
	ld l,a
	ld a,h
	adc a,0
	ld h,a
	ld a,(hl)
	ld l,(iy+1)			; left = centre - 16, top = centre - 8
	ld h,(iy+2)
	ld de,-16
	add hl,de
	ex de,hl
	ld l,(iy+3)
	ld h,(iy+4)
	ld bc,-8
	add hl,bc
	ld b,h
	ld c,l
	push ix
	push iy
	call bubble_a
	pop iy
	pop ix
	pop bc
.n:	ld de,KQ_SIZE
	add ix,de
	ld de,5
	add iy,de
	djnz .s
	ret
ks_mood:	db MOOD_WAIT,MOOD_FOOD,MOOD_ANGRY
