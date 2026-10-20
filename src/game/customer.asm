; Customers: figures made of three compiled parts, head (20 lines), body (14)
; and legs (14), in any combination of styles (tools/mkparts.py, sheets
; cust_head/cust_body/cust_legs). A customer is one sprite entry with the
; three parts (their dy counts from the figure's top line).
;
; Test placement for now: some customers stand, some walk to and fro.

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
CU_MOOD		equ 11		; MOOD_* (src/game/items.asm)
CU_SIZE		equ 12

	ifndef CUST_BENCH
CUST_BENCH	equ 0
	endif

	if CUST_BENCH			; frame rate test: 5 walkers in the first view
CU_COUNT	equ 5
cust_list:
	;  x,  y       head body legs dir        dx  min/2 max/2 mood
	dw 10,0 : db 0,1,2,DIR_RIGHT,   1, 5, 60, 0
	dw 120,30 : db 1,2,0,DIR_LEFT, -1, 5, 60, 0
	dw 40,70 : db 2,0,1,DIR_RIGHT,  1, 5, 60, 0
	dw 90,100 : db 1,1,1,DIR_LEFT, -1, 5, 60, 0
	dw 60,120 : db 2,2,2,DIR_RIGHT, 1, 5, 60, 0
	else
CU_COUNT	equ 4
cust_list:
	;  x,  y       head body legs dir        dx  min/2 max/2 mood
	dw 100,10 : db 0,1,2,DIR_DOWN,  0, 0, 0, MOOD_HAPPY
	dw 20,60 : db 1,2,0,DIR_RIGHT,  1, 10, 75, 0
	dw 30,104 : db 2,0,1,DIR_RIGHT, 0, 0, 0, MOOD_FOOD
	dw 140,112 : db 2,2,0,DIR_LEFT, -1, 50, 70, MOOD_WAIT
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
	ld (cust_y),hl
	ld de,48
	add hl,de
	ld (spr_z),hl
	ld a,(ix+CU_BODY)		; one sprite entry, three parts
	ld hl,cust_body_frames
	call .desc
	ld (spr_f2),hl
	ld a,(ix+CU_LEGS)
	ld hl,cust_legs_frames
	call .desc
	ld (spr_f3),hl
	ld a,(ix+CU_HEAD)
	ld hl,cust_head_frames
	call .desc
	ld a,(ix+CU_X)			; even x (whole bytes)
	and #FE
	ld e,a
	ld d,(ix+CU_X+1)
	ld bc,(cust_y)
	push de
	call sprites_add_z
	pop de
	ld bc,(cust_y)
	call bubble_sprite
	ld de,CU_SIZE
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
