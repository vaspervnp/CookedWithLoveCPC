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
; Tables: a group that ate leaves its plates (drawn with the tray sprite, a
; stamp); the table is taken again only when Bill has cleared it: fire at
; its spot with empty hands takes the plates on the tray, fire at the pass
; leaves them there.
;
; Bubbles: in the queue "...", seated (wants to order) the notepad, waiting
; for the food a plate, eating a heart, wants to pay a coin; a plate over
; the pass when an order is ready.

; (G_MAX, GR_SIZE, TRAIL_N and the big tables: src/game/vars.asm)
QUEUE_PEOPLE	equ 6		; customers waiting at the entrance at most
QUEUE_SLOTS	equ 2		; groups waiting at the entrance
WALK_MAX	equ 5		; customers walking at the same time (+ Bill = 6
				; moving figures; the others wait, still ones are
				; stamps)

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
GR_SLOT		equ 9		; place in the queue (0 = front)
GR_DISH		equ 10		; the dish of each customer (4 bytes)
GR_KIT		equ 14		; Medium: bits 0-3 dish started, 4-7 at the pass
GR_ORD		equ 15		; Medium: order number (src/game/kitchen.asm)

; entrance (level 1: the mats at metatiles 8-9 of the bottom row)
DOOR_X		equ 128		; customer sprite left/top
DOOR_Y		equ 623
QUEUE_X		equ 128		; first in the queue; the others to its left
QUEUE_Y		equ 583
QUEUE_DX	equ 14
QUEUE_DY	equ 24		; the next group: a row behind (above)
	if TEST_FILL
SPAWN_TICKS	equ 60
	else
SPAWN_TICKS	equ 300		; a new group at most every 6 s
	endif

FOLLOW_GAP	equ 5		; trail entries between the followers
NEAR_X		equ 28		; fire reaches this far (feet to feet)
NEAR_Y		equ 24
EAT_T		equ 600		; eating: 12 s
BUBBLE_T	equ 50		; Bill's notepad bubble after taking an order
TALK_MAX	equ 3		; sitting customers talking at the same time
TALK_CHANCE	equ 6		; out of 256 per tick: someone starts talking
PAT_RATE	equ 12
PAT_REFILL	equ 96
PAT_ANGRY	equ 64

sv_prev:	db 0		; input of the last tick (fire edge)
sv_follow:	db 0		; group + 1 following Bill
sv_spawn_t:	dw 50
sv_tick:	db 0
sv_seed:	dw #ACE1
trail_head:	db 0
bill_carry:	db 0		; group + 1 whose plates Bill carries
sv_bub_t:	db 0
sv_dirty:	db 0		; Bill carries dirty plates
TB_DIRTY	equ #80		; tb_busy: plates left (+ their number, 1-3)
TB_LOCKED	equ #40		; tb_busy: in the expansion, not bought yet
EXP_COST	equ 300		; the expansion (src/ovl/prep.asm)
sv_exp:		db 0		; bought
START_MONEY	equ 150		; the economy (portions: src/ovl/prep.asm)
DAY_COST	equ 50		; rent and wages, at the end of each day
sv_money:	dw START_MONEY
sv_served:	dw 0		; customers who paid today
sv_lost:	dw 0		; customers who left angry today
sv_day:		db TEST_FILL	; (the preparation counts the day on)
sv_phase:	db 0		; SP_*: open, closed (no more arrivals), over, ...
SP_OPEN		equ 0
SP_CLOSED	equ 1
SP_OVER		equ 2		; everybody gone: the summary (src/ovl/prep.asm)
SP_PREP		equ 3		; the morning: portions of each dish
SP_BROKE	equ 4		; the money did not cover the day: game over
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
HUD_ROW3	equ 3		; the status: open, closed, the day over;
HUD_QUEUE	equ 9		; waiting at the entrance (icon, digit)
HUD_STOCK	equ 16		; portions left: dish d at HUD_STOCK + 3 d
MINUTE_TICKS	equ 50		; a game minute every second

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

