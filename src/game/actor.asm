; Bill: player-controlled waiter, collision with solid tiles, walk animation,
; camera that follows him with a dead-zone. One call to actor_tick = 1/50 s.
;
; Position = feet point in map pixels/lines. The sprite (32x48) is drawn with
; its top-left at (x-16, y-47); x is rounded down to even (2-pixel bytes).
; Movement uses 8-bit fractions: horizontal 0.625 px/tick, vertical 1.25
; lines/tick (Mode 0 pixels are twice as wide as tall, so both look alike).

DIR_DOWN	equ 0
DIR_UP		equ 1
DIR_RIGHT	equ 2
DIR_LEFT	equ 3

SPEED_X		equ 160		; 1/256 px per tick
SPEED_Y		equ 320		; 1/256 line per tick
ANIM_STEP	equ 7		; distance units per walk frame

SOLID_FIRST	equ 48		; tiles >= this block movement

; feet box relative to (x, y)
FOOT_L		equ -6
FOOT_R		equ 5
FOOT_T		equ -5

; camera dead-zone (feet position on screen)
CAM_L		equ 60
CAM_R		equ 100
	ifndef CAM_T			; (tests: smaller puts Bill in the partial top row)
CAM_T		equ 80
	endif
CAM_B		equ 128

actor_init:
	ld hl,BILL_X0
	ld (bill_x),hl
	ld hl,BILL_Y0
	ld (bill_y),hl
	xor a
	ld (bill_dir),a
	ld (bill_anim),a
	ret

; In: A = input bits (KEY_*). Needs RAM_C5 (map).
actor_tick:
	ld (at_in),a
	xor a
	ld (bill_moving),a
	; horizontal
	ld a,(at_in)
	bit KEY_RIGHT,a
	jr z,.nr
	ld a,DIR_RIGHT
	ld (bill_dir),a
	ld de,1
	call move_x
.nr:	ld a,(at_in)
	bit KEY_LEFT,a
	jr z,.nl
	ld a,DIR_LEFT
	ld (bill_dir),a
	ld de,-1
	call move_x
.nl:	ld a,(at_in)
	bit KEY_DOWN,a
	jr z,.nd
	ld a,(at_in)			; vertical keys set the facing unless moving sideways
	and (1<<KEY_LEFT)|(1<<KEY_RIGHT)
	jr nz,.d1
	ld a,DIR_DOWN
	ld (bill_dir),a
.d1:	ld de,1
	call move_y
.nd:	ld a,(at_in)
	bit KEY_UP,a
	jr z,.nu
	ld a,(at_in)
	and (1<<KEY_LEFT)|(1<<KEY_RIGHT)
	jr nz,.u1
	ld a,DIR_UP
	ld (bill_dir),a
.u1:	ld de,-1
	call move_y
.nu:
	; animation
	ld a,(bill_moving)
	or a
	jr nz,.anim
	xor a
	ld (bill_dist),a
	jr .cam
.anim:	ld a,(bill_dist)
	cp ANIM_STEP
	jr c,.cam
	sub ANIM_STEP
	ld (bill_dist),a
	ld a,(bill_anim)
	inc a
	and 3
	ld (bill_anim),a

.cam:	; camera: horizontal (screen x = x - 2*sx)
	ld hl,(bill_x)
	ld a,(scr_sx)
	ld e,a
	ld d,0
	or a
	sbc hl,de
	sbc hl,de
	bit 7,h
	jp nz,scroll_left		; left of the view (only after a jump)
	ld de,CAM_L
	push hl
	or a
	sbc hl,de
	pop hl
	call c,scroll_left
	ld de,CAM_R+1
	or a
	sbc hl,de
	call nc,scroll_right
	; vertical (screen y = y - sy), up to 2 lines per tick
	ld b,2
.cv:	push bc
	ld hl,(bill_y)
	ld de,(scr_sy)
	or a
	sbc hl,de
	ld de,CAM_T
	push hl
	or a
	sbc hl,de
	pop hl
	jr nc,.cv1
	call scroll_up
	jr .cv2
.cv1:	ld de,CAM_B+1
	or a
	sbc hl,de
	call nc,scroll_down
.cv2:	pop bc
	djnz .cv
	ret

; Move horizontally by DE = +1/-1 times SPEED_X.
move_x:
	ld a,(bill_xf)
	add a,lo(SPEED_X)
	ld (bill_xf),a
	ret nc				; less than a pixel so far
	ld hl,(bill_x)
	add hl,de
	push hl
	ld de,(bill_y)
	call box_free
	pop hl
	ret nz
	ld (bill_x),hl
	call moved			; 1 pixel = 2 distance units
	jr moved

; Move vertically by DE = +1/-1 times SPEED_Y (1 line + fraction).
move_y:
	ld a,(bill_yf)
	add a,lo(SPEED_Y)
	ld (bill_yf),a
	ld b,hi(SPEED_Y)
	jr nc,.n
	inc b
.n:	ld a,b
	or a
	ret z
