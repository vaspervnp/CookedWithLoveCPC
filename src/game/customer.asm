; Customers: figures made of three compiled parts, head (20 lines), body (14)
; and legs (14), in any combination of styles (tools/mkparts.py, sheets
; cust_head/cust_body/cust_legs). A customer is one sprite entry with the
; three parts (their dy counts from the figure's top line).
;
; Sitting, the figure is drawn SIT_DROP lines lower; in profile it has the
; sitting legs (sheet cust_sit), facing down or up none (the table or the
; body hides them; the chair is part of the background).
;
; Test placement for now: some customers stand, some walk to and fro, some sit.

CU_PART_FRAMES	equ 12		; per style: (down, up, right, left) x (idle, walk 1, walk 2)

; customer record
CU_X		equ 0		; left edge, map pixels (even)
CU_Y		equ 2		; top line
CU_HEAD		equ 4		; styles
CU_BODY		equ 5
CU_LEGS		equ 6
CU_DIR		equ 7		; DIR_*
CU_DX		equ 8		; walking: pixels per tick (signed, 0 = standing)
CU_MIN		equ 9		; walking range (x / 2)
CU_MAX		equ 10
CU_ROUTE	equ 9		; service (no walking range): route kind << 4 + step
CU_RTAB		equ 10		; its table * 4 + seat
CU_MOOD		equ 11		; MOOD_* (src/game/items.asm)
CU_SIT		equ 12		; 1: sitting (on a chair of the background)
CU_ON		equ 13		; 0: not in the restaurant (not drawn)
CU_TX		equ 14		; service: where it walks to (src/game/service.asm)
CU_TY		equ 16
CU_STILL	equ 18		; 1: standing still (queue): drawn as a stamp
CU_TALK		equ 19		; sitting: ticks of talking left (service.asm)
CU_SIZE		equ 20

SIT_DROP	equ 4		; sitting: the figure is drawn this much lower

; (CUST_BENCH, SERVICE: src/main.asm)

	if CUST_BENCH			; frame rate test: 5 walkers in the first view
CU_COUNT	equ 5
cust_list:
	;  x,  y       head body legs dir        dx  min/2 max/2 mood sit on, target
	dw 10,0 : db 0,1,2,DIR_RIGHT,   1, 5, 60, 0, 0, 1 : dw 0,0 : db 0,0
	dw 120,30 : db 1,2,0,DIR_LEFT, -1, 5, 60, 0, 0, 1 : dw 0,0 : db 0,0
	dw 40,70 : db 2,0,1,DIR_RIGHT,  1, 5, 60, 0, 0, 1 : dw 0,0 : db 0,0
	dw 90,100 : db 1,1,1,DIR_LEFT, -1, 5, 60, 0, 0, 1 : dw 0,0 : db 0,0
	dw 60,120 : db 2,2,2,DIR_RIGHT, 1, 5, 60, 0, 0, 1 : dw 0,0 : db 0,0
	elseif SERVICE			; the game: a pool (src/game/service.asm)
CU_COUNT	equ 24		; a full dining room
cust_list:
	ds CU_COUNT*CU_SIZE,0
	elseif MAP_TEST==0		; level 1: at the tables of the dining room
CU_COUNT	equ 4
cust_list:
	;  x,  y       head body legs dir        dx  min/2 max/2 mood sit on, target
	; seats of the level's tables (build/lvl1_objs.asm)
	dw TB0_S0_X,TB0_S0_Y : db 0,1,2,TB0_S0_DIR, 0, 0, 0, MOOD_HAPPY, 1, 1 : dw 0,0 : db 0,0
	dw TB0_S1_X,TB0_S1_Y : db 1,2,1,TB0_S1_DIR, 0, 0, 0, MOOD_WAIT, 1, 1 : dw 0,0 : db 0,0
	dw TB5_S0_X,TB5_S0_Y : db 2,0,1,TB5_S0_DIR, 0, 0, 0, MOOD_FOOD, 1, 1 : dw 0,0 : db 0,0
	dw 40,352 : db 2,2,0,DIR_RIGHT, 1, 20, 130, 0, 0, 1 : dw 0,0 : db 0,0	; walking the aisle (row 24)
	else
CU_COUNT	equ 4
cust_list:
	;  x,  y       head body legs dir        dx  min/2 max/2 mood sit on, target
	dw 100,10 : db 0,1,2,DIR_DOWN,  0, 0, 0, MOOD_HAPPY, 1, 1 : dw 0,0 : db 0,0
	dw 20,60 : db 1,2,0,DIR_RIGHT,  1, 10, 75, 0, 0, 1 : dw 0,0 : db 0,0
	dw 30,104 : db 2,0,1,DIR_RIGHT, 0, 0, 0, MOOD_FOOD, 1, 1 : dw 0,0 : db 0,0
	dw 140,112 : db 2,2,0,DIR_LEFT, -1, 50, 70, MOOD_WAIT, 0, 1 : dw 0,0 : db 0,0
	endif

cust_anim:	db 0

; One game tick: walkers move and turn at the ends of their range.
cust_tick:
	ld hl,cust_anim
	inc (hl)
	bit 0,(hl)			; walkers move every other tick
	ret nz
	ld ix,cust_list
	ld b,CU_COUNT
.lp:	ld a,(ix+CU_DX)
	or a
	jr z,.next
	ld e,a				; x += dx
	rla
	sbc a,a
	ld d,a
	ld l,(ix+CU_X)
	ld h,(ix+CU_X+1)
	add hl,de
	ld (ix+CU_X),l
	ld (ix+CU_X+1),h
	srl h				; x / 2 against the range
	rr l
	ld a,l
	cp (ix+CU_MIN)
	jr c,.right
	cp (ix+CU_MAX)
	jr c,.next
	ld (ix+CU_DX),-1
	ld (ix+CU_DIR),DIR_LEFT
	jr .next
.right:	ld (ix+CU_DX),1
	ld (ix+CU_DIR),DIR_RIGHT
.next:	ld de,CU_SIZE
	add ix,de
	djnz .lp
	ret

; Add the customers' parts to the sprite list.
cust_sprites:
	ld ix,cust_list
	ld b,CU_COUNT
.lp:	push bc
	ld a,(ix+CU_ON)
	or a
	jp z,.skip
	call cust_visible		; outside the view: not in the sprite list
	jp nc,.skip
	ld a,(ix+CU_DIR)		; frame = dir*3 + pose
	ld c,a
	add a,a
	add a,c
	ld c,a
	ld a,(ix+CU_DX)
	or a
	jr z,.pose
	ld a,(cust_anim)		; walking: 4-step cycle, 8 ticks a step
	rrca
	rrca
	rrca
	and 3
	push hl
	call walk_frame
	pop hl
	add a,c
	ld c,a
.pose:	ld a,c
	ld (cust_f),a
	ld l,(ix+CU_Y)			; depth: bottom line of the figure
	ld h,(ix+CU_Y+1)
	ld a,(ix+CU_SIT)
	or a
	jr z,.y
	ld de,SIT_DROP
	add hl,de
.y:	ld (cust_y),hl
	ld de,48
	add hl,de
	ld (spr_z),hl
	ld a,(ix+CU_BODY)		; one sprite entry, three parts
	ld hl,cust_body_frames
	call .desc
	ld (spr_f2),hl
	ld a,(ix+CU_SIT)
	or a
	jr nz,.sit
	ld a,(ix+CU_LEGS)
	ld hl,cust_legs_frames
	call .desc
	ld (spr_f3),hl
	jr .head
.sit:	ld a,(ix+CU_DIR)		; sitting: legs only in profile
	sub DIR_RIGHT
	jr c,.head
	ld e,a				; frame = style*2 + (left)
	ld a,(ix+CU_LEGS)
	add a,a
	add a,e
	add a,a
	ld e,a
	ld d,0
	ld hl,cust_sit_frames
	add hl,de
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	ld (spr_f3),hl
.head:
	ld a,(ix+CU_HEAD)
	ld hl,cust_head_frames
	call .desc
	ld a,(ix+CU_X)			; even x (whole bytes)
	and #FE
	ld e,a
	ld d,(ix+CU_X+1)
	ld bc,(cust_y)
	ld a,(ix+CU_SIT)		; sitting or standing still: a stamp
	or (ix+CU_STILL)		; (sprite.asm)
	ld (spr_stamp),a
	push de
	call sprites_add_z
	pop de
	ld bc,(cust_y)
	call bubble_sprite
	ld a,(ix+CU_TALK)		; talking: the open mouth now and then
	or a
	jr z,.skip
	ld a,(cust_anim)
	and 8
	jr z,.skip
	ld hl,mouth_frames		; right, left (mirror)
	ld a,(ix+CU_DIR)
	cp DIR_LEFT
	jr nz,.mr
	inc hl
	inc hl
.mr:	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	push hl
	ld hl,#7FFE			; over its stamp
	ld (spr_z),hl
	pop hl
	ld a,(ix+CU_X)
	and #FE
	ld e,a
	ld d,(ix+CU_X+1)
	ld bc,(cust_y)
	call sprites_add_z
.skip:	ld de,CU_SIZE
	add ix,de
	pop bc
	dec b
	jp nz,.lp
	ret

; A = style, HL = frame table -> HL = descriptor of table[style*12 + frame]
.desc:	ld e,a
	ld d,0
	ex de,hl
	add hl,hl
	add hl,hl
	ld b,h
	ld c,l
	add hl,hl
	add hl,bc			; style*12
	ld a,(cust_f)
	ld c,a
	ld b,0
	add hl,bc
	add hl,hl
	add hl,de
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	ret

cust_f:		db 0
cust_y:		dw 0

; Carry if customer IX (with its bubble above) may be in the view:
; x - 2*sx in -32..159, y - sy in -66..167.
cust_visible:
	ld a,(scr_sx)
	ld l,a
	ld h,0
	add hl,hl
	ex de,hl
	ld l,(ix+CU_X)
	ld h,(ix+CU_X+1)
	or a
	sbc hl,de
	ld de,32
	add hl,de			; 0..191
	ld a,h
	or a
	ret nz
	ld a,l
	cp 192
	ret nc
	ld l,(ix+CU_Y)
	ld h,(ix+CU_Y+1)
	ld de,(scr_sy)
	or a
	sbc hl,de
	ld de,66
	add hl,de			; 0..233
	ld a,h
	or a
	ret nz
	ld a,l
	cp 234
	ret