; The status (HUD row 3, columns 1-7) of phase A: open or closed (the
; others: src/ovl/prep.asm).
sv_status:
	push af
	ld a,HUD_BG
	ld b,a
	call hud_colors
	ld bc,(1<<8)+HUD_ROW3
	ld e,HUD_QUEUE
	call hud_spaces
	pop af
	ld hl,txt_open
	ld c,10				; open: green
	or a
	jr z,.one
	ld hl,txt_closed
	ld c,4				; closed: red
.one:	push hl
	ld a,c
	ld b,HUD_BG
	call hud_colors
	pop hl
	ld bc,(1<<8)+HUD_ROW3
	jp hud_text

; ---------------------------------------------------------------------------
; One game tick (bank 5).
service_tick:
	ifdef TEST_SFX			; test: the effects in turn, 2 s apart
	ld hl,.tsfx
	inc (hl)
	ld a,(hl)
	and 31
	jr nz,.ts
	ld a,(hl)
	rrca
	rrca
	rrca
	rrca
	rrca
	and 7
	cp SFX_DONE+1
	call c,sfx_play
	jr .ts
.tsfx:	db 0
.ts:
	endif
	ld a,(sv_phase)			; between the days: the overlay
	cp SP_OVER
	jr c,.day
	ld a,(ovl_req)			; (once loaded)
	or a
	ret nz
	jp OVL_TICK
.day:
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
	call sv_status
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
	ld a,(sv_menu)			; the menu at the pass: its keys
	or a
	jr z,.nm
	call sv_menu_keys
	jr .mk
.nm:	bit KEY_SWAP,c			; the other character
	call nz,staff_swap
	ld a,(ctl_who)			; fire: Bill's, Liberty's or Blossom's
	or a
	jr z,.fb
	bit KEY_FIRE,c
	jr z,.mk
	dec a
	call z,lib_fire
	ld a,(ctl_who)
	cp 2
	call z,blo_fire
	jr .mk
.fb:	bit KEY_FIRE,c
	call nz,sv_fire
.mk:	call sv_cook_tick
	call kitchen_tick
	call storage_tick
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
	call sv_hud_queue
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
	ld a,SP_OVER			; the summary and the next morning: the
	ld (sv_phase),a			; overlay, loaded now that only Bill
	ld a,1				; is on screen (src/game/area.asm)
	ld (ovl_req),a
.nw:	call sv_talk
	ld a,(cust_anim)		; walking: a step every other tick
	rrca
	ret c
	jp sv_walk

; The sitting customers chat: a few at a time, chosen at random, for 1-2.5 s.
sv_talk:
	ld iy,cust_list			; time runs out; count the talking ones
	ld b,CU_COUNT
	ld c,0
.l:	ld a,(iy+CU_TALK)
	or a
	jr z,.n
	inc c
	ld a,(iy+CU_SIT)		; (got up meanwhile: stops)
	or a
	jr z,.st
	dec (iy+CU_TALK)
	jr .n
.st:	ld (iy+CU_TALK),0
.n:	ld de,CU_SIZE
	add iy,de
	djnz .l
	ld a,c
	cp TALK_MAX
	ret nc
	call sv_rand			; now and then someone else
	cp TALK_CHANCE
	ret nc
	call sv_rand			; who: a random customer, if sitting
	and 31
	cp CU_COUNT
	ret nc
	call sv_cust
	ld a,(iy+CU_ON)
	and (iy+CU_SIT)
	ret z
	ld a,(iy+CU_TALK)
	or a
	ret nz
	call sv_rand			; 50-113 ticks
	and 63
	add a,50
	ld (iy+CU_TALK),a
	ret

; ---------------------------------------------------------------------------
; HL = customer A of the pool, IY too
sv_cust:
	ld l,a				; A*20 = A*16 + A*4
	ld h,0
	add hl,hl
	add hl,hl
	ld d,h
	ld e,l
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
	ld ix,groups			; queue full or no free group: later
	ld b,G_MAX
	ld iy,0
	ld c,0				; groups at the entrance
	ld l,c				; and their customers
