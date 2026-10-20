; Service: groups of customers (1-4) arrive at the entrance and wait in the
; queue; Bill takes them to a table: fire next to the queue and the group
; follows him (each member walks to where Bill was a while ago: the trail),
; fire at the spot of a free table that has seats enough (below it) and they
; walk to their chairs and sit down.
;
; The customers are a pool (cust_list, src/game/customer.asm): a group uses
; GR_N consecutive records from GR_FIRST. A customer walks to (CU_TX, CU_TY)
; (sprite left/top), CU_DX = 1 while walking (walk animation).
;
; Bubbles: in the queue "...", seated (wants to order) the notepad.

G_MAX		equ 4		; groups at the same time

GS_FREE		equ 0
GS_ARRIVE	equ 1		; walking from the door to the queue
GS_QUEUE	equ 2
GS_FOLLOW	equ 3		; behind Bill
GS_SEATING	equ 4		; walking to the chairs
GS_SEATED	equ 5		; waiting to order

; group record
GR_STATE	equ 0
GR_N		equ 1		; customers
GR_FIRST	equ 2		; first customer (index in the pool)
GR_TABLE	equ 3
GR_SIZE		equ 4

; entrance (level 1: the mats at metatiles 8-9 of the bottom row)
DOOR_X		equ 128		; customer sprite left/top
DOOR_Y		equ 623
QUEUE_X		equ 128		; first in the queue; the others to its left
QUEUE_Y		equ 583
QUEUE_DX	equ 14
SPAWN_TICKS	equ 300		; a new group at most every 6 s

TRAIL_N		equ 32		; Bill's feet, recorded every 4 ticks he walks
FOLLOW_GAP	equ 5		; trail entries between the followers
NEAR_X		equ 28		; fire reaches this far (feet to feet)
NEAR_Y		equ 24

groups:		ds G_MAX*GR_SIZE,0
tb_busy:	ds TABLE_COUNT,0	; group + 1 at the table, 0 = free
sv_prev:	db 0		; input of the last tick (fire edge)
sv_follow:	db 0		; group + 1 following Bill
sv_spawn_t:	dw 50
sv_tick:	db 0
sv_seed:	dw #ACE1
trail:		ds TRAIL_N*4,0	; x, y words
trail_head:	db 0

; ---------------------------------------------------------------------------
; One game tick (bank 5).
service_tick:
	ld hl,cust_anim
	inc (hl)
	ld a,(input)			; fire: pressed this tick
	ld b,a
	ld a,(sv_prev)
	cpl
	and b
	ld c,a
	ld a,b
	ld (sv_prev),a
	bit KEY_FIRE,c
	call nz,sv_fire
	ld hl,sv_tick
	inc (hl)
	ld a,(hl)
	and 3
	call z,sv_trail
	call sv_spawn
	ld ix,groups
	ld b,G_MAX
.g:	push bc
	call sv_group
	ld de,GR_SIZE
	add ix,de
	pop bc
	djnz .g
	ld a,(cust_anim)		; walking: a step every other tick
	rrca
	ret c
	jp sv_walk

; ---------------------------------------------------------------------------
; HL = customer A of the pool, IY too
sv_cust:
	ld l,a				; A*18 = A*16 + A*2
	ld h,0
	add hl,hl
	ld d,h
	ld e,l
	add hl,hl
	add hl,hl
	add hl,hl
	add hl,de
	ld de,cust_list
	add hl,de
	push hl
	pop iy
	ret

; IY = first customer of group IX, B = its customers
sv_members:
	ld a,(ix+GR_FIRST)
	call sv_cust
	ld b,(ix+GR_N)
	ret

; random byte in A (16-bit xorshift; the same sequence every game for now)
sv_rand:
	ld hl,(sv_seed)
	ld a,h
	rra
	ld a,l
	rra
	xor h
	ld h,a
	ld a,l
	rra
	ld a,h
	rra
	xor l
	ld l,a
	xor h
	ld h,a
	ld (sv_seed),hl
	ld a,l
	ret

; carry set if |HL - DE| < C
sv_near:
	or a
	sbc hl,de
	jp p,.p
	ex de,hl
	ld hl,0
	or a
	sbc hl,de
.p:	ld a,h
	or a
	ret nz				; (carry clear)
	ld a,l
	cp c
	ret

; ---------------------------------------------------------------------------
; Bill's trail: his feet every 4 ticks he walks.
sv_trail:
	ld a,(bill_moving)
	or a
	ret z
