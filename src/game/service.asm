; Service: groups of customers (1-4) arrive at the entrance and wait in the
; queue; Bill takes them to a table: fire next to the queue and the group
; follows him (each member walks to where Bill was a while ago: the trail),
; fire at the spot of a free table that has seats enough (below it) and they
; walk to their chairs and sit down. Then, fire at the table's spot: take
; the order; the kitchen (automatic for now) cooks it and puts it on the
; pass; fire at the pass: the plates on Bill's tray; fire at the table:
; served, they eat; then fire at the table: they pay and leave.
;
; The day: from 12:00 (a game minute a second); at DAY_END no more
; customers come; when the last group has left, the HUD's second row shows
; the day's stars (served against lost customers) and earnings, and fire
; starts the next day.
;
; Patience: GR_P (255 at the start) goes down while they wait for Bill (in
; the queue, to order, for the food, to pay): a point every PAT_RATE ticks,
; about a minute from full to nothing; every service step refills
; PAT_REFILL. Below PAT_ANGRY the bubble is the angry one; at 0 they leave
; without paying. The tip is GR_P / 32 (0-7).
;
; The customers are a pool (cust_list, src/game/customer.asm): a group uses
; GR_N consecutive records from GR_FIRST. A customer walks to (CU_TX, CU_TY)
; (sprite left/top), CU_DX = 1 while walking (walk animation).
;
; Bubbles: in the queue "...", seated (wants to order) the notepad, waiting
; for the food a plate, eating a heart, wants to pay a coin; a plate over
; the pass when an order is ready.

G_MAX		equ 4		; groups at the same time

GS_FREE		equ 0
GS_ARRIVE	equ 1		; walking from the door to the queue
GS_QUEUE	equ 2
GS_FOLLOW	equ 3		; behind Bill
GS_SEATING	equ 4		; walking to the chairs
GS_SEATED	equ 5		; waiting to order
GS_ORDERED	equ 6		; in the kitchen (GR_T)
GS_READY	equ 7		; on the pass
GS_CARRIED	equ 8		; on Bill's tray
GS_EATING	equ 9		; (GR_T)
GS_PAY		equ 10		; wants to pay
GS_LEAVING	equ 11		; walking to the door

; group record
GR_STATE	equ 0
GR_N		equ 1		; customers
GR_FIRST	equ 2		; first customer (index in the pool)
GR_TABLE	equ 3
GR_T		equ 4		; timer (ticks)
GR_P		equ 6		; patience
GR_PT		equ 7		; ticks to the next point lost
GR_MOOD		equ 8		; bubble of the state (angry: shown instead)
GR_SIZE		equ 16

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
KITCHEN_T	equ 500		; cooking: 10 s
EAT_T		equ 600		; eating: 12 s
PRICE		equ 12		; per customer
BUBBLE_T	equ 50		; Bill's notepad bubble after taking an order
PAT_RATE	equ 12
PAT_REFILL	equ 96
PAT_ANGRY	equ 64

groups:		ds G_MAX*GR_SIZE,0
tb_busy:	ds TABLE_COUNT,0	; group + 1 at the table, 0 = free
sv_prev:	db 0		; input of the last tick (fire edge)
sv_follow:	db 0		; group + 1 following Bill
sv_spawn_t:	dw 50
sv_tick:	db 0
sv_seed:	dw #ACE1
trail:		ds TRAIL_N*4,0	; x, y words
trail_head:	db 0
bill_carry:	db 0		; group + 1 whose plates Bill carries
sv_bub_t:	db 0
sv_money:	dw 0
sv_served:	dw 0		; customers who paid today
sv_lost:	dw 0		; customers who left angry today
sv_day:		db 1
sv_phase:	db 0		; 0 open, 1 closed (no more arrivals), 2 over
sv_money0:	dw 0		; money when the day started
	ifndef DAY_MIN			; length of the day (game minutes; tests: shorter)
DAY_MIN		equ 180
	endif
DAY_END		equ 12*60+DAY_MIN
sv_min:		dw 12*60	; time of day (minutes)
sv_sec:		db 0		; ticks of the current game minute

; HUD (row 1): coin + money, clock + time, person + customers served
HUD_ROW		equ 1
HUD_MONEY	equ 4
HUD_TIME	equ 16
HUD_SERVED	equ 29
HUD_LOST	equ 37
HUD_ROW2	equ 2		; day, at the end of the day stars and earnings
HUD_DAY		equ 4
HUD_STARS	equ 15
HUD_EARN	equ 29
MINUTE_TICKS	equ 50		; a game minute every second