.f:	ld a,(ix+GR_STATE)
	cp GS_ARRIVE
	jr z,.q
	cp GS_QUEUE
	jr nz,.nq
.q:	inc c
	ld a,l
	add a,(ix+GR_N)
	ld l,a
	jr .n
.nq:	or a
	jr nz,.n
	ld a,iyh
	or iyl
	jr nz,.n
	push ix
	pop iy
.n:	ld de,GR_SIZE
	add ix,de
	djnz .f
	ld a,c
	cp QUEUE_SLOTS
	ret nc
	ld a,iyh
	or iyl
	ret z
	ld a,QUEUE_PEOPLE		; room for QUEUE_PEOPLE - L more
	sub l
	ret z
	ret c
	push iy
	pop ix
	ld (ix+GR_SLOT),c
	ld c,a
	push bc
	call sv_rand			; size 1-4 (at most the room)
	pop bc
	and 3
	inc a
	cp c
	jr c,.sz
	ld a,c
.sz:	ld (ix+GR_N),a
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
	call sv_members			; in at the door
.m:	push bc
	ld (iy+CU_ON),1
	ld (iy+CU_X),DOOR_X&255
	ld (iy+CU_X+1),DOOR_X>>8
	ld (iy+CU_Y),DOOR_Y&255
	ld (iy+CU_Y+1),DOOR_Y>>8
	ld (iy+CU_DIR),DIR_UP
	xor a
	ld (iy+CU_STILL),a
	ld (iy+CU_SIT),a
	ld (iy+CU_MOOD),a
	ld (iy+CU_DX),a
	call .style
	ld (iy+CU_HEAD),a
	call .style
	ld (iy+CU_BODY),a
	call .style
	ld (iy+CU_LEGS),a
	ld de,CU_SIZE
	add iy,de
	pop bc
	djnz .m
	jp sv_to_queue
.busy:	inc c
	jp .try
.style:	call sv_rand			; 0-2
	and 3
	cp 3
	jr z,.style
	ret

; Group IX walks to its place in the queue (slot GR_SLOT): member k at
; QUEUE_X - k*QUEUE_DX, a row of QUEUE_DY lines per slot.
sv_to_queue:
	ld (ix+GR_STATE),GS_ARRIVE
	ld hl,QUEUE_Y
	ld de,-QUEUE_DY
	ld b,(ix+GR_SLOT)
	inc b
	jr .s
.sl:	add hl,de
.s:	djnz .sl
	ld (tq_y),hl
	call sv_members
	ld hl,QUEUE_X
.m:	ld (iy+CU_STILL),0
	ld (iy+CU_TX),l
	ld (iy+CU_TX+1),h
	ld de,(tq_y)
	ld (iy+CU_TY),e
	ld (iy+CU_TY+1),d
	ld de,-QUEUE_DX
	add hl,de
	ld de,CU_SIZE
	add iy,de
	djnz .m
	ret

; A group left the queue: the ones behind it move up.
sv_queue_up:
	ld ix,groups
	ld b,G_MAX
.g:	push bc
	ld a,(ix+GR_STATE)
	cp GS_ARRIVE
	jr z,.q
	cp GS_QUEUE
	jr nz,.n
.q:	ld a,(ix+GR_SLOT)
	or a
	jr z,.n
	dec (ix+GR_SLOT)
	call sv_to_queue
.n:	ld de,GR_SIZE
	add ix,de
	pop bc
	djnz .g
	ret

tq_y:	dw 0

; ---------------------------------------------------------------------------
; State of group IX.
sv_group:
	if TEST_FILL			; test: the queue sits down by itself
	ld a,(ix+GR_STATE)
	cp GS_QUEUE
	jr nz,.state
	ld c,0
.ft:	ld a,c
	cp TABLE_COUNT
	jr nc,.state
	ld hl,tb_busy
	ld e,c
	ld d,0
	add hl,de
	ld a,(hl)
	or a
	jr nz,.fn
	push bc
	ld a,c
	call sv_table
	pop bc
	ld a,(hl)
	cp (ix+GR_N)
	jr nc,.fs
