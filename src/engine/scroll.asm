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
; Fine vertical scroll (see crtc.asm): the top 8-fy lines of the playfield
; are the R5 lines at the end of frame H, which show the 40 words right
; after the HUD. Rasters fy..7 of ring row cy are copied there (copy_top).
; Frame A shows ring rows cy+1..cy+20 and, as its R5 lines, rasters
; 0..fy-1 of row cy+21. The ring itself is never modified for scrolling.
;
; Screen memory that is visible must only change when the beam is not on it,
; so a frame update is done in this order (scroll_update):
;   1. moves: incoming rows are drawn at once (outside the visible view),
;      an incoming column is only noted (it overwrites a visible column)
;   2. build nxt_state
;   3. after the top buffer has been displayed (I2): copy_top
;   4. once the beam is low enough in A (I4): draw the column top to bottom,
;      always behind the beam
;   5. flag nxt_state; I0/I1 commit it before H is displayed again

MAP_W		equ 80		; tiles (8x8)
MAP_H		equ 84
MAP_CW		equ MAP_W*2	; chars (4x8)
VIEW_CW		equ 40
VIEW_ROWS	equ PF_ROWS+1	; rows kept valid in the ring (cy..cy+21)
MAX_SX		equ (MAP_CW-VIEW_CW)*2
MAX_SY		equ (MAP_H-PF_ROWS)*8

; HUD sets in the &8000 page (word offsets): HUD (160 words) followed by the
; top buffer (40 words). Set 1 is used for R3 phase 1, its HUD is drawn
; shifted by one byte so that it stays still on screen.
HUD_SET0	equ 0
HUD_SET1	equ 512
HUD_WORDS	equ HUD_ROWS*40

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
; Finish a frame update after the moves (steps 2-5 above).
scroll_update:
	call scroll_build_state
	xor a
	ld (sync_a),a
.a:	ld a,(sync_a)
	or a
	jr z,.a
	call copy_top
	ld a,(pending_col)
	inc a
	jr z,.ready
	xor a
	ld (sync_c),a
.c:	ld a,(sync_c)
	or a
	jr z,.c
	ld a,(pending_col)
	call draw_col
	call copy_top_col
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
	ld a,h
	and 3
	ld h,a
	ld (scr_base),hl
	ld ix,nxt_state
	ld de,40			; A starts at row cy+1
	add hl,de
	call ma_ring
	ld (ix+ST_AMA),l
	ld (ix+ST_AMA+1),h

	ld a,(scr_fy)
	ld (ix+ST_AR5),a
	ld b,a
	ld a,8
	sub b
	ld (ix+ST_HR5),a

	; horizontal phase: R3 and HUD set
	ld a,(scr_sx)
	and 1
	ld hl,#2000+HUD_SET0
	ld de,(HUD_SET0+HUD_WORDS)*2
	ld a,R3_STD
	jr z,.ph
	ld hl,#2000+HUD_SET1
	ld de,(HUD_SET1+HUD_WORDS)*2
	ld a,R3_ALT
.ph:	ld (ix+ST_R3),a
	ld (ix+ST_HMA),l
	ld (ix+ST_HMA+1),h
	ld (top_dst),de
	ret

; HL = ring word (any) -> R12/R13 value for the &C000 page.
ma_ring:
	ld a,h
	and 3
	or #30
	ld h,a
	ret

; Copy rasters fy..7 of ring row scr_base into the top buffer (top_dst in
; the &8000 page), buffer line = raster - fy. Handles the 2K block wrap.
copy_top:
	ld hl,(scr_base)
	add hl,hl
	ld (top_off),hl
	ex de,hl
	ld hl,2048
	or a
	sbc hl,de			; bytes left in block
	ld a,h
	or a
	jr nz,.full
	ld a,l
	cp 80
	jr c,.n1
.full:	ld a,80
.n1:	ld (top_n1),a
	ld a,(scr_fy)
	ld b,a				; source raster
	ld c,0				; buffer line