; ---------------------------------------------------------------------------
; Start of the day: the HUD.
service_init:
	ld a,8				; icons
	ld b,HUD_BG
	call hud_colors
	ld a,G_COIN_L
	ld bc,(1<<8)+HUD_ROW
	call hud_char
	ld a,G_COIN_R
	ld bc,(2<<8)+HUD_ROW
	call hud_char
	ld a,13
	ld b,HUD_BG
	call hud_colors
	ld a,G_CLOCK_L
	ld bc,((HUD_TIME-3)<<8)+HUD_ROW
	call hud_char
	ld a,G_CLOCK_R
	ld bc,((HUD_TIME-2)<<8)+HUD_ROW
	call hud_char
	ld a,G_PERSON_L
	ld bc,((HUD_SERVED-3)<<8)+HUD_ROW
	call hud_char
	ld a,G_PERSON_R
	ld bc,((HUD_SERVED-2)<<8)+HUD_ROW
	call hud_char
	ld a,4				; angry: red
	ld b,HUD_BG
	call hud_colors
	ld a,G_ANGRY_L
	ld bc,((HUD_LOST-3)<<8)+HUD_ROW
	call hud_char
	ld a,G_ANGRY_R
	ld bc,((HUD_LOST-2)<<8)+HUD_ROW
	call hud_char
	ld a,5				; day: orange
	ld b,HUD_BG
	call hud_colors
	ld a,G_SUN_L
	ld bc,(1<<8)+HUD_ROW2
	call hud_char
	ld a,G_SUN_R
	ld bc,(2<<8)+HUD_ROW2
	call hud_char
	call sv_hud_money
sv_hud_day:				; the counters of the day
	ld a,5
	ld b,HUD_BG
	call hud_colors
	ld a,(sv_day)
	ld l,a
	ld h,0
	ld d,2
	ld bc,(HUD_DAY<<8)+HUD_ROW2
	call hud_number
	call sv_hud_served
	call sv_hud_lost
	; fall through

; HH:MM
sv_hud_time:
	ld a,13
	ld b,HUD_BG
	call hud_colors
	ld hl,(sv_min)
	ld bc,60
	ld e,-1
.h:	inc e
	or a
	sbc hl,bc
	jr nc,.h
	add hl,bc
	push hl
	ld l,e
	ld h,0
	ld d,2
	ld bc,(HUD_TIME<<8)+HUD_ROW
	call hud_number
	ld a,G_COLON
	ld bc,((HUD_TIME+2)<<8)+HUD_ROW
	call hud_char
	pop hl
	ld d,2
	ld bc,((HUD_TIME+3)<<8)+HUD_ROW
	jp hud_number0

sv_hud_money:
	ld a,8
	ld b,HUD_BG
	call hud_colors
	ld hl,(sv_money)
	ld d,5
	ld bc,(HUD_MONEY<<8)+HUD_ROW
	jp hud_number

sv_hud_served:
	ld a,13
	ld b,HUD_BG
	call hud_colors
	ld hl,(sv_served)
	ld d,3
	ld bc,(HUD_SERVED<<8)+HUD_ROW
	jp hud_number

sv_hud_lost:
	ld a,4
	ld b,HUD_BG
	call hud_colors
	ld hl,(sv_lost)
	ld d,3
	ld bc,(HUD_LOST<<8)+HUD_ROW
	jp hud_number

; The end of the day: stars and earnings. 3 stars: nobody lost; 2: served
; at least 3 times the lost; 1: at least as many; else none.
sv_summary:
	ld hl,(sv_lost)
	ld de,(sv_served)
	ld c,0
	ld a,d				; nobody came: no stars
	or e
	jr z,.st
	ld a,h
	or l
	ld c,3
	jr z,.st
	ld c,0
	ex de,hl			; HL = served, DE = lost
	or a
	sbc hl,de
	jr c,.st			; fewer served than lost
	inc c
	or a
	sbc hl,de
	jr c,.st
	or a
	sbc hl,de
	jr c,.st			; served < 3 lost
	inc c