.fn:	inc c
	jr .ft
.fs:	xor a
	ld (ix+GR_MOOD),a
	push bc
	call sv_members
.fm:	ld (iy+CU_STILL),0
	ld (iy+CU_MOOD),0
	ld de,CU_SIZE
	add iy,de
	djnz .fm
	pop bc
	push ix				; index + 1 = (IX - groups) / 16 + 1
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
	call sv_sit
	jp sv_queue_up
	else
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
	ld a,(sv_mode)			; Medium: waiting for Liberty's kitchen
	or a				; at half the rate
	jr z,.pd
	ld a,(ix+GR_STATE)
	cp GS_ORDERED
	jr nz,.pd
	ld (ix+GR_PT),PAT_RATE*2
.pd:	dec (ix+GR_P)
	jp z,sv_angry
	ld a,(ix+GR_P)
	cp PAT_ANGRY-1
	call z,sv_show_mood
	endif
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
.cook:	ld a,(sv_mode)			; Medium: Liberty cooks (kitchen.asm)
	or a
	ret nz
	call sv_dect
	ret nz
	ld (ix+GR_STATE),GS_READY
	ld a,SFX_READY
	call sfx_play
	push ix
	call sv_hud_tickets
	pop ix
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
	ld (iy+CU_STILL),1
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
	call sv_done
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
	ld a,SFX_ANGRY
	call sfx_play
	ld e,(ix+GR_N)
	ld d,0
	ld hl,(sv_lost)
	add hl,de
	ld (sv_lost),hl
	push ix
	call sv_hud_lost
	pop ix
	ld a,(ix+GR_STATE)		; their order is dropped
	cp GS_ORDERED
	jr c,.nk
	cp GS_CARRIED
	jr nc,.nk
	ld (ix+GR_STATE),GS_SEATED	; (no ticket any more)
	push ix
	call sv_hud_tickets
	pop ix
.nk:	ld a,MOOD_ANGRY
	; fall through

; The group leaves (mood A on the way): the table is free again, the
; plates on Bill's tray for them are wasted, all walk to the door.
sv_leave:
	call sv_mood
	ld a,(ix+GR_STATE)
	cp GS_SEATING
	sbc a,a				; FF: no table (from the queue)
	ld (sl_notab),a
	ld a,(ix+GR_STATE)
	cp GS_SEATING
	jr c,.nt
	ld hl,tb_busy			; the table: free, or their plates on it
	ld e,(ix+GR_TABLE)
	ld d,0
	add hl,de
	ld c,0
	cp GS_EATING
	jr c,.fr
	ld a,(ix+GR_N)
	cp 4
	jr c,.d3
	ld a,3
.d3:	or TB_DIRTY
	ld c,a
.fr:	ld (hl),c
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
.nc:	ld a,(ix+GR_STATE)
	ld (ix+GR_STATE),GS_LEAVING
	cp GS_QUEUE
	jr nz,.nq
	push ix
	call sv_queue_up
	pop ix
.nq:	call sv_members
.lv:	ld (iy+CU_SIT),0
	ld (iy+CU_STILL),0
	ld (iy+CU_TALK),0
	ld (iy+CU_TX),DOOR_X&255	; from the queue: straight to the door
	ld (iy+CU_TX+1),DOOR_X>>8
	ld (iy+CU_TY),DOOR_Y&255
	ld (iy+CU_TY+1),DOOR_Y>>8
	ld (iy+CU_ROUTE),0
	ld a,(sl_notab)
	or a
	jr nz,.lq
	ld a,(ix+GR_TABLE)		; from a table: around the tables
	add a,a
	add a,a
	ld (iy+CU_RTAB),a
	ld (iy+CU_ROUTE),R_DOOR<<4
	push bc
	call sv_route_next
	pop bc
.lq:	ld de,CU_SIZE
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

; Z if customer IY is at its target at the end of its route
sv_done:
	call sv_at
	ret nz
	ld a,(iy+CU_ROUTE)
	or a
	ret