.line:	push bc
	ld a,b
	add a,a
	add a,a
	add a,a
	add a,#C0
	ld h,a
	ld l,0
	ld de,(top_off)
	add hl,de			; src
	ld a,c
	add a,a
	add a,a
	add a,a
	add a,#80
	ld d,a
	ld e,0
	push hl
	ld hl,(top_dst)
	add hl,de
	ex de,hl			; dst
	pop hl
	ld a,(top_n1)
	ld c,a
	ld b,0
	ldir
	cp 80
	jr z,.next
	ld a,h				; wrap to block start
	sub 8
	ld h,a
	ld a,(top_n1)
	neg
	add a,80
	ld c,a
	ld b,0
	ldir
.next:	pop bc
	inc c
	inc b
	ld a,b
	cp 8
	jr nz,.line
	ret

; Copy the column pending_col of ring row cy into the top buffer (after
; copy_top, which ran before the column was drawn).
copy_top_col:
	ld a,(scr_cx)
	ld b,a
	ld a,(pending_col)
	sub b				; column 0..39 in the view
	add a,a
	ld e,a
	ld d,0
	ld hl,(top_dst)
	add hl,de
	ld (tc_dst),hl
	ld hl,(scr_base)		; src word = base + column
	srl d
	ld a,e
	rra
	ld e,a
	add hl,de
	ld a,h
	and 3
	ld h,a
	add hl,hl
	ld (tc_src),hl
	ld a,(scr_fy)
	ld b,a				; source raster
	ld c,0				; buffer line
.line:	ld a,b
	add a,a
	add a,a
	add a,a
	add a,#C0
	ld h,a
	ld l,0
	ld de,(tc_src)
	add hl,de
	ld a,c
	add a,a
	add a,a
	add a,a
	add a,#80
	ld d,a
	ld e,0
	push hl
	ld hl,(tc_dst)
	add hl,de
	ex de,hl
	pop hl
	ld a,(hl)
	ld (de),a
	inc hl
	inc de
	ld a,(hl)
	ld (de),a
	inc c
	inc b
	ld a,b
	cp 8
	jr nz,.line
	ret

; ---------------------------------------------------------------------------
; Draw map char row Y (A) for X = cx..cx+39.
draw_row:
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

; Draw map char column X (A) for Y = cy..cy+21 (stops at the map bottom).
draw_col:
	ld (ca_x),a
	ld a,(scr_cy)
	ld b,a
	ld a,MAP_H
	sub b				; rows left in the map
	cp VIEW_ROWS
	jr c,.n
	ld a,VIEW_ROWS
.n:	ld (dc_rows),a
	ld a,b
	call char_addr			; DE = screen, IX = map, C = half*2
.lp:	ld a,(ix+0)
	call draw_char
	ld a,e				; next row: +80 bytes, wrap in the 2K block
	add a,80
	ld e,a
	jr nc,.nc
	inc d
	ld a,d
	and 7
	or #C0
	ld d,a
.nc:	push bc
	ld bc,MAP_W
	add ix,bc
	pop bc
	ld hl,dc_rows
	dec (hl)
	jr nz,.lp
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

; Draw one char (2 bytes x 8 lines) of a tile.
; In: A = tile, C = half*2, DE = screen address. Out: DE preserved.
; Destroys: A, B, HL
draw_char:
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
	ld b,8
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
	ld a,d
	sub #40
	ld d,a
	ret

scr_sx:		db 0
scr_sy:		dw 0
scr_cx:		db 0
scr_cy:		db 0
scr_fy:		db 0
scr_base:	dw 0
ca_x:		db 0
dc_rows:	db 0
pending_col:	db 255		; incoming column, drawn late in A
top_dst:	dw 0		; byte offset of the top buffer in the &8000 page
top_off:	dw 0
top_n1:		db 0
tc_src:		dw 0
tc_dst:		dw 0
