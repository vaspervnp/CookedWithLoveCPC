; Scrolling playfield: tile map -> two 1024-word screen rings (double buffer).
;
; Map char (X,Y) (X = 4-pixel column, Y = 8-line row) lives at ring word
; (Y*40 + X) & 1023 in every 2K block of a screen page, so the view (40 x 22
; chars) is always contiguous from word base = cy*40 + cx. Each buffer
; remembers which view its ring holds (buf_cx/buf_cy) and buffer_sync only
; draws the columns/rows that changed since that buffer was last drawn.
;
; Scroll position (camera): sx in 2-pixel steps (0..MAX_SX), sy in lines.
;   cx = (sx+1) >> 1, phase = sx & 1 (R3 = R3_ALT moves the picture 2 pixels
;   right, so odd positions show the next char column shifted right)
;   cy = sy >> 3, fy = sy & 7
;
; Fine vertical scroll (see crtc.asm): the top 8-fy lines of the playfield
; are the R5 lines at the end of frame H, which show the 40 words right after
; the HUD. Rasters fy..7 of ring row cy are copied there (copy_top). Frame A
; shows ring rows cy+1..cy+20 and, as its R5 lines, rasters 0..fy-1 of row
; cy+21.
;
; Drawing a frame (see main.asm): restore sprites, buffer_sync, draw sprites,
; copy_top, scroll_build_state. Tiles and map are in bank 5 (RAM_C5 while
; drawing), the HUD sets in the base &4000 page (RAM_C0 for copy_top).

MAP_W		equ 80		; tiles (8x8)
MAP_H		equ 84
MAP_CW		equ MAP_W*2	; chars (4x8)
VIEW_CW		equ 40
VIEW_ROWS	equ PF_ROWS+1	; rows kept valid in the ring (cy..cy+21)
MAX_SX		equ (MAP_CW-VIEW_CW)*2
MAX_SY		equ (MAP_H-PF_ROWS)*8

; HUD sets in the base &4000 page, one per (R3 phase, buffer): set s at word
; s*256 holds the HUD (160 words) followed by the top buffer (40 words). The
; HUD of phase 1 sets is drawn shifted by one byte so it stays still.
HUD_WORDS	equ HUD_ROWS*40

; ---------------------------------------------------------------------------
; Set an absolute camera position; both buffers will be redrawn.
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
	xor a
	ld (buf_state+BS_OK),a
	ld (buf_state+4+BS_OK),a
	ret

; Camera steps (no drawing; buffer_sync catches up).
scroll_right:
	ld a,(scr_sx)
	cp MAX_SX
	ret nc
	inc a
	ld (scr_sx),a
	inc a
	srl a
	ld (scr_cx),a
	ret

scroll_left:
	ld a,(scr_sx)
	or a
	ret z
	dec a
	ld (scr_sx),a
	inc a
	srl a
	ld (scr_cx),a
	ret

scroll_down:
	ld hl,(scr_sy)
	ld de,MAX_SY
	or a
	sbc hl,de
	ret nc
	ld hl,(scr_sy)
	inc hl
	jr scroll_sety

scroll_up:
	ld hl,(scr_sy)
	ld a,h
	or l
	ret z
	dec hl
scroll_sety:
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
	ret

; ---------------------------------------------------------------------------
; Select the buffer to draw (A = 0/1).
scroll_select:
	ld (back),a
	or a
	ld a,#80
	jr z,.p
	ld a,#C0
.p:	ld (scr_page),a
	ret

; Bring the back buffer's ring up to the camera view. Needs RAM_C5.
BS_CX		equ 0
BS_CY		equ 1
BS_OK		equ 2

buffer_sync:
	ld a,(back)
	add a,a
	add a,a
	ld e,a
	ld d,0
	ld ix,buf_state
	add ix,de
	ld a,(ix+BS_OK)
	or a
	jp z,.full

	; columns, for the rows the ring holds now (bcy..bcy+21)
	ld a,(ix+BS_CY)
	ld (dc_y0),a
	ld a,(scr_cx)
	sub (ix+BS_CX)			; d = cx - bcx
	jr z,.rows
	jr c,.left
	cp VIEW_CW
	jp nc,.full
	ld b,a				; X = bcx+40 .. cx+39
	ld a,(ix+BS_CX)
	add a,VIEW_CW
	jr .cols