; Routes around the tables (no path finding: points from the table's data).
; To a seat: to Bill's spot below the table (the group follows him there:
; it is close), along its row (always free) to the chair's column, into
; the chair. To the door: down
; to that row, along it to the trunk (a free column to the entrance,
; TRUNK_X from tools/buildmap.py), down it to the door's row, to the door.
R_SEAT		equ 1
R_DOOR		equ 2

; Customer IY reached a point of its route: the next one (NZ), or Z when
; it has no route (any more).
sv_route_next:
	ld a,(iy+CU_ROUTE)
	or a
	ret z
	ld c,a				; kind << 4 + step
	inc a
	ld (iy+CU_ROUTE),a
	ld a,(iy+CU_RTAB)
	rrca
	rrca
	and #3F
	push bc
	call sv_table
	pop bc
	push hl
	ld de,TB_BY			; the row below the table: Bill's feet - 47
	add hl,de
	ld e,(hl)
	inc hl
	ld d,(hl)
	ld hl,-47
	add hl,de
	ld (rn_row),hl
	pop hl
	push hl				; Bill's spot as a sprite left: x - 16
	inc hl				; (TB_BX)
	ld e,(hl)
	inc hl
	ld d,(hl)
	ld hl,-16
	add hl,de
	ld (rn_spot),hl
	pop hl
	ld a,c
	and #0F
	ld b,a				; B = step
	ld a,c
	and #F0
	cp R_SEAT<<4
	jr nz,.door
	ld a,(iy+CU_RTAB)		; seat k: x, y
	and 3
	ld e,a
	add a,a
	add a,a
	add a,e
	add a,TB_SEAT0
	ld e,a
	ld d,0
	add hl,de
	ld e,(hl)
	inc hl
	ld d,(hl)
	inc hl
	ld (rn_x),de
	ld e,(hl)
	inc hl
	ld d,(hl)
	ld (rn_y),de
	ld a,b
	or a
	ld hl,(rn_spot)
	jr z,.rowx			; 0: to Bill's spot
	dec a
	ld hl,(rn_x)
	jr z,.rowx			; 1: along its row to the chair's column
	ld de,(rn_y)			; 2: into the chair, the end
	jr .last
.door:	ld a,b
	or a
	jr z,.row			; 0: to the row
	dec a
	ld hl,TRUNK_X
	jr z,.rowx			; 1: along it to the trunk
	dec a
	ld de,DOOR_Y
	jr z,.set			; 2: down the trunk
	ld hl,DOOR_X			; 3: to the door, the end
.last:	ld (iy+CU_ROUTE),0
.set:	ld (iy+CU_TX),l
	ld (iy+CU_TX+1),h
	ld (iy+CU_TY),e
	ld (iy+CU_TY+1),d
	or 1				; NZ: a new target
	ret
.row:	ld l,(iy+CU_X)			; straight down/up from here
	ld h,(iy+CU_X+1)
.rowx:	ld de,(rn_row)
	jr .set

sl_notab:	db 0
rn_row:	dw 0
rn_spot:	dw 0
rn_x:	dw 0
rn_y:	dw 0

; Z if all of group IX are at their targets
sv_arrived:
	call sv_members
.l:	call sv_done
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

; The order of group IX: each customer chooses a dish of the menu (with
; portions left: there are enough for all); the kitchen needs the time of
; the slowest.
sv_choose:
	push ix
	pop iy
	ld b,(ix+GR_N)
	ld hl,0				; the longest time
.c:	push bc
	push hl
	call sv_rand
	and 7				; (DISH_N = 8): this one or the next
.f:	ld e,a				; with portions left
	ld d,0
	ld hl,sv_stock
	add hl,de
	ld a,(hl)
	or a
	jr nz,.got
	ld a,e
	inc a
	and 7
	jr .f
.got:	dec (hl)
	ld a,e
	ld (iy+GR_DISH),a
	add a,a
	ld e,a
	ld d,0
	ld hl,dish_ticks
	add hl,de
	ld e,(hl)
	inc hl
	ld d,(hl)
	pop hl
	push hl
	or a
	sbc hl,de
	pop hl
	jr nc,.n
	ex de,hl
