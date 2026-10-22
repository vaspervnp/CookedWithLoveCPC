; Staff: Liberty / Eleftheria, the cook (area kitchen: sheets liberty,
; liberty_act) and Blossom / Anthi, the storage keeper (area storage:
; blossom, blossom_carry, blossom_act). Their sprites are in the area images
; of bank 7: each is drawn only while her area is loaded.
;
; For now each runs a looped test script. A step: kind, a, b, ticks
;   ST_ACT:   a = action, b = frame offset of the facing (0 right, else left)
;   ST_WALK:  a = DIR_*, b = pixels per 2 ticks (signed, horizontal)
;   ST_CARRY: as ST_WALK, carrying a box (frames: down, right, left; going
;             up the walk frames are used, the box is hidden)

ST_ACT		equ 0
ST_WALK		equ 1
ST_CARRY	equ 2

; staff record
SR_X		equ 0
SR_Y		equ 2
SR_STEP		equ 4		; current step
SR_T		equ 6		; ticks left in it
SR_ANIM		equ 7
SR_SCRIPT	equ 8
SR_WALK		equ 10		; frame tables
SR_CARRY	equ 12
SR_ACT		equ 14
SR_AREA		equ 16
SR_SIZE		equ 17

STAFF_N		equ 2

	if MAP_TEST
LIB_X0 equ 90 : LIB_Y0 equ 118 : LIB_WALK equ 60
BLO_X0 equ 400 : BLO_Y0 equ 430 : BLO_WALK equ 70
	else				; level 1: kitchen row 12, storage row 24
LIB_X0 equ 344 : LIB_Y0 equ 160 : LIB_WALK equ 96
BLO_X0 equ 520 : BLO_Y0 equ 352 : BLO_WALK equ 90
	endif

staff_list:
	dw LIB_X0,LIB_Y0, lib_script : db 64,0 : dw lib_script
	dw liberty_frames, 0, liberty_act_frames : db AREA_KITCHEN
	dw BLO_X0,BLO_Y0, blo_script : db 70,0 : dw blo_script
	dw blossom_frames, blossom_carry_frames, blossom_act_frames : db AREA_STORAGE

lib_script:
	db ST_ACT, 0, 6, 64		; chop (counter to her left)
	db ST_WALK, DIR_RIGHT, 1, LIB_WALK
	db ST_ACT, 1, 0, 64		; stir (stove to her right)
	db ST_WALK, DIR_LEFT, -1, LIB_WALK
	db ST_ACT, 2, 6, 48		; oven, facing left
	db #FF

blo_script:
	db ST_CARRY, DIR_RIGHT, 1, BLO_WALK	; box to the shelf
	db ST_ACT, 0, 0, 48		; onto the shelf (to her right)
	db ST_WALK, DIR_LEFT, -1, BLO_WALK
	db ST_WALK, DIR_DOWN, 0, 16	; (turns to the viewer)
	db #FF

lib_taken:	db 0		; Liberty is the player's (lib_rec) since a swap

blo_taken:	db 0

	if SERVICE
; Swap the player (the service, fire 2 / space): Bill -> Liberty -> (Hard:
; Blossom ->) Bill. The first time each leaves her script where she is.
staff_swap:
	xor a				; none walks on by himself
	ld (bill_moving),a
	ld (lib_rec+AC_MOV),a
	ld (blo_rec+AC_MOV),a
	ld a,(ctl_who)
	inc a
	cp 2
	jr c,.w
	jr nz,.b0			; (3: back to Bill)
	ld a,(sv_mode)			; Blossom in Hard only
	cp 2
	ld a,2
	jr z,.w
.b0:	xor a
.w:	ld (ctl_who),a
	ld hl,bill_x
	or a
	jr z,.set
	dec a
	jr nz,.blo
	ld hl,lib_taken
	ld ix,staff_list
	ld de,lib_rec
	call .take
	ld hl,lib_rec
	jr .set
.blo:	ld hl,blo_taken
	ld ix,staff_list+SR_SIZE
	ld de,blo_rec
	call .take
	ld hl,blo_rec