sv_trail_put:
	ld a,(trail_head)
	inc a
	and TRAIL_N-1
	ld (trail_head),a
	call sv_trail_at
	ld de,(bill_x)
	ld (hl),e
	inc hl
	ld (hl),d
	inc hl
	ld de,(bill_y)
	ld (hl),e
	inc hl
	ld (hl),d
	ret

; HL = trail entry A
sv_trail_at:
	add a,a
	add a,a
	ld l,a
	ld h,0
	ld de,trail
	add hl,de
	ret

; All the trail at Bill's feet (a group starts following).
sv_trail_fill:
	ld b,TRAIL_N
.l:	push bc
	call sv_trail_put
	pop bc
	djnz .l
	ret

; ---------------------------------------------------------------------------
; A new group now and then, while nobody waits at the entrance.
sv_spawn:
	ld hl,(sv_spawn_t)
	dec hl
	ld (sv_spawn_t),hl
	ld a,h
	or l
	ret nz
	ld hl,SPAWN_TICKS
	ld (sv_spawn_t),hl
	ld ix,groups			; queue busy or no free group: later
	ld b,G_MAX
	ld iy,0
.f:	ld a,(ix+GR_STATE)
	cp GS_ARRIVE
	ret z
	cp GS_QUEUE
	ret z
	or a
	jr nz,.n
	ld a,iyh
	or iyl
	jr nz,.n
	push ix
	pop iy
.n:	ld de,GR_SIZE
	add ix,de
	djnz .f
	ld a,iyh
	or iyl
	ret z
	push iy
	pop ix
	call sv_rand			; size 1-4
	and 3
	inc a
	ld (ix+GR_N),a
	; first fit: GR_N free customers in a row
	ld c,0				; candidate first
.try:	ld a,c
	add a,(ix+GR_N)
	cp CU_COUNT+1
	ret nc				; no room: later
	ld a,c
	call sv_cust
	ld b,(ix+GR_N)
	ld e,c
.chk:	ld a,(iy+CU_ON)
	or a
	jr nz,.busy
	push de
	ld de,CU_SIZE
	add iy,de
	pop de
	djnz .chk
	ld (ix+GR_FIRST),c
	ld (ix+GR_STATE),GS_ARRIVE
	call sv_members			; in at the door, to the queue
	ld hl,QUEUE_X
.m:	push bc
	push hl
	ld (iy+CU_ON),1
	ld (iy+CU_X),DOOR_X&255
	ld (iy+CU_X+1),DOOR_X>>8
	ld (iy+CU_Y),DOOR_Y&255
	ld (iy+CU_Y+1),DOOR_Y>>8
	ld (iy+CU_TX),l
	ld (iy+CU_TX+1),h
	ld (iy+CU_TY),QUEUE_Y&255
	ld (iy+CU_TY+1),QUEUE_Y>>8
	ld (iy+CU_DIR),DIR_UP
	xor a
	ld (iy+CU_SIT),a
	ld (iy+CU_MOOD),a
	ld (iy+CU_DX),a
	call .style
	ld (iy+CU_HEAD),a
	call .style
	ld (iy+CU_BODY),a
	call .style
	ld (iy+CU_LEGS),a
	pop hl
	ld de,-QUEUE_DX
	add hl,de
	ld de,CU_SIZE
	add iy,de
	pop bc
	djnz .m
	ret
.busy:	inc c
	jr .try
.style:	call sv_rand			; 0-2
	and 3
	cp 3
	jr z,.style
	ret

; ---------------------------------------------------------------------------
; State of group IX.
sv_group:
	ld a,(ix+GR_STATE)
	cp GS_ARRIVE
	jr z,.arrive
	cp GS_FOLLOW
	jr z,.follow
	cp GS_SEATING
	jr z,.seating
	ret
.arrive:
	call sv_arrived
	ret nz
	ld (ix+GR_STATE),GS_QUEUE
	call sv_members
.q:	ld (iy+CU_DIR),DIR_DOWN
	ld de,CU_SIZE
	add iy,de
	djnz .q
	ld a,MOOD_WAIT
	jp sv_mood
.follow:				; member k: trail entry head - gap*(k+1)
	call sv_members
	ld a,(trail_head)
	ld c,a