.n:	inc iy
	pop bc
	djnz .c
	ld (ix+GR_T),l
	ld (ix+GR_T+1),h
	push ix
	call sv_hud_tickets
	pop ix
	ret
	assert DISH_N==8

; HUD row 2 from column HUD_TICKETS: a ticket per order in the kitchen
; (grey icons) or on the pass (in their colours), the icons of its dishes.
HUD_TICKETS	equ 8
sv_hud_tickets:
	ld a,HUD_BG			; clear the row
	ld b,a
	call hud_colors
	ld bc,(HUD_TICKETS<<8)+HUD_ROW2
	ld e,40
	call hud_spaces
	ld a,HUD_TICKETS
	ld (st_col),a
	ld ix,groups
	ld b,G_MAX
.g:	push bc
	ld a,(ix+GR_STATE)
	cp GS_ORDERED
	jr z,.t
	cp GS_READY
	jr nz,.gn
.t:	ld a,(ix+GR_N)			; room for it?
	add a,a
	ld c,a
	ld a,(st_col)
	add a,c
	cp 41
	jr nc,.gn
	push ix
	pop iy
	ld a,(ix+GR_KIT)		; (Medium: the dishes at the pass)
	rrca
	rrca
	rrca
	rrca
	and #0F
	ld (tk_kit),a
	ld b,(ix+GR_N)
.d:	push bc
	ld a,(iy+GR_DISH)
	ld c,a
	ld hl,tk_kit			; at the pass, or ready: the dish's
	srl (hl)			; colour, cooking: grey
	jr c,.col
	ld a,(ix+GR_STATE)
	cp GS_READY
	ld a,12
	jr nz,.ink
.col:	ld hl,dish_ink
	ld a,l
	add a,c
	ld l,a
	ld a,h
	adc a,0
	ld h,a
	ld a,(hl)
.ink:	push bc
	ld b,HUD_BG
	call hud_colors
	pop bc
	ld a,c
	add a,a
	add a,G_DISH0
	push af
	ld a,(st_col)
	ld b,a
	ld c,HUD_ROW2
	pop af
	push af
	call hud_char
	pop af
	inc a
	ld hl,st_col
	ld b,(hl)
	inc b
	inc (hl)
	inc (hl)
	ld c,HUD_ROW2
	call hud_char
	inc iy
	pop bc
	djnz .d
	ld hl,st_col			; a gap
	inc (hl)
.gn:	ld de,GR_SIZE
	add ix,de
	pop bc
	dec b
	jp nz,.g
	ret

st_col:	db 0
tk_kit:	db 0

; HUD row 3: the portions left of each dish (sold out: grey). The menu at
; the pass open: the chosen one in its colour, the others grey, and the
; portions with the ones cooking.
sv_hud_stock:
	ld a,(ctl_who)			; Blossom's: the storage (storage.asm)
	cp 2
	jp z,st_hud
	push ix
	ld c,0
.d:	push bc
	ld b,0
	ld hl,sv_stock
	add hl,bc
	ld e,(hl)			; portions
	ld hl,dish_ink
	add hl,bc
	ld a,(sv_menu)
	or a
	ld a,(hl)
	jr z,.nm
	ld hl,sv_cook
	add hl,bc
	ld b,a
	ld a,e
	add a,(hl)
	ld e,a
	ld a,(sv_mcur)
	cp c
	ld a,b
	jr z,.ink
	jr .gr
.nm:	inc e
	dec e
	jr nz,.ink
.gr:	ld a,12
.ink:	push de
	ld b,HUD_BG
	call hud_colors
	pop de
	pop bc
	push bc
	push de
	ld a,c				; column: HUD_STOCK + 3 d
	ld b,a
	add a,a
	add a,b
	add a,HUD_STOCK
	ld b,a
	ld a,c
	add a,a
	add a,G_DISH0
	push bc
	push af
	ld c,HUD_ROW3
	call hud_char
	pop af
	pop bc
	inc a
	inc b
	push bc
	ld c,HUD_ROW3
	call hud_char
	pop bc
	inc b
	pop de
	ld l,e
	ld h,0
	ld d,1
	ld c,HUD_ROW3
	call hud_number
	pop bc
	inc c
	ld a,c
	cp DISH_N
	jr nz,.d
	pop ix
	ret

