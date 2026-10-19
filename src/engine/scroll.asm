; Scrolling playfield: tile map -> 1024-word screen ring at &C000.
;
; Map char (X,Y) (X = 4-pixel column, Y = 8-line row) lives at ring word
; (Y*40 + X) & 1023 in every 2K block, so the view (40 x 22 chars) is always
; contiguous from word base = cy*40 + cx and scrolling only redraws the
; incoming column or row.
;
; Scroll position: sx in 2-pixel steps (0..MAX_SX), sy in lines (0..MAX_SY).
;   cx = (sx+1) >> 1, phase = sx & 1 (R3 = R3_ALT moves the picture 2 pixels
;   right, so odd positions show the next char column shifted right)
;   cy = sy >> 3, fy = sy & 7
;
; Fine vertical scroll: the top row of the view (row cy) is displayed with
; R9 = 7-fy, i.e. only rasters 0..7-fy. So that row is stored pre-shifted:
; tile rasters fy..7 go into screen blocks 0..7-fy (the hidden rasters are
; simply not stored). top_row/top_shift track which row is stored shifted.
;
; Screen memory that is visible must only change when the beam is not on it,
; so a frame update is done in this order (scroll_update):
;   1. moves: incoming rows are drawn at once (outside the visible view),
;      an incoming column is only noted (it overwrites a visible column)
;   2. build nxt_state
;   3. after A row 0 has been displayed: re-store the top row (fix_top)
;   4. once B has started (no playfield on screen): draw the column
;   5. flag nxt_state; I0 (VSYNC) commits it before A is displayed again

MAP_W		equ 80		; tiles (8x8)
MAP_H		equ 84
MAP_CW		equ MAP_W*2	; chars (4x8)
VIEW_CW		equ 40
VIEW_ROWS	equ PF_ROWS+1	; rows kept valid in the ring
MAX_SX		equ (MAP_CW-VIEW_CW)*2
MAX_SY		equ (MAP_H-PF_ROWS)*8

HUD_MA0		equ #2000	; HUD at word 0 of the &8000 page
HUD_MA1		equ #2100	; HUD copy for R3 phase 1 (word 256)

; ---------------------------------------------------------------------------
; Set an absolute scroll position and redraw the whole view.
; In: A = sx, HL = sy
scroll_set:
	ld (scr_sx),a
	inc a
	srl a
	ld (scr_cx),a
	ld (scr_sy),hl
	ld a,l
	and 7
	ld (scr_fy),a
	srl h
	rr l
	srl h
	rr l
	srl h
	rr l
	ld a,l
	ld (scr_cy),a
	ld a,255			; no row stored shifted yet
	ld (top_row),a
	xor a
	ld (top_shift),a
	ld a,255
	ld (pending_col),a
	ld a,(scr_cy)
	ld b,VIEW_ROWS
.row:	push af
	push bc
	call draw_row
	pop bc
	pop af
	inc a
	djnz .row
	ret

scroll_right:
	ld a,(scr_sx)
	cp MAX_SX
	ret nc
	inc a
	ld (scr_sx),a
	bit 0,a
	ret z
	inc a
	srl a
	ld (scr_cx),a
	add a,VIEW_CW-1
	ld (pending_col),a
	ret

scroll_left:
	ld a,(scr_sx)
	or a
	ret z
	dec a
	ld (scr_sx),a
	bit 0,a
	ret nz
	srl a
	ld (scr_cx),a
	ld (pending_col),a
	ret

scroll_down:
	ld hl,(scr_sy)
	ld de,MAX_SY
	or a
	sbc hl,de
	ret nc
	ld hl,(scr_sy)
	inc hl
	ld (scr_sy),hl
	ld a,l
	and 7
	ld (scr_fy),a
	ret nz
	ld a,(scr_cy)
	inc a
	ld (scr_cy),a
	add a,VIEW_ROWS-1
	jp draw_row