.fl:	ld a,c
	sub FOLLOW_GAP
	and TRAIL_N-1
	ld c,a
	push bc
	call sv_trail_at
	ld e,(hl)			; feet -> sprite left/top
	inc hl
	ld d,(hl)
	inc hl
	push hl
	ld hl,-16
	add hl,de
	ld (iy+CU_TX),l
	ld (iy+CU_TX+1),h
	pop hl
	ld e,(hl)
	inc hl
	ld d,(hl)
	ld hl,-47
	add hl,de
	ld (iy+CU_TY),l
	ld (iy+CU_TY+1),h
	ld de,CU_SIZE
	add iy,de
	pop bc
	djnz .fl
	ret
.seating:				; on the chair: sit down facing the table
	call sv_members
	ld c,0				; seats taken
.sl:	ld a,(iy+CU_SIT)
	or a
	jr nz,.sat
	call sv_at
	jr nz,.nx
	ld (iy+CU_SIT),1
	ld (iy+CU_DX),0
	push bc				; dir of seat k
	ld a,(ix+GR_N)
	sub b
	call sv_seat
	ld bc,4
	add hl,bc
	ld a,(hl)
	ld (iy+CU_DIR),a
	pop bc
.sat:	inc c
.nx:	ld de,CU_SIZE
	add iy,de
	djnz .sl
	ld a,c
	cp (ix+GR_N)
	ret nz
	ld (ix+GR_STATE),GS_SEATED
	ld a,MOOD_ORDER
	; fall through

; Mood A on the group's first customer (its bubble).
sv_mood:
	push af
	ld a,(ix+GR_FIRST)
	call sv_cust
	pop af
	ld (iy+CU_MOOD),a
	ret

; Z if customer IY is at its target
sv_at:
	ld a,(iy+CU_X)
	cp (iy+CU_TX)
	ret nz
	ld a,(iy+CU_X+1)
	cp (iy+CU_TX+1)
	ret nz
	ld a,(iy+CU_Y)
	cp (iy+CU_TY)
	ret nz
	ld a,(iy+CU_Y+1)
	cp (iy+CU_TY+1)
	ret

; Z if all of group IX are at their targets
sv_arrived:
	call sv_members
.l:	call sv_at
	ret nz
	ld de,CU_SIZE
	add iy,de
	djnz .l
	ret

; HL = seat A of the table of group IX (x, y, dir)
sv_seat:
	push af
	ld a,(ix+GR_TABLE)
	call sv_table
	ld de,TB_SEAT0
	add hl,de
	pop af
	ld e,a				; *SEAT_SIZE (5)
	add a,a
	add a,a
	add a,e
	ld e,a
	ld d,0
	add hl,de
	ret

; HL = table A
sv_table:
	ld l,a
	ld h,0
	ld d,h
	ld e,l
	add hl,hl			; *25 = *24 + 1
	add hl,de
	add hl,hl
	add hl,hl
	add hl,hl
	add hl,de
	ld de,lvl_tables
	add hl,de
	ret

; ---------------------------------------------------------------------------
; Fire: take the queue's group along, or seat the group that follows.
sv_fire:
	ld a,(sv_follow)
	or a
	jr nz,.seat
	ld ix,groups
	ld b,G_MAX
.g:	ld a,(ix+GR_STATE)
	cp GS_QUEUE
	jr nz,.n
	push bc
	call sv_bill_near
	pop bc
	jr c,.take
.n:	ld de,GR_SIZE
	add ix,de
	djnz .g
	ret
.take:	ld (ix+GR_STATE),GS_FOLLOW
	ld a,G_MAX			; group index + 1
	sub b
	inc a
	ld (sv_follow),a
	xor a
	call sv_mood
	jp sv_trail_fill
.seat:	dec a				; IX = the following group
	add a,a
	add a,a
	ld e,a
	ld d,0
	ld ix,groups
	add ix,de
	ld c,0				; tables
.t:	ld a,c
	cp TABLE_COUNT
	ret nc
	ld hl,tb_busy
	ld e,c
	ld d,0
	add hl,de
	ld a,(hl)
	or a
	jr nz,.tn
	ld a,c
	call sv_table
	ld a,(hl)			; seats enough?
	cp (ix+GR_N)
	jr c,.tn
	inc hl
	ld e,(hl)			; Bill on its spot?
	inc hl
	ld d,(hl)
	inc hl
	push hl
	push bc
	ld hl,(bill_x)
	ld c,NEAR_X/2
	call sv_near
	pop bc
	pop hl
	jr nc,.tn
	ld e,(hl)
	inc hl
	ld d,(hl)
	push bc
	ld hl,(bill_y)
	ld c,NEAR_Y/2
	call sv_near
	pop bc
	jr c,.sit