; The menu at the pass (keys pressed this tick in C): left/right the dish,
; up a portion more (its ingredients paid, cooked in the kitchen's turn:
; sv_cook_tick), fire or down: closed. Up to 9 of a dish with the cooking.
sv_menu_keys:
	ld hl,sv_mcur
	bit KEY_LEFT,c
	jr z,.r
	dec (hl)
	jr .w
.r:	bit KEY_RIGHT,c
	jr z,.u
	inc (hl)
.w:	ld a,(hl)
	and DISH_N-1
	ld (hl),a
	jp sv_hud_stock
.u:	bit KEY_UP,c
	jr nz,.more
	ld a,c
	and (1<<KEY_FIRE)|(1<<KEY_DOWN)
	ret z
	xor a
	ld (sv_menu),a
	jp sv_hud_stock
.more:	ld e,(hl)
	ld d,0
	ld hl,sv_stock
	add hl,de
	ld a,(hl)
	ld hl,sv_cook
	add hl,de
	add a,(hl)
	cp 9
	ret nc
	ld a,(sv_mode)			; Hard: its ingredients from the hatch
	cp 2
	jr nz,.cost
	push hl
	ld a,e
	ld hl,st_hatch
	call st_have
	pop de
	ret nz
	ld a,(sv_mcur)
	ld hl,st_hatch
	call st_take
	ex de,hl
	inc (hl)
	jp sv_hud_stock
.cost:	push hl
	ld hl,dish_cost
	add hl,de
	ld c,(hl)
	ld b,0
	ld hl,(sv_money)
	or a
	sbc hl,bc
	pop de
	ret c				; (no money)
	ld (sv_money),hl
	ex de,hl
	inc (hl)
	call sv_hud_money
	jp sv_hud_stock

; (sv_menu, sv_mcur, sv_cook_t, sv_cook_d: src/game/vars.asm)

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
	ld a,(sv_dirty)			; dirty plates: left at the pass
	or a
	jr z,.pf
	xor a
	ld (sv_dirty),a
	ld (bill_plates),a
	ret
.pf:	ld a,(bill_plates)		; empty hands: the plates of a ready order
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
	ld a,1				; nothing ready: the menu (more portions)
	ld (sv_menu),a
	jp sv_hud_stock
.pick:	ld (ix+GR_STATE),GS_CARRIED
	push bc
	push ix
	call sv_hud_tickets
	pop ix
	pop bc
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
.tables:				; a table with plates left: clear it
	ld a,(bill_plates)
	or a
	jr nz,.tg
	ld c,0
.dt:	ld a,c
	cp TABLE_COUNT
	jr nc,.tg
	ld hl,tb_busy
	ld e,c
	ld d,0
	add hl,de
	ld a,(hl)
	and TB_DIRTY
	jr z,.dn
	push hl
	push bc
	ld a,c
	call sv_at_table
	pop bc
	pop hl
	jr nc,.dn
	ld a,(hl)			; on the tray, the table is free
	and 3
	ld (bill_plates),a
	ld (hl),0
	ld a,1
	ld (sv_dirty),a
	ret
.dn:	inc c
	jr .dt
.tg:					; at a group's table: order, serve, pay
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
	ld hl,sv_stock			; portions left for all of them?
	ld b,DISH_N
	xor a
.stk:	add a,(hl)
	inc hl
	djnz .stk
	cp (ix+GR_N)
	jp c,sv_angry			; no: they leave
	ld (ix+GR_STATE),GS_ORDERED	; the order: to the kitchen
	ld (ix+GR_KIT),0
	ld hl,sv_ordseq
	ld a,(hl)
	ld (ix+GR_ORD),a
	inc (hl)
	call sv_choose
	call sv_hud_stock
	ld a,SFX_ORDER
	call sfx_play
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
	ld a,SFX_SERVE
	call sfx_play
	ld a,MOOD_HAPPY
	call sv_mood
	jp sv_refill
