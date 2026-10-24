; The hired cook (sv_exp EXP_COOK, Medium and Hard, hired in the evening:
; src/ovl/prep.asm; his wage with the rent): Liberty's figure (drawn while
; the kitchen's area is loaded), on his own. He waits at the pass (Liberty's
; spot there); a plate done (or burnt) at a station, or a free station with
; a dish of its kind waiting: he walks there (tools/buildmap.py cook_paths:
; HP_CKP, hw_walk), starts it (lib_start) and waits for it, takes the plate
; (ks_take), walks back and leaves it at the pass (ks_place).

	if DEMO==0
CK_AT		equ 4		; HW_STATE: at the station
CK_WAGE		equ 20
CK_HIRE		equ 100

	; ck_rec, ck_carry, ck_stn, ck_wait: src/game/vars.asm

; A tick of the service.
ck_tick:
	ld ix,ck_rec
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
	ld a,(ck_carry)
	or a
	ret z
	ld iy,ck_carry
	jp ks_place
.at:	ld a,(ck_stn)			; its station (IY) and slot (IX)
	call ks_stn
	ld a,(ck_stn)
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
.take:	ld iy,ck_carry
	call ks_take
.back:	ld a,WT_BACK
	ld (ck_rec+HW_STATE),a
	ret
.home:	ld hl,ck_wait			; (twice a second)
	dec (hl)
	ret nz
	ld (hl),25
	call ks_count
	ld ix,ks_slots			; a plate done or burnt, or a free one
	ld c,0				; with a dish of its kind waiting
.f:	ld a,(ix+KQ_ST)
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
.go:	ld a,c
	ld (ck_stn),a
	ld ix,ck_rec
	add a,HP_CKP
	jp hw_go

; His sprite, a plate over him if he carries one (in the kitchen's area).
ck_sprites:
	ld a,(ck_rec+HW_STATE)
	or a
	ret z
	ld a,(area_cur)
	cp AREA_KITCHEN
	ret nz
	ld ix,ck_rec
	ld hl,liberty_frames
	call ac_frame
	push hl
	call spr_visible
	pop hl
	ret nc
	push de
	push bc
	call sprites_add
	pop bc
	pop de
	ld a,(ck_carry)
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