.left:	neg
	cp VIEW_CW
	jp nc,.full
	ld b,a				; X = cx .. bcx-1
	ld a,(scr_cx)
.cols:	push af
	push bc
	push ix
	call draw_col
	pop ix
	pop bc
	pop af
	inc a
	djnz .cols
	ld a,(scr_cx)
	ld (ix+BS_CX),a

.rows:	ld a,(scr_cy)
	sub (ix+BS_CY)			; e = cy - bcy
	jr z,.done
	jr c,.up
	cp VIEW_ROWS
	jr nc,.full
	ld b,a				; Y = bcy+22 .. cy+21
	ld a,(ix+BS_CY)
	add a,VIEW_ROWS
	jr .rws
.up:	neg
	cp VIEW_ROWS
	jr nc,.full
	ld b,a				; Y = cy .. bcy-1
	ld a,(scr_cy)
.rws:	push af
	push bc
	push ix
	call draw_row
	pop ix
	pop bc
	pop af
	inc a
	djnz .rws
.done:	ld a,(scr_cy)
	ld (ix+BS_CY),a
	ret

.full:	ld a,(scr_cx)
	ld (ix+BS_CX),a
	ld a,(scr_cy)
	ld (ix+BS_CY),a
	ld (ix+BS_OK),1
	ld b,VIEW_ROWS
.frow:	push af
	push bc
	push ix
	call draw_row
	pop ix
	pop bc
	pop af
	inc a
	djnz .frow
	ret

; Build nxt_state for displaying the back buffer (not flagged yet).
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
	ld a,h				; R12: page bits from the buffer
	and 3
	ld h,a
	ld a,(scr_page)
	rrca
	rrca
	and #30
	or h
	ld h,a
	ld (ix+ST_AMA),l
	ld (ix+ST_AMA+1),h

	ld a,(scr_fy)
	ld (ix+ST_AR5),a
	ld b,a
	ld a,8
	sub b
	ld (ix+ST_HR5),a

	; HUD set s = phase*2 + back, R3 of the phase
	ld a,(scr_sx)
	and 1
	ld c,R3_STD
	jr z,.ph
	ld c,R3_ALT
.ph:	ld (ix+ST_R3),c
	add a,a
	ld b,a
	ld a,(back)
	or b				; s
	ld (ix+ST_HMA),0		; MA = &1000 + s*256
	ld b,a
	or #10
	ld (ix+ST_HMA+1),a
	ld a,b				; top buffer byte offset = s*512 + 320
	add a,a
	ld h,a
	ld l,0
	ld de,HUD_WORDS*2
	add hl,de
	ld (top_dst),hl
	ret

; Copy rasters fy..7 of the back ring's row cy (scr_base, set by
; scroll_build_state) into its top buffer. Needs RAM_C0.
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
	ld h,a
	ld a,(scr_page)
	add a,h
	ld h,a
	ld l,0
	ld de,(top_off)
	add hl,de			; src
	ld a,c
	add a,a
	add a,a
	add a,a
	add a,#40
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

; ---------------------------------------------------------------------------
; Draw map char row Y (A) for X = cx..cx+39. Needs RAM_C5.
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
	ld d,a
	ld a,(scr_page)
	or d
	ld d,a
.nw:	djnz .lp
	ret

; Draw map char column X (A) for VIEW_ROWS rows from dc_y0 (stops at the map
; bottom). Needs RAM_C5.
draw_col:
	ld (ca_x),a
	ld a,(dc_y0)
	ld b,a
	ld a,MAP_H
	sub b				; rows left in the map
	ret c
	ret z
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
	ld d,a
	ld a,(scr_page)
	or d
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
	ld h,a
	ld a,(scr_page)
	or h
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
scr_page:	db #80		; high byte of the back buffer (&80 / &C0)
back:		db 0		; back buffer 0/1
buf_state:	ds 8,0		; per buffer: BS_CX, BS_CY, BS_OK, pad
ca_x:		db 0
dc_y0:		db 0
dc_rows:	db 0
top_dst:	dw 0		; byte offset of the top buffer in the &4000 page
top_off:	dw 0
top_n1:		db 0