.lp:	push bc
	push de
	ld hl,(bill_y)
	add hl,de
	ex de,hl			; DE = new y
	ld hl,(bill_x)
	push de
	call box_free
	pop de
	jr nz,.blk
	ld (bill_y),de
	call moved
	pop de
	pop bc
	djnz .lp
	ret
.blk:	pop de
	pop bc
	ret

moved:
	ld a,1
	ld (bill_moving),a
	ld hl,bill_dist
	inc (hl)
	ret

; Is the feet box at feet (HL = x, DE = y) free? Z = free.
box_free:
	ld (bf_x),hl
	ld (bf_y),de
	ld bc,FOOT_L
	ld de,FOOT_T
	call solid_at
	ret nz
	ld bc,FOOT_R
	ld de,FOOT_T
	call solid_at
	ret nz
	ld bc,FOOT_L
	ld de,0
	call solid_at
	ret nz
	ld bc,FOOT_R
	ld de,0
	jp solid_at

; NZ if the tile at (bf_x + BC, bf_y + DE) is solid (outside the map too).
solid_at:
	ld hl,(bf_y)
	add hl,de
	srl h
	rr l
	srl h
	rr l
	srl h
	rr l				; tile row
	ld a,h
	or a
	jr nz,.solid
	ld a,l
	cp MAP_H
	jr nc,.solid
	ld (sa_ty),a
	ld hl,(bf_x)
	add hl,bc
	srl h
	rr l
	srl h
	rr l
	srl h
	rr l				; tile column
	ld a,h
	or a
	jr nz,.solid
	ld a,l
	cp MAP_W
	jr nc,.solid
	ld c,a				; C = tile column
	ld a,(sa_ty)			; metatile: map + (row >> 1)*40 + (column >> 1)
	srl a
	ld l,a
	ld h,0
	add hl,hl
	add hl,hl
	add hl,hl
	ld d,h
	ld e,l
	add hl,hl
	add hl,hl
	add hl,de
	ld a,c
	srl a
	ld e,a
	ld d,0
	add hl,de
	ld de,map_data
	add hl,de
	ld e,(hl)
	ld a,(sa_ty)			; plane: (row & 1)*2 + (column & 1)
	and 1
	add a,a
	ld b,a
	ld a,c
	and 1
	or b
	add a,hi(meta_data)
	ld d,a
	ld a,(de)			; the tile
	cp SOLID_FIRST
	ld a,0
	jr c,.free
	inc a
.free:	or a
	ret
.solid:	or 1
	ret

sa_ty:	db 0

; Walk cycle of 4 steps over 3 frames (idle, walk 1, walk 2):
; A = step (0..3) -> A = pose
walk_frame:
	ld hl,walk_pose
	add a,l
	ld l,a
	ld a,h
	adc a,0
	ld h,a
	ld a,(hl)
	ret
walk_pose:	db 1,0,2,0

; Put Bill into the sprite list.
actor_sprites:
	ld a,(bill_dir)
	ld b,a				; frame = dir*3 + (moving ? walk_pose[anim] : 0)
	add a,a
	add a,b
	ld b,a
	ld a,(bill_moving)
	or a
	jr z,.idle
	ld a,(bill_anim)
	call walk_frame
	add a,b
	ld b,a
.idle:	ld a,b
	ld (dbg_frame),a
	ld l,b
	ld h,0
	add hl,hl
	ld de,bill_frames
	add hl,de
	ld a,(hl)			; frame descriptor
	inc hl
	ld h,(hl)
	ld l,a
	push hl
	ld hl,(bill_x)
	ld a,l
	and #FE
	ld l,a
	ld de,-16
	add hl,de
	ex de,hl			; DE = left
	ld hl,(bill_y)
	ld bc,-47
	add hl,bc
	ld b,h
	ld c,l				; BC = top
	pop hl
	if CLONES
	ld a,CLONES			; stress test: copies of Bill around him
	ld (cl_n),a
	ld (cl_x),de
	ld (cl_y),bc
	ld (cl_f),hl
	call sprites_add
.cl:	ld hl,(cl_x)
	ld de,26
	add hl,de
	ld (cl_x),hl
	ex de,hl
	ld hl,(cl_y)
	ld bc,9
	add hl,bc
	ld (cl_y),hl
	ld b,h
	ld c,l
	ld hl,(cl_f)
	call sprites_add
	ld hl,cl_n
	dec (hl)
	jr nz,.cl
	ret
cl_n:	db 0
cl_x:	dw 0
cl_y:	dw 0
cl_f:	dw 0
	else
	ld (tray_x),de
	ld (tray_y),bc
	call sprites_add
	jp bill_items
	endif

dbg_frame:	db 0
bill_x:		dw 0
bill_xf:	db 0
bill_y:		dw 0
bill_yf:	db 0
bill_dir:	db 0
bill_anim:	db 0
bill_dist:	db 0
bill_moving:	db 0
at_in:		db 0
bf_x:		dw 0
bf_y:		dw 0
