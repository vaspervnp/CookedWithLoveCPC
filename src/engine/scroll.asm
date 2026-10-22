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
;
; The map is made of 16x16 metatiles (tools/maps2asm.py): map_data holds
; MAP_MW x MAP_H/2 metatile indices, meta_data 4 aligned planes of 256 bytes,
; plane k = tile of quadrant k (2*(tile row & 1) + (tile column & 1)).

MAP_W		equ 80		; tiles (8x8)
MAP_H		equ 84
MAP_MW		equ MAP_W/2	; metatiles (2x2 tiles) per map row
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
BS_DREW		equ 3		; buffer_sync drew tiles (stamps: sprite.asm)

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
	ld a,(scr_cx)			; new tiles to draw? (for the stamps)
	cp (ix+BS_CX)
	jr nz,.dr
	ld a,(scr_cy)
	cp (ix+BS_CY)
	jr z,.nd
.dr:	ld (ix+BS_DREW),1
.nd:

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

.full:	ld (ix+BS_DREW),1
	ld a,(scr_cx)
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
; copy_top only when the top row of this buffer can differ from what its top
; buffer holds: scroll moved since this buffer was last built, or a sprite is
; or was (last time) in the partial top row.
copy_top_if:
	ld a,(back)
	ld e,a
	ld d,0
	ld hl,tc_hit
	add hl,de
	ld a,(top_hit)
	ld c,(hl)			; last time's flag for this buffer
	ld (hl),a
	or c
	ld b,a				; B != 0: a sprite there
	ld hl,tc_sx
	add hl,de
	ld a,(scr_sx)
	cp (hl)
	ld (hl),a
	jr nz,copy_top
	ld hl,tc_sy
	add hl,de
	add hl,de
	ld a,(scr_sy)
	cp (hl)
	ld (hl),a
	inc hl
	jr nz,.sy1
	ld a,(scr_sy+1)
	cp (hl)
	ld (hl),a
	jr nz,copy_top
	ld a,b
	or a
	ret z
	jr copy_top
.sy1:	ld a,(scr_sy+1)
	ld (hl),a
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
	call ldi_c
	ld a,(top_n1)
	cp 80
	jr z,.next
	ld a,h				; wrap to block start
	sub 8
	ld h,a
	ld a,(top_n1)
	neg
	add a,80
	ld c,a
	call ldi_c
.next:	pop bc
	inc c
	inc b
	ld a,b
	cp 8
	jr nz,.line
	ret

; C (1..80) bytes HL -> DE with an unrolled LDI chain (16 T/byte instead
; of 21). BC is destroyed.
ldi_c:
	ld b,0
	push hl
	ld hl,ldi80_end
	or a
	sbc hl,bc
	sbc hl,bc
	ld (.c+1),hl
	pop hl
.c:	jp 0
ldi80:	repeat 80
	ldi
	rend
ldi80_end:
	ret

tc_hit:		db 0,0		; per buffer: a sprite was in the partial top row
tc_sx:		db #FF,#FF	; per buffer: scroll at the last copy_top
tc_sy:		dw #FFFF,#FFFF

; NZ if buffer_sync drew tiles into the back buffer since the last call.
buffer_drew:
	ld a,(back)
	add a,a
	add a,a
	ld hl,buf_state+BS_DREW
	add a,l
	ld l,a
	ld a,h
	adc a,0
	ld h,a
	ld a,(hl)
	ld (hl),0
	or a
	ret

; Redraw the tiles under a figure (32 x 52 from x = DE, y = BC, map
; pixels/lines) in the back buffer, inside the view. Maps bank 5.
redraw_tiles:
	push bc
	RAM RAM_C5			; (uses BC)
	pop bc
	srl d				; char columns x/4 .. (x+31)/4
	rr e
	srl d
	rr e
	ld a,e
	ld (rt_x0),a
	srl b				; char rows y/8 .. (y+51)/8
	rr c
	srl b
	rr c
	srl b
	rr c
	ld a,c
	ld (rt_y),a
	ld a,(scr_cy)			; rows: from max(y0, cy)
	ld d,a
	ld a,c
	cp d
	jr nc,.y0
	ld a,d
.y0:	ld (rt_y),a
	ld a,c				; to min(y0+7, cy+21, map)
	add a,7
	ld e,a
	ld a,d
	add a,VIEW_ROWS-1
	cp e
	jr nc,.y1
	ld e,a
.y1:	ld a,e
	cp MAP_H
	jr c,.y2
	ld e,MAP_H-1
.y2:	ld a,e
	ld (rt_y1),a
.row:	ld a,(rt_y)
	ld b,a
	ld a,(rt_y1)
	cp b
	ret c
	ld a,(rt_x0)
	ld c,a
	ld b,9				; 9 char columns
.col:	push bc
	ld a,(scr_cx)			; inside the view's columns?
	ld e,a
	ld a,c
	sub e
	jr c,.cn
	cp VIEW_CW
	jr nc,.cn
	ld a,c
	cp MAP_CW
	jr nc,.cn
	ld (ca_x),a
	ld a,(rt_y)
	call char_addr
	call map_char