.set:	ld (ctl_rec),hl
	jp sv_hud_stock			; (row 3: Blossom's or the portions)
; flag HL, staff record IX -> actor record DE (sprite left/top -> feet)
.take:	ld a,(hl)
	or a
	ret nz
	inc (hl)
	push de
	pop iy
	ld l,(ix+SR_X)
	ld h,(ix+SR_X+1)
	ld de,16
	add hl,de
	ld (iy+AC_X),l
	ld (iy+AC_X+1),h
	ld l,(ix+SR_Y)
	ld h,(ix+SR_Y+1)
	ld de,47
	add hl,de
	ld (iy+AC_Y),l
	ld (iy+AC_Y+1),h
	ld (iy+AC_DIR),DIR_DOWN
	ret
	endif

; NZ if staff record IX is under the player (A: 1 Liberty, 2 Blossom).
staff_taken:
	push ix
	pop hl
	ld de,staff_list
	or a
	sbc hl,de
	ld a,(lib_taken)
	jr z,.l
	ld a,(blo_taken)
	or a
	ret z
	ld a,2
	ret
.l:	or a
	ret

; One game tick for every staff member.
staff_tick:
	ld ix,staff_list
	ld b,STAFF_N
.lp:	push bc
	call .one
	ld de,SR_SIZE
	add ix,de
	pop bc
	djnz .lp
	ret

.one:	call staff_taken		; under the player since a swap
	ret nz
	inc (ix+SR_ANIM)
	dec (ix+SR_T)
	jr nz,.run
	ld l,(ix+SR_STEP)		; next step
	ld h,(ix+SR_STEP+1)
	ld de,4
	add hl,de
	ld a,(hl)
	inc a
	jr nz,.st
	ld l,(ix+SR_SCRIPT)		; loop
	ld h,(ix+SR_SCRIPT+1)
.st:	ld (ix+SR_STEP),l
	ld (ix+SR_STEP+1),h
	inc hl
	inc hl
	inc hl
	ld a,(hl)
	ld (ix+SR_T),a
.run:	ld l,(ix+SR_STEP)
	ld h,(ix+SR_STEP+1)
	ld a,(hl)
	cp ST_ACT
	ret z
	ld a,(ix+SR_ANIM)		; walking: a step every other tick
	rrca
	ret c
	inc hl
	inc hl
	ld a,(hl)
	ld e,a
	rla
	sbc a,a
	ld d,a
	ld l,(ix+SR_X)
	ld h,(ix+SR_X+1)
	add hl,de
	ld (ix+SR_X),l
	ld (ix+SR_X+1),h
	ret

; Add the staff of the loaded area to the sprite list.
staff_sprites:
	ld ix,staff_list
	ld b,STAFF_N
.lp:	push bc
	ld a,(area_cur)
	cp (ix+SR_AREA)
	call z,.one
	ld de,SR_SIZE
	add ix,de
	pop bc
	djnz .lp
	ret

.one:	call staff_taken		; taken over: from her actor record
	jr z,.scr
	push ix
	ld ix,lib_rec
	ld hl,liberty_frames
	cp 1
	jr z,.lf
	ld ix,blo_rec			; Blossom: carrying (but going up):
	ld hl,blossom_frames		; her carry frames (down, right, left)
	if SERVICE
	ld a,(blo_carry)
	or a
	jr z,.lf
	ld a,(ix+AC_DIR)
	cp DIR_UP
	jr z,.lf
	push af
	or a
	jr z,.bd
	dec a
.bd:	ld (ix+AC_DIR),a
	ld hl,blossom_carry_frames
	call ac_frame
	pop af
	ld (ix+AC_DIR),a
	jr .add2
	endif
.lf:	call ac_frame
.add2:	push de
	push bc
	call sprites_add
	pop bc
	pop de
	pop ix
	if SERVICE
	push ix				; (Blossom: no plate)
	pop hl
	ld a,l
	cp staff_list&255
	ret nz
	ld a,(lib_carry)		; a plate (src/game/kitchen.asm)
	or a
	ret z
	ld a,MOOD_FOOD
	push ix
	call bubble_a
	pop ix
	endif
	ret
.scr:	ld l,(ix+SR_STEP)
	ld h,(ix+SR_STEP+1)
	ld a,(hl)			; kind
	inc hl
	ld c,(hl)			; a
	inc hl
	ld b,(hl)			; b
	cp ST_ACT
	jr nz,.walk
	ld a,c				; action: frame = facing + action*2 + phase
	add a,a
	add a,b
	ld c,a
	ld a,(ix+SR_ANIM)		; 2 phases, 8 ticks each
	rrca
	rrca
	rrca
	and 1
	add a,c
	ld l,(ix+SR_ACT)
	ld h,(ix+SR_ACT+1)
	jr .add
.walk:	cp ST_CARRY			; carrying, but not going up: carry frames
	jr nz,.w
	ld a,c
	cp DIR_UP
	jr z,.w
	or a				; carry rows: down 0, right 3, left 6
	jr z,.cd
	dec a
.cd:	ld c,a
	add a,a
	add a,c
	ld c,a
	call .pose
	add a,c
	ld l,(ix+SR_CARRY)
	ld h,(ix+SR_CARRY+1)
	jr .add
.w:	ld a,c				; walk: frame = dir*3 + walk_pose[step]
	add a,a
	add a,c
	ld c,a
	call .pose
	add a,c
	ld l,(ix+SR_WALK)
	ld h,(ix+SR_WALK+1)
.add:	add a,a
	ld e,a
	ld d,0
	add hl,de
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	ld a,(ix+SR_X)			; even x (whole bytes)
	and #FE
	ld e,a
	ld d,(ix+SR_X+1)
	ld c,(ix+SR_Y)
	ld b,(ix+SR_Y+1)
	push ix
	call sprites_add
	pop ix
	ret

; A = walk pose of the step (standing still while b = 0)
.pose:	ld l,(ix+SR_STEP)
	ld h,(ix+SR_STEP+1)
	inc hl
	inc hl
	ld a,(hl)
	or a
	ret z
	ld a,(ix+SR_ANIM)
	rrca
	rrca
	rrca
	and 3
	jp walk_frame