.st:	ld a,c
	ld (sm_stars),a
	ld a,8
	ld b,HUD_BG
	call hud_colors
	ld b,HUD_STARS			; three stars, the first C full
	ld c,0
.sl:	push bc
	ld a,(sm_stars)
	cp c
	ld a,G_STAR0_L
	jr z,.e
	jr c,.e
	ld a,G_STAR_L
.e:	push af
	ld c,HUD_ROW2
	call hud_char
	pop af
	pop bc
	push bc
	inc a
	inc b
	ld c,HUD_ROW2
	call hud_char
	pop bc
	inc b
	inc b
	inc b
	inc c
	ld a,c
	cp 3
	jr nz,.sl
	ld a,G_COIN_L			; earnings
	ld bc,((HUD_EARN-3)<<8)+HUD_ROW2
	call hud_char
	ld a,G_COIN_R
	ld bc,((HUD_EARN-2)<<8)+HUD_ROW2
	call hud_char
	ld hl,(sv_money)
	ld de,(sv_money0)
	or a
	sbc hl,de
	ld d,5
	ld bc,(HUD_EARN<<8)+HUD_ROW2
	jp hud_number

; Fire after the end of the day: the next one.
sv_new_day:
	ld hl,sv_day
	inc (hl)
	ld hl,12*60
	ld (sv_min),hl
	ld hl,0
	ld (sv_served),hl
	ld (sv_lost),hl
	ld hl,(sv_money)
	ld (sv_money0),hl
	ld hl,50
	ld (sv_spawn_t),hl
	xor a
	ld (sv_phase),a
	ld a,HUD_BG			; clear the stars and earnings
	ld b,a
	call hud_colors
	ld b,HUD_STARS
.c:	push bc
	ld a,G_SPACE
	ld c,HUD_ROW2
	call hud_char
	pop bc
	inc b
	ld a,b
	cp HUD_EARN+5
	jr nz,.c
	call sv_hud_day
	jp sv_hud_time

sm_stars:	db 0

; ---------------------------------------------------------------------------
; One game tick (bank 5).
service_tick:
	ld a,(sv_phase)			; the clock (stops when the day is over)
	cp 2
	jr z,.ck
	ld hl,sv_sec
	inc (hl)
	ld a,(hl)
	cp MINUTE_TICKS
	jr c,.ck
	ld (hl),0
	ld hl,(sv_min)
	inc hl
	ld (sv_min),hl
	ld de,DAY_END			; closing time: no more arrivals
	or a
	sbc hl,de
	jr nz,.tm
	ld a,1
	ld (sv_phase),a
.tm:	call sv_hud_time
.ck:
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
	ld hl,sv_bub_t			; Bill's bubble goes after a while
	ld a,(hl)
	or a
	jr z,.nb
	dec (hl)
	jr nz,.nb
	xor a
	ld (bill_bubble),a
.nb:	ld ix,groups
	ld b,G_MAX
.g:	push bc
	call sv_group
	ld de,GR_SIZE
	add ix,de
	pop bc
	djnz .g
	ld a,(sv_phase)			; closed and everybody gone: the day is over
	dec a
	jr nz,.nw
	ld ix,groups
	ld b,G_MAX
.f:	ld a,(ix+GR_STATE)
	or a
	jr nz,.nw
	ld de,GR_SIZE
	add ix,de
	djnz .f
	ld a,2
	ld (sv_phase),a
	call sv_summary
.nw:	ld a,(cust_anim)		; walking: a step every other tick
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
	ld a,(sv_phase)			; open only
	or a
	ret nz
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
	ld (ix+GR_P),255		; full patience
	ld (ix+GR_PT),PAT_RATE
	ld (ix+GR_MOOD),0
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
	jp .try
.style:	call sv_rand			; 0-2
	and 3
	cp 3
	jr z,.style
	ret

; ---------------------------------------------------------------------------
; State of group IX.
sv_group:
	ld a,(ix+GR_STATE)		; waiting for Bill: patience goes
	cp GS_QUEUE
	jr z,.wait
	cp GS_SEATED
	jr c,.state
	cp GS_EATING
	jr z,.state
	cp GS_LEAVING
	jr nc,.state
.wait:	dec (ix+GR_PT)
	jr nz,.state
	ld (ix+GR_PT),PAT_RATE
	dec (ix+GR_P)
	jp z,sv_angry
	ld a,(ix+GR_P)
	cp PAT_ANGRY-1
	call z,sv_show_mood