.pay:	ld b,(ix+GR_N)			; money (their dishes) and tip, the table
	ld hl,(sv_money)		; is free, out
	push ix
.pm:	ld a,(ix+GR_DISH)
	push hl
	ld hl,dish_price
	add a,l
	ld l,a
	ld a,h
	adc a,0
	ld h,a
	ld e,(hl)
	ld d,0
	pop hl
	add hl,de
	inc ix
	djnz .pm
	pop ix
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
	ld a,SFX_COIN
	call sfx_play
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
	call sv_members
.ns:	ld (iy+CU_STILL),0
	ld de,CU_SIZE
	add iy,de
	djnz .ns
	call sv_trail_fill
	jp sv_queue_up
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
.sit:	ld a,(sv_follow)
	push af
	xor a
	ld (sv_follow),a
	pop af
	; fall through

; Group IX (A = its index + 1) takes table C: they walk to their chairs.
sv_sit:
	ld (ix+GR_TABLE),c		; the table is theirs
	ld hl,tb_busy
	ld e,c
	ld d,0
	add hl,de
	ld (hl),a
	ld (ix+GR_STATE),GS_SEATING
	call sv_members			; member k: a route to seat k
	ld c,0
.m:	push bc
	ld a,(ix+GR_TABLE)
	add a,a
	add a,a
	add a,c
	ld (iy+CU_RTAB),a
	ld (iy+CU_ROUTE),R_SEAT<<4
	call sv_route_next
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
	call kitchen_sprites		; (Medium)
	ld c,0				; plates left on tables (the tray sprite,
.t:	ld a,c				; a stamp)
	cp TABLE_COUNT
	jr nc,.pass
	ld hl,tb_busy
	ld e,c
	ld d,0
	add hl,de
	ld a,(hl)
	bit 7,a
	jr z,.tn
	and 3
	dec a
	add a,a
	ld e,a
	ld d,0
	push bc
	ld hl,tray_frames
	add hl,de
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	push hl
	ld a,c				; above Bill's spot: x - 16, y - 34
	call sv_table
	inc hl
	ld e,(hl)
	inc hl
	ld d,(hl)
	inc hl
	ld c,(hl)
	inc hl
	ld b,(hl)
	ld hl,-16
	add hl,de
	ex de,hl
	ld hl,-34
	add hl,bc
	ld b,h
	ld c,l
	call spr_visible		; (in the view only)
	pop hl
	jr nc,.tv
	ld a,1
	ld (spr_stamp),a
	call sprites_add
.tv:	pop bc
.tn:	inc c
	jr .t
.pass:	ld ix,groups
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
; longer way (a pixel is two lines wide). At most WALK_MAX walk at once:
; those that walked last time go on first, the others wait.
sv_walk:
	xor a
	ld (sw_n),a
	inc a				; first those that walked last time,
	call .pass
	xor a				; then the others, WALK_MAX in all
.pass:	ld (sw_pass),a
	ld iy,cust_list
	ld b,CU_COUNT
.l:	push bc
	ld a,(iy+CU_ON)
	or a
	jp z,.next
	ld a,(iy+CU_SIT)
	or a
	jp nz,.next
	ld a,(sw_pass)
	cp (iy+CU_DX)
	jp nz,.next
	call sv_at			; there: the next point of its route,
	jr nz,.go			; or it stands
	push bc
	call sv_route_next
	pop bc
	jp z,.stop
.go:
	ld a,(sw_n)
	cp WALK_MAX
	jp nc,.stop			; too many walking: waits
	inc a
	ld (sw_n),a
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
	jr .next
.stop:	ld (iy+CU_DX),0
.next:	ld de,CU_SIZE
	add iy,de
	pop bc
	dec b
	jp nz,.l
	ret

sw_n:	db 0
sw_pass:	db 0
sw_ax:	dw 0
sw_ay:	dw 0
sw_dx:	db 0
sw_dy:	db 0
