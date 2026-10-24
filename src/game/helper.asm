; The storage helper (sv_exp EXP_HELPER, Hard, hired in the evening:
; src/ovl/prep.asm; his wage with the rent): Blossom's figure (drawn while
; the storage's area is loaded), on his own. He waits beside the hatch;
; boxes at the door: he takes one there and puts it on the nearest shelf
; (fridge) of its kind; else, a group with room for a box at the hatch and
; units on the shelves: he takes units from the nearest shelf (fridge) of
; its kind and leaves them at the hatch. There he does what Blossom does
; (blo_at, with his carry in hers). His ways (tools/buildmap.py
; helper_paths, HP_HLP) go home - place - home, by the kind of the place.

	if DEMO==0
HL_WAGE		equ 20
HL_HIRE		equ 100

hl_rec:		ds HW_SIZE,0
hl_carry:	db 0		; as blo_carry, blo_units
hl_units:	db 0
hl_src:		db 0		; what he carries is from the door (to a shelf)
hl_kind:	db 0		; where he walks: 0 shelf, 1 fridge, 2 door, 3 hatch
hl_wait:	db 1

; A tick of the service.
hl_tick:
	ld ix,hl_rec
	ld a,(ix+HW_STATE)
	or a
	ret z
	dec a
	jr z,.home
	call hw_walk
	ret nz
	ld (ix+AC_MOV),0
	ld a,(ix+HW_STATE)
	cp WT_GO
	jp nz,hw_home
	ld (ix+HW_STATE),WT_BACK	; there: as Blossom, then back
	ld a,(hl_kind)			; the place: its index in HP_SS
	add a,HP_HLS
	call hp_get2
	ld e,a
	add a,a
	add a,e
	add a,HP_SS
	call stn_first
	call hl_swap
	call blo_at
	jr hl_swap
.home:	ld hl,hl_wait			; (twice a second)
	dec (hl)
	ret nz
	ld (hl),25
	ld a,(hl_carry)
	or a
	jr z,.free
	ld a,(hl_src)			; carrying: from the door to its shelf,
	or a				; from a shelf to the hatch
	ld a,3
	jr z,.go
	ld a,(hl_carry)
	dec a
	call st_cold
	jr .go
.free:	ld hl,st_door			; boxes at the door?
	ld b,ING_N
	xor a
.d:	or (hl)
	inc hl
	djnz .d
	ld (hl_src),a
	or a
	ld a,2
	jr nz,.go
	ld b,0				; a group with room for a box at the
.h:	ld a,b				; hatch and units on the shelves
	ld hl,st_hatch
	call st_add
	ld a,(hl)
	cp HATCH_CAP-BOX_UNITS+1
	jr nc,.hn
	ld a,b
	ld hl,st_stock
	call st_add
	ld a,(hl)
	or a
	ld a,b
	jp nz,.k
.hn:	inc b
	ld a,b
	cp ING_N
	jr nz,.h
	ret
.k:	call st_cold
.go:	ld (hl_kind),a
	add a,HP_HLP
	ld ix,hl_rec
	jp hw_go

; His carry and Blossom's change places.
hl_swap:
	ld hl,(blo_carry)
	ld de,(hl_carry)
	ld (blo_carry),de
	ld (hl_carry),hl
	ret

; His sprite, carrying with Blossom's carry frames (in the storage's area).
hl_sprites:
	ld a,(hl_rec+HW_STATE)
	or a
	ret z
	ld a,(area_cur)
	cp AREA_STORAGE
	ret nz
	ld ix,hl_rec
	ld a,(hl_carry)
	ld c,#FF
	jp staff_blo
	else
hl_tick:
hl_sprites:
	ret
HL_WAGE		equ 0
HL_HIRE		equ 0
	endif