.state:	ld a,(ix+GR_STATE)
	cp GS_ARRIVE
	jr z,.arrive
	cp GS_FOLLOW
	jr z,.follow
	cp GS_SEATING
	jp z,.seating
	cp GS_ORDERED
	jr z,.cook
	cp GS_EATING
	jr z,.eat
	cp GS_LEAVING
	ret nz
	call sv_arrived			; at the door: gone
	ret nz
	call sv_members
.off:	ld (iy+CU_ON),0
	ld de,CU_SIZE
	add iy,de
	djnz .off
	ld (ix+GR_STATE),GS_FREE
	ret
.cook:	call sv_dect
	ret nz
	ld (ix+GR_STATE),GS_READY
	ret
.eat:	call sv_dect
	ret nz
	ld (ix+GR_STATE),GS_PAY
	ld a,MOOD_PAY
	jp sv_mood
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
	ld (ix+GR_MOOD),a
	; fall through

; More patience (a service step), the bubble again.
sv_refill:
	ld a,(ix+GR_P)
	add a,PAT_REFILL
	jr nc,.n
	ld a,255
.n:	ld (ix+GR_P),a
	jr sv_show_mood

; Mood A of the group's state.
sv_mood:
	ld (ix+GR_MOOD),a
	; fall through

; Its bubble on the group's first customer: the state's, or angry when
; patience is low (while it has a bubble).
sv_show_mood:
	ld a,(ix+GR_FIRST)
	call sv_cust
	ld a,(ix+GR_MOOD)
	or a
	jr z,.set
	ld a,(ix+GR_P)
	cp PAT_ANGRY
	ld a,MOOD_ANGRY
	jr c,.set
	ld a,(ix+GR_MOOD)
.set:	ld (iy+CU_MOOD),a
	ret

; Out of patience: they leave without paying.
sv_angry:
	ld e,(ix+GR_N)
	ld d,0
	ld hl,(sv_lost)
	add hl,de
	ld (sv_lost),hl
	push ix
	call sv_hud_lost
	pop ix
	ld a,MOOD_ANGRY
	; fall through

; The group leaves (mood A on the way): the table is free again, the
; plates on Bill's tray for them are wasted, all walk to the door.
sv_leave:
	call sv_mood
	ld a,(ix+GR_STATE)
	cp GS_SEATING
	jr c,.nt
	ld hl,tb_busy
	ld e,(ix+GR_TABLE)
	ld d,0
	add hl,de
	ld (hl),0
.nt:	push ix				; group + 1 = (IX - groups) / 16 + 1
	pop hl
	ld de,groups
	or a
	sbc hl,de
	ld a,l
	rrca
	rrca
	rrca
	rrca
	inc a
	ld hl,bill_carry
	cp (hl)
	jr nz,.nc
	xor a
	ld (hl),a
	ld (bill_plates),a
.nc:	ld (ix+GR_STATE),GS_LEAVING
	call sv_members
.lv:	ld (iy+CU_SIT),0
	ld (iy+CU_TX),DOOR_X&255
	ld (iy+CU_TX+1),DOOR_X>>8
	ld (iy+CU_TY),DOOR_Y&255
	ld (iy+CU_TY+1),DOOR_Y>>8
	ld de,CU_SIZE
	add iy,de
	djnz .lv
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

; Count down the group's timer: Z at 0.
sv_dect:
	ld l,(ix+GR_T)
	ld h,(ix+GR_T+1)
	dec hl
	ld (ix+GR_T),l
	ld (ix+GR_T+1),h
	ld a,h
	or l
	ret

; IX = group A
sv_group_a:
	add a,a
	add a,a
	add a,a
	add a,a
	ld e,a
	ld d,0
	ld ix,groups
	add ix,de
	ret

; carry if Bill is on the spot of table A (below it)
sv_at_table:
	call sv_table
	inc hl
	ld e,(hl)
	inc hl
	ld d,(hl)
	inc hl
	push hl
	ld hl,(bill_x)
	ld c,NEAR_X/2
	call sv_near
	pop hl
	ret nc
	ld e,(hl)
	inc hl
	ld d,(hl)
	ld hl,(bill_y)
	ld c,NEAR_Y/2
	jp sv_near