.cn:	pop bc
	inc c
	djnz .col
	ld hl,rt_y
	inc (hl)
	jr .row

rt_x0:	db 0
rt_y:	db 0
rt_y1:	db 0

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
	call map_char
	pop bc
	ld a,c				; next char: other half of the tile,
	xor 2
	ld c,a
	jr nz,.same
	ld a,(ca_plane)			; next tile: other quadrant column,
	xor 1
	ld (ca_plane),a
	rra
	jr c,.same
	inc ix				; next metatile
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
.lp:	call map_char
	ld a,(ca_plane)			; next tile row: other quadrant row,
	xor 2
	ld (ca_plane),a
	and 2
	jr nz,.sm
	push bc				; next metatile row
	ld bc,MAP_MW
	add ix,bc
	pop bc
.sm:	ld a,e				; next row: +80 bytes, wrap in the 2K block
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
.nc:	ld hl,dc_rows
	dec (hl)
	jr nz,.lp
	ret

; In: A = Y, (ca_x) = X
; Out: DE = screen address (line 0), IX = metatile pointer, ca_plane =
; plane of the tile quadrant, C = half*2
char_addr:
	ld b,a				; plane: (Y & 1)*2 + (X >> 1 & 1)
	and 1
	add a,a
	ld c,a
	ld a,(ca_x)
	rra
	and 1
	or c
	add a,hi(meta_data)
	ld (ca_plane),a
	ld a,b
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
	push de
	ld a,b				; metatile: map + (Y >> 1)*40 + (X >> 2)
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
	ld a,(ca_x)
	rra
	rra
	and #3F
	ld e,a
	ld d,0
	add hl,de
	ld de,map_data
	add hl,de
	push hl
	pop ix
	pop de
	ld a,(ca_x)
	and 1
	add a,a
	ld c,a
	ret

; Draw the char of the metatile at IX, quadrant plane (ca_plane), half C.
; Called with RAM_C5 (the map); the tiles of the HUD page: RAM_C0 for the
; drawing (C is kept: out (c),a).
map_char:
	ld l,(ix+0)
	ld a,(ca_plane)
	ld h,a
	ld a,(hl)
	cp TILE_SPILL
	jr nc,draw_char			; (in bank 5)
	ld l,a
	ld b,GA_PORT
	ld a,RAM_C0
	out (c),a
	ld a,l
	call draw_char
	ld b,GA_PORT
	ld a,RAM_C5
	out (c),a
	ret

; Tiles (tools/maps2asm.py tile_number): tile t < TILE_SPILL is in the free
; end of a HUD page set (bytes TILE_LO.. of sets 1-3, 3 tiles of 32: the top
; buffer ends at 399, the next set's phase-1 HUD starts at its 511; set 0's
; bytes 400.. are B_MA, the black row below the playfield): t = line*16 +
; set*4 + j (j < 3), at &4000 + line*&800 + set*512 + TILE_LO + 32 j. The
; others in bank 5: tiles_b5 + 32 (t - TILE_SPILL). Placed by tiles_place
; at the boot.
TILE_LO		equ 400		; (the low byte stays below 256 for 3 tiles)
TILE_SPILL	equ 128
TILE_HUD	equ 72		; tiles in the HUD page
	assert (TILE_LO&255)+96<=256 && TILE_LO>=400 && TILE_LO+96<=511

; Draw one char (2 bytes x 8 lines) of a tile. Needs RAM_C0 (HUD page
; tiles) or RAM_C5 (the others).
; In: A = tile, C = half*2, DE = screen address. Out: DE preserved.
; Destroys: A, B, HL
draw_char:
	cp TILE_SPILL
	jr nc,.sp
	ld l,a				; H = &40 + TILE_LO/256 + line*8 + set*2
	srl a
	and #7E
	add a,#40+(TILE_LO>>8)
	ld h,a
	ld a,l				; L = TILE_LO + 32 j + half*2
	and 3
	rrca
	rrca
	rrca
	add a,TILE_LO&255
	add a,c
	ld l,a
.go:	ld b,8
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
.sp:	sub TILE_SPILL			; in bank 5 (aligned to 32)
	ld l,a
	ld h,0
	add hl,hl
	add hl,hl
	add hl,hl
	add hl,hl
	add hl,hl
	ld a,l
	add a,c
	add a,tiles_b5&255
	ld l,a
	ld a,h
	adc a,tiles_b5>>8
	ld h,a
	jr .go

scr_sx:		db 0
scr_sy:		dw 0
scr_cx:		db 0
scr_cy:		db 0
scr_fy:		db 0
scr_base:	dw 0
scr_page:	db #80		; high byte of the back buffer (&80 / &C0)
back:		db 0		; back buffer 0/1
buf_state:	ds 8,0		; per buffer: BS_CX, BS_CY, BS_OK, BS_DREW
ca_x:		db 0
ca_plane:	db 0
dc_y0:		db 0
dc_rows:	db 0
top_dst:	dw 0		; byte offset of the top buffer in the &4000 page
top_off:	dw 0
top_n1:		db 0