.tn:	inc c
	jr .t
.sit:	ld (ix+GR_TABLE),c		; the table is theirs
	ld hl,tb_busy
	ld e,c
	ld d,0
	add hl,de
	ld a,(sv_follow)
	ld (hl),a
	xor a
	ld (sv_follow),a
	ld (ix+GR_STATE),GS_SEATING
	call sv_members			; member k to seat k
	ld c,0
.m:	push bc
	ld a,c
	call sv_seat
	ld a,(hl)
	ld (iy+CU_TX),a
	inc hl
	ld a,(hl)
	ld (iy+CU_TX+1),a
	inc hl
	ld a,(hl)
	ld (iy+CU_TY),a
	inc hl
	ld a,(hl)
	ld (iy+CU_TY+1),a
	ld de,CU_SIZE
	add iy,de
	pop bc
	inc c
	djnz .m
	ret

; carry if Bill's feet are near the feet of the first customer of group IX
sv_bill_near:
	ld a,(ix+GR_FIRST)
	call sv_cust
	ld l,(iy+CU_X)
	ld h,(iy+CU_X+1)
	ld de,16
	add hl,de
	ex de,hl
	ld hl,(bill_x)
	ld c,NEAR_X
	call sv_near
	ret nc
	ld l,(iy+CU_Y)
	ld h,(iy+CU_Y+1)
	ld de,47
	add hl,de
	ex de,hl
	ld hl,(bill_y)
	ld c,NEAR_Y
	jp sv_near

; ---------------------------------------------------------------------------
; Every customer one step to its target: 1 pixel and 2 lines, facing the
; longer way (a pixel is two lines wide).
sv_walk:
	ld iy,cust_list
	ld b,CU_COUNT
.l:	push bc
	ld a,(iy+CU_ON)
	or a
	jp z,.next
	ld a,(iy+CU_SIT)
	or a
	jp nz,.next
	xor a
	ld (iy+CU_DX),a
	ld (sw_ax),a
	ld (sw_ay),a
	ld l,(iy+CU_TX)			; x
	ld h,(iy+CU_TX+1)
	ld e,(iy+CU_X)
	ld d,(iy+CU_X+1)
	or a
	sbc hl,de
	jr z,.y
	ld bc,1
	ld a,DIR_RIGHT
	jp p,.xs
	ld bc,-1
	ld a,DIR_LEFT
	push af				; |dx|
	ex de,hl
	ld hl,0
	or a
	sbc hl,de
	pop af
.xs:	ld (sw_dx),a
	ld (sw_ax),hl
	ld l,(iy+CU_X)
	ld h,(iy+CU_X+1)
	add hl,bc
	ld (iy+CU_X),l
	ld (iy+CU_X+1),h
	ld (iy+CU_DX),1
.y:	ld l,(iy+CU_TY)
	ld h,(iy+CU_TY+1)
	ld e,(iy+CU_Y)
	ld d,(iy+CU_Y+1)
	or a
	sbc hl,de
	jr z,.dir
	ld bc,2
	ld a,DIR_DOWN
	jp p,.ys
	ld bc,-2
	ld a,DIR_UP
	push af
	ex de,hl
	ld hl,0
	or a
	sbc hl,de
	pop af
.ys:	ld (sw_dy),a
	ld (sw_ay),hl
	ld a,h				; one line left: a single line
	or a
	jr nz,.yb
	ld a,l
	dec a
	jr nz,.yb
	sra b				; +-2 -> +-1
	rr c
.yb:	ld l,(iy+CU_Y)
	ld h,(iy+CU_Y+1)
	add hl,bc
	ld (iy+CU_Y),l
	ld (iy+CU_Y+1),h
	ld (iy+CU_DX),1
.dir:	ld a,(iy+CU_DX)			; facing: the longer way (2|dx| vs |dy|)
	or a
	jp z,.next
	ld hl,(sw_ax)
	add hl,hl
	ld de,(sw_ay)
	or a
	sbc hl,de
	ld a,(sw_dx)
	jr nc,.d
	ld a,(sw_dy)
.d:	ld (iy+CU_DIR),a
.next:	ld de,CU_SIZE
	add iy,de
	pop bc
	dec b
	jp nz,.l
	ret

sw_ax:	dw 0
sw_ay:	dw 0
sw_dx:	db 0
sw_dy:	db 0