; ---------------------------------------------------------------------------
; Fire: what is next to Bill.
sv_fire:
	ld a,(sv_phase)
	cp 2
	jp z,sv_new_day
	ld a,(sv_follow)
	or a
	jp nz,.seat
	ld hl,(bill_x)			; at the pass: take the plates of a ready order
	ld de,PASS_BX
	ld c,NEAR_X/2
	call sv_near
	jr nc,.tables
	ld hl,(bill_y)
	ld de,PASS_BY
	ld c,NEAR_Y
	call sv_near
	jr nc,.tables
	ld a,(bill_carry)
	or a
	jr nz,.tables
	ld ix,groups
	ld b,G_MAX
.p:	ld a,(ix+GR_STATE)
	cp GS_READY
	jr z,.pick
	ld de,GR_SIZE
	add ix,de
	djnz .p
	jr .tables
.pick:	ld (ix+GR_STATE),GS_CARRIED
	ld a,G_MAX			; group + 1
	sub b
	inc a
	ld (bill_carry),a
	ld a,(ix+GR_N)			; the tray holds 3 plates (the sprite)
	cp 4
	jr c,.p3
	ld a,3
.p3:	ld (bill_plates),a
	ret
.tables:				; at a group's table: order, serve, pay
	ld ix,groups
	ld b,G_MAX
.t:	push bc
	ld a,(ix+GR_STATE)
	cp GS_SEATED
	jr z,.tt
	cp GS_CARRIED
	jr z,.tt
	cp GS_PAY
	jr nz,.tn
.tt:	ld a,(ix+GR_TABLE)
	call sv_at_table
	jr c,.act
.tn:	ld de,GR_SIZE
	add ix,de
	pop bc
	djnz .t
	jp .queue
.act:	pop bc
	ld a,(ix+GR_STATE)
	cp GS_SEATED
	jr nz,.serve
	ld (ix+GR_STATE),GS_ORDERED	; the order: to the kitchen
	ld (ix+GR_T),KITCHEN_T&255
	ld (ix+GR_T+1),KITCHEN_T>>8
	ld a,MOOD_ORDER
	ld (bill_bubble),a
	ld a,BUBBLE_T
	ld (sv_bub_t),a
	ld a,MOOD_FOOD
	call sv_mood
	jp sv_refill
.serve:	cp GS_CARRIED
	jr nz,.pay
	ld a,G_MAX			; their plates on Bill's tray?
	sub b
	inc a
	ld c,a
	ld a,(bill_carry)
	cp c
	ret nz
	xor a
	ld (bill_carry),a
	ld (bill_plates),a
	ld (ix+GR_STATE),GS_EATING
	ld (ix+GR_T),EAT_T&255
	ld (ix+GR_T+1),EAT_T>>8
	ld a,MOOD_HAPPY
	call sv_mood
	jp sv_refill
.pay:	ld b,(ix+GR_N)			; money and tip, the table is free, out
	ld hl,(sv_money)
	ld de,PRICE
.pm:	add hl,de
	djnz .pm
	ld a,(ix+GR_P)
	rlca
	rlca
	rlca
	and 7
	ld e,a
	add hl,de
	ld (sv_money),hl
	ld e,(ix+GR_N)
	ld d,0
	ld hl,(sv_served)
	add hl,de
	ld (sv_served),hl
	push ix
	call sv_hud_money
	call sv_hud_served
	pop ix
	xor a
	jp sv_leave
.queue:					; next to the queue: they follow
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
	call sv_group_a
	ld c,0				; tables
.st:	ld a,c
	cp TABLE_COUNT
	ret nc
	ld hl,tb_busy
	ld e,c
	ld d,0
	add hl,de
	ld a,(hl)
	or a
	jr nz,.sn
	ld a,c
	call sv_table
	ld a,(hl)			; seats enough?
	cp (ix+GR_N)
	jr c,.sn
	push bc
	ld a,c
	call sv_at_table
	pop bc
	jr c,.sit
.sn:	inc c
	jr .st
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

; A plate over the pass while an order waits there (render, bank 5).
service_sprites:
	ld ix,groups
	ld b,G_MAX
.l:	ld a,(ix+GR_STATE)
	cp GS_READY
	jr z,.show
	ld de,GR_SIZE
	add ix,de
	djnz .l
	ret
.show:	ld de,PASS_X-8
	ld bc,PASS_Y+8
	ld a,MOOD_FOOD
	jp bubble_a

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
