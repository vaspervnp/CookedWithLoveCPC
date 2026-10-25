; The hired cooks (sv_exp EXP_COOK, then EXP_COOK2; Medium and Hard, hired in the evening:
; src/ovl/prep.asm; his wage with the rent): Liberty's figure (drawn while
; the kitchen's area is loaded), on his own. He waits at the pass (Liberty's
; spot there); a plate done (or burnt) at a station, or a free station with
; a dish of its kind waiting: he walks there (tools/buildmap.py cook_paths:
; HP_CKP, hw_walk), starts it (lib_start) and waits for it, takes the plate
; (ks_take), walks back and leaves it at the pass (ks_place). The second
; waits above the first; neither goes to a station the other walks to or
; stands at (ck_taken).

	if DEMO==0
CK_AT		equ 4		; HW_STATE: at the station
CK_WAGE		equ 20
CK_HIRE		equ 100
CR_CARRY	equ HW_SIZE	; a cook's record: then his carry block (as
CR_STN		equ HW_SIZE+4	; lib_carry), his station
CR_SIZE		equ HW_SIZE+5

ck_rec:		ds HW_SIZE,0	; (by name for the tests)
ck_carry:	ds 4,0
ck_stn:		db 0
	assert $-ck_rec==CR_SIZE
	; ck2_rec, ck_wait, ck_cur: src/game/vars.asm

; A tick of the service.
ck_tick:
	ld hl,ck_wait			; (their search: twice a second)
	dec (hl)
	jp p,.t
	ld (hl),25
.t:	ld ix,ck_rec
	call .one
	ld ix,ck2_rec
.one:	ld (ck_cur),ix
	ld a,(ix+HW_STATE)
	or a
	ret z
	dec a
	jr z,.home
	cp CK_AT-1
	jr z,.at
	call hw_walk
	ret nz
	ld a,(ix+HW_STATE)
	cp WT_GO
	ld (ix+HW_STATE),CK_AT
	ret z
	call hw_home			; back: his plate at the pass
	ld a,(ix+CR_CARRY)
	or a
	ret z
	call ck_iy
	jp ks_place
.at:	ld a,(ix+CR_STN)		; its station (IY) and slot (IX)
	push af
	call ks_stn
	pop af
	call ks_slot
	ld a,(ix+KQ_ST)
	dec a
	ret z				; cooking: he waits
	jp p,.take
	call lib_start			; free: a dish of its kind, if any
	ld a,(ix+KQ_ST)
	or a
	ret nz
	jr .back
.take:	push ix
	ld ix,(ck_cur)
	call ck_iy
	pop ix
	call ks_take
.back:	ld ix,(ck_cur)
	ld (ix+HW_STATE),WT_BACK
	ret
.home:	ld a,(ck_wait)
	or a
	ret nz
	call ks_count
	ld ix,ks_slots			; a plate done or burnt, or a free one
	ld c,0				; with a dish of its kind waiting
.f:	call ck_taken
	jr z,.fn
	ld a,(ix+KQ_ST)
	cp 2
	jr nc,.go
	or a
	jr nz,.fn
	ld a,c
	add a,a
	add a,c
	add a,HP_KS
	call hp_get
	ld (ks_type),a
	push bc
	call ks_find
	pop bc
	jr nz,.go
.fn:	ld de,KQ_SIZE
	add ix,de
	inc c
	ld a,c
	cp b
	jr nz,.f
	ret
.go:	ld ix,(ck_cur)
	ld (ix+CR_STN),c
	ld a,c
	add a,HP_CKP
	jp hw_go

; IY = the carry block of cook IX.
ck_iy:
	push ix
	pop iy
	ld de,CR_CARRY
	add iy,de
	ret

; Z if station C is a cook's (going there or there).
ck_taken:
	ld hl,ck_rec+HW_STATE
	call .t
	ret z
	ld hl,ck2_rec+HW_STATE
.t:	ld a,(hl)
	cp WT_GO
	jr z,.s
	cp CK_AT
	ret nz
.s:	ld de,CR_STN-HW_STATE
	add hl,de
	ld a,(hl)
	cp c
	ret

; Their sprites, a plate over one carrying (in the kitchen's area).
ck_sprites:
	ld a,(area_cur)
	cp AREA_KITCHEN
	ret nz
	ld ix,ck_rec
	call .one
	ld ix,ck2_rec
.one:	ld a,(ix+HW_STATE)
	or a
	ret z
	ld hl,liberty_frames
	call ac_frame
	push hl
	call spr_visible
	pop hl
	ret nc
	push de
	push bc
	push ix
	call sprites_add
	pop ix
	pop bc
	pop de
	ld a,(ix+CR_CARRY)
	or a
	ret z
	ld a,MOOD_FOOD
	jp bubble_a
	else
ck_tick:
ck_sprites:
	ret
CK_WAGE		equ 0
CK_HIRE		equ 0
	endif
