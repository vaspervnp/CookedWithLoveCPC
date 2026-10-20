; Staff: Liberty / Eleftheria, the cook (sheets liberty, liberty_act; area
; kitchen) and Blossom / Anthi, the storage keeper (sheet blossom; area
; storage).
;
; For now she runs a looped script in the test level: chop, step right,
; stir, step back, oven (facing left), ... Each step: kind, a, b, ticks
;   ST_ACT:  a = action (0 chop, 1 stir, 2 oven), b = 0 right / 6 left
;   ST_WALK: a = DIR_*, b = pixels per 2 ticks (signed)

ST_ACT		equ 0
ST_WALK		equ 1

lib_script:
	db ST_ACT, 0, 0, 64
	db ST_WALK, DIR_RIGHT, 1, 60
	db ST_ACT, 1, 0, 64
	db ST_WALK, DIR_LEFT, -1, 60
	db ST_ACT, 2, 6, 48
	db #FF

lib_x:		dw 90
lib_y:		dw 118
lib_step:	dw lib_script
lib_t:		db 64
lib_anim:	db 0

; One game tick.
staff_tick:
	call blossom_tick
	ld hl,lib_anim
	inc (hl)
	ld hl,lib_t
	dec (hl)
	jr nz,.run
	ld hl,(lib_step)		; next step
	ld de,4
	add hl,de
	ld a,(hl)
	inc a
	jr nz,.st
	ld hl,lib_script		; loop
.st:	ld (lib_step),hl
	inc hl
	inc hl
	inc hl
	ld a,(hl)
	ld (lib_t),a
.run:	ld ix,(lib_step)
	ld a,(ix+0)
	cp ST_WALK
	ret nz
	ld a,(lib_anim)			; walking: move every other tick
	rrca
	ret c
	ld a,(ix+2)
	ld e,a
	rla
	sbc a,a
	ld d,a
	ld hl,(lib_x)
	add hl,de
	ld (lib_x),hl
	ret

; Add the staff of the loaded area to the sprite list (their sprites are in
; the area image of bank 7).
staff_sprites:
	ld a,(area_cur)
	cp AREA_KITCHEN
	jp nz,blossom_sprite
	ld ix,(lib_step)
	ld a,(ix+0)
	cp ST_WALK
	jr z,.walk
	ld a,(ix+1)			; action: frame = facing + action*2 + phase
	add a,a
	add a,(ix+2)
	ld b,a
	ld a,(lib_anim)			; 2 phases, 8 ticks each
	rrca
	rrca
	rrca
	and 1
	add a,b
	ld hl,liberty_act_frames
	jr .add
.walk:	ld a,(ix+1)			; walk: frame = dir*3 + walk_pose[step]
	ld b,a
	add a,a
	add a,b
	ld b,a
	ld a,(lib_anim)
	rrca
	rrca
	rrca
	and 3
	call walk_frame
	add a,b
	ld hl,liberty_frames
.add:	add a,a
	ld e,a
	ld d,0
	add hl,de
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	ld a,(lib_x)			; even x (whole bytes)
	and #FE
	ld e,a
	ld a,(lib_x+1)
	ld d,a
	ld bc,(lib_y)
	jp sprites_add

; Blossom (for now): walks to and fro at the right of the map.
BLO_MIN		equ 400
BLO_MAX		equ 470

blo_x:		dw BLO_MIN
blo_y:		dw 430
blo_dx:		db 1
blo_anim:	db 0

blossom_tick:
	ld hl,blo_anim
	inc (hl)
	bit 0,(hl)			; a pixel every other tick
	ret nz
	ld a,(blo_dx)
	ld e,a
	rla
	sbc a,a
	ld d,a
	ld hl,(blo_x)
	add hl,de
	ld (blo_x),hl
	ld de,BLO_MIN
	or a
	sbc hl,de
	jr z,.r
	ld hl,(blo_x)
	ld de,BLO_MAX
	or a
	sbc hl,de
	ret nz
	ld a,-1
	ld (blo_dx),a
	ret
.r:	ld a,1
	ld (blo_dx),a
	ret

blossom_sprite:
	cp AREA_STORAGE
	ret nz
	ld a,(blo_dx)			; frame = dir*3 + walk_pose[step]
	or a
	ld b,DIR_RIGHT*3
	jp p,.d
	ld b,DIR_LEFT*3
.d:	ld a,(blo_anim)
	rrca
	rrca
	rrca
	and 3
	call walk_frame
	add a,b
	add a,a
	ld e,a
	ld d,0
	ld hl,blossom_frames
	add hl,de
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	ld a,(blo_x)
	and #FE
	ld e,a
	ld a,(blo_x+1)
	ld d,a
	ld bc,(blo_y)
	jp sprites_add