scroll_up:
	ld hl,(scr_sy)
	ld a,h
	or l
	ret z
	dec hl
	ld (scr_sy),hl
	ld a,l
	and 7
	ld (scr_fy),a
	cp 7
	ret nz
	ld a,(scr_cy)
	dec a
	ld (scr_cy),a
	jp draw_row

; ---------------------------------------------------------------------------
; Store row cy shifted by fy (and restore the previous top row if needed).
fix_top:
	ld a,(scr_cy)
	ld b,a
	ld a,(top_row)
	cp b
	jr nz,.moved
	ld a,(scr_fy)			; same row: did the shift change?
	ld c,a
	ld a,(top_shift)
	cp c
	ret z
	ld a,c
	ld (top_shift),a
	ld (dc_shift),a
	ld a,b
	jp draw_row_s
.moved:	ld a,(top_shift)		; old top row still visible -> unshift it
	or a
	jr z,.new
	ld a,(top_row)
	sub b
	jr c,.new
	cp VIEW_ROWS
	jr nc,.new
	xor a
	ld (dc_shift),a
	ld a,(top_row)
	call draw_row_s
.new:	ld a,(scr_cy)
	ld (top_row),a
	ld a,(scr_fy)
	ld (top_shift),a
	or a
	ret z
	ld (dc_shift),a
	ld a,(scr_cy)
	jp draw_row_s

; Finish a frame update after the moves (steps 2-5 above).
scroll_update:
	call scroll_build_state
	xor a
	ld (sync_row0),a
.r0:	ld a,(sync_row0)
	or a
	jr z,.r0
	call fix_top
	ld a,(pending_col)
	inc a
	jr z,.ready
	xor a
	ld (sync_bstart),a
.b:	ld a,(sync_bstart)
	or a
	jr z,.b
	ld a,(pending_col)
	call draw_col
	ld a,255
	ld (pending_col),a
.ready:	ld a,1
	ld (nxt_ready),a
	ret

; Build nxt_state from the current scroll position (not flagged yet).
scroll_build_state:
	; base = (cy*40 + cx) & 1023
	ld a,(scr_cy)
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
	ld a,(scr_cx)
	ld e,a
	ld d,0
	add hl,de
	call ma_ring
	ld ix,nxt_state
	ld (ix+ST_AMA),l
	ld (ix+ST_AMA+1),h

	ld a,(scr_fy)
	or a
	jr nz,.fine
	ld (ix+ST_AR4),PF_ROWS-1	; 21 rows, all R9 = 7
	ld (ix+ST_R9TOP),7
	ld (ix+ST_R9BOT),7
	ld a,8				; g
	jr .timing
.fine:	ld (ix+ST_AR4),PF_ROWS		; 22 rows
	ld b,a
	ld a,7
	sub b
	ld (ix+ST_R9TOP),a
	ld a,b
	dec a
	ld (ix+ST_R9BOT),a
	ld a,b				; g = fy

.timing:
	; W4A = slide_end - (C4 - 64g), W4B = slide_end - (64g - SLIDE_OVH4)
	push af
	call mul64
	push hl
	ld de,SLIDE_OVH4
	or a
	sbc hl,de
	ex de,hl
	ld hl,slide_end
	or a
	sbc hl,de
	ld (ix+ST_W4B),l
	ld (ix+ST_W4B+1),h
	pop hl
	ld de,slide_end-C4
	add hl,de
	ld (ix+ST_W4A),l
	ld (ix+ST_W4A+1),h
	pop af
	; W1 = slide_end - ((8-fy)*64 - SLIDE_OVH1)
	ld a,(scr_fy)
	ld b,a
	ld a,8
	sub b
	call mul64
	ld de,SLIDE_OVH1
	or a
	sbc hl,de
	ex de,hl
	ld hl,slide_end
	or a
	sbc hl,de
	ld (ix+ST_W1),l
	ld (ix+ST_W1+1),h

	; horizontal phase
	ld a,(scr_sx)
	and 1
	ld hl,HUD_MA0
	ld a,R3_STD
	jr z,.ph
	ld hl,HUD_MA1
	ld a,R3_ALT
.ph:	ld (ix+ST_R3),a
	ld (ix+ST_HUDMA),l
	ld (ix+ST_HUDMA+1),h
	ret

; HL = ring word (any) -> R12/R13 value for the &C000 page.
ma_ring:
	ld a,h
	and 3
	or #30
	ld h,a
	ret

; HL = A * 64
mul64:
	ld l,a
	ld h,0
	add hl,hl
	add hl,hl
	add hl,hl
	add hl,hl
	add hl,hl
	add hl,hl
	ret

; ---------------------------------------------------------------------------
; Draw map char row Y (A) for X = cx..cx+39, shifted if it is the top row.
draw_row:
	ld b,a
	ld a,(top_row)
	cp b
	ld a,0
	jr nz,.s
	ld a,(top_shift)
.s:	ld (dc_shift),a
	ld a,b
; Same with an explicit shift in dc_shift.
draw_row_s:
	cp MAP_H
	ret nc
	ld b,a
	ld a,(scr_cx)
	ld (ca_x),a
	ld a,b
	call char_addr
	ld b,VIEW_CW
.lp:	push bc
	ld a,(ix+0)
	call draw_char
	pop bc
	ld a,c
	xor 2
	ld c,a
	jr nz,.same
	inc ix
.same:	inc e
	inc e
	jr nz,.nw
	inc d
	ld a,d
	and 7
	or #C0
	ld d,a
.nw:	djnz .lp
	ret

; Draw map char column X (A) for Y = cy..cy+21.
draw_col:
	ld (ca_x),a
	ld a,(scr_cy)
	ld b,VIEW_ROWS
.lp:	cp MAP_H
	ret nc
	push af
	push bc
	ld c,a
	ld a,(top_row)
	cp c
	ld a,0
	jr nz,.s
	ld a,(top_shift)
.s:	ld (dc_shift),a
	ld a,c
	call char_addr
	ld a,(ix+0)
	call draw_char
	pop bc
	pop af
	inc a
	djnz .lp
	ret

; In: A = Y, (ca_x) = X
; Out: DE = screen address (line 0), IX = map pointer, C = half*2
char_addr:
	ld l,a
	ld h,0
	add hl,hl
	add hl,hl
	add hl,hl
	ld d,h
	ld e,l
	add hl,hl
	add hl,hl
	add hl,de			; 40Y
	push hl
	ld a,(ca_x)
	ld e,a
	ld d,0
	add hl,de			; ring word
	add hl,hl
	ld a,h
	and 7
	or #C0
	ld h,a
	ex de,hl			; DE = screen
	pop hl
	add hl,hl			; 80Y
	ld a,(ca_x)
	ld c,a
	srl c
	ld b,0
	add hl,bc
	ld bc,map_data
	add hl,bc
	push hl
	pop ix
	ld a,(ca_x)
	and 1
	add a,a
	ld c,a
	ret

; Draw one char (2 bytes wide) of a tile: tile rasters dc_shift..7 go to
; screen lines 0..7-dc_shift.
; In: A = tile, C = half*2, DE = screen address. DE preserved.
; Destroys: A, B, HL
draw_char:
	push de
	ld l,a
	rrca
	rrca
	rrca
	and #1F
	add a,hi(tile_data)
	ld h,a
	ld a,l
	and 7
	rrca
	rrca
	rrca
	add a,c
	ld l,a
	ld a,(dc_shift)
	ld b,a
	add a,a
	add a,a
	add a,l
	ld l,a
	ld a,8
	sub b
	ld b,a
.lp:	ld a,(hl)
	ld (de),a
	inc l
	inc e
	ld a,(hl)
	ld (de),a
	dec e
	inc l
	inc l
	inc l
	ld a,d
	add a,8
	ld d,a
	djnz .lp
	pop de
	ret

scr_sx:		db 0
scr_sy:		dw 0
scr_cx:		db 0
scr_cy:		db 0
scr_fy:		db 0
ca_x:		db 0
dc_shift:	db 0
top_row:	db 255
top_shift:	db 0
pending_col:	db 255		; incoming column to draw at the start of B
