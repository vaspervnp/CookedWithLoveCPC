; Masked sprites (Mode 0, pen 0 transparent) drawn into the back buffer's
; screen ring, with save-under per buffer.
;
; Sprites live in map coordinates: map byte column bx (2 pixels), map line ly.
; In a ring the byte (bx, ly) is at
;   page + (ly&7)*&800 + ((2*((ly>>3)*40 + (bx>>1)) + (bx&1)) & 2047)
; so along a line the address is linear modulo 2048 (wraps at the end of the
; 2K block). Drawing is clipped to the visible view (bytes 2cx..2cx+79, lines
; sy..sy+167), which also keeps it inside the rows the ring holds.
;
; Frame data (tools/sprite2asm.py), 48 lines of: db start, count, bytes...
; Sprite graphics are in bank 4 (RAM_C4), save-under records in base RAM
; (SAVE_AREA0/1, one per buffer). A record is a list of segments
; [count][address][bytes], ended by count 0. Each line saves and then draws
; only the bytes it covers.
;
; Per frame: sprites_restore (erase what this buffer showed, in reverse
; order), then after buffer_sync: sprites_draw (list sorted by y).

SPR_W		equ 16		; bytes
SPR_H		equ 48		; lines
SPR_MAX		equ 8
SAVE_AREA0	equ #2000	; save-under records, base RAM (4K per buffer)
SAVE_AREA1	equ #3000

; sprite list entry
SE_FRAME	equ 0		; frame data pointer (bank 4)
SE_X		equ 2		; left edge, map pixels (even)
SE_Y		equ 4		; top line
SE_SIZE		equ 6

; Clear the sprite list for this frame.
sprites_clear:
	xor a
	ld (spr_n),a
	ret

; Add a sprite. In: HL = frame pointer, DE = x, BC = y.
sprites_add:
	ld a,(spr_n)
	cp SPR_MAX
	ret nc
	push hl
	ld l,a
	inc a
	ld (spr_n),a
	ld h,0
	add hl,hl
	ld a,l
	add a,l
	add a,l				; index*6
	ld l,a
	push de
	ld de,spr_list
	add hl,de
	pop de
	ex (sp),hl			; HL = frame, (sp) = entry
	ex de,hl			; DE = frame, HL = x
	ex (sp),hl			; HL = entry, (sp) = x
	ld (hl),e
	inc hl
	ld (hl),d
	inc hl
	pop de				; x
	ld (hl),e
	inc hl
	ld (hl),d
	inc hl
	ld (hl),c
	inc hl
	ld (hl),b
	ret

; ---------------------------------------------------------------------------
; Erase the sprites drawn into the back buffer last time.
sprites_restore:
	call save_table			; HL = pointer table, A = count
	or a
	ret z
	ld b,a
	add a,a				; HL = &table[count]
	ld e,a
	ld d,0
	add hl,de
.rec:	dec hl
	ld d,(hl)
	dec hl
	ld e,(hl)
	push hl
	push bc
	ex de,hl
.seg:	ld a,(hl)
	or a
	jr z,.end
	inc hl
	ld c,a
	ld b,0
	ld e,(hl)
	inc hl
	ld d,(hl)
	inc hl
	ldir
	jr .seg
.end:	pop bc
	pop hl
	djnz .rec
	call save_count_ptr
	ld (hl),0
	ret

; HL = save pointer table of the back buffer, A = its count.
save_table:
	call save_count_ptr
	ld a,(hl)
	push af
	ld a,(back)
	ld hl,save_ptrs
	or a
	jr z,.b0
	ld hl,save_ptrs+SPR_MAX*2
.b0:	pop af
	ret

save_count_ptr:
	ld hl,save_n
	ld a,(back)
	add a,l
	ld l,a
	ret nc
	inc h
	ret

; ---------------------------------------------------------------------------
; Draw the sprite list into the back buffer (sorted by y, saving under).
sprites_draw:
	ld a,(back)			; save area of this buffer
	or a
	ld hl,SAVE_AREA0
	jr z,.s0
	ld hl,SAVE_AREA1
.s0:	ld (save_ptr),hl
	; order: indices sorted by SE_Y (insertion sort, n <= 8)
	ld a,(spr_n)
	or a
	ret z
	ld b,a
	ld c,0
	ld hl,spr_order
.init:	ld (hl),c
	inc hl
	inc c
	djnz .init
	ld a,(spr_n)
	cp 2
	jr c,.sorted
	ld c,1				; i
.outer:	ld b,c				; j = i
.inner:	ld a,b
	or a
	jr z,.next
	push bc
	ld hl,spr_order
	ld e,b
	ld d,0
	add hl,de
	ld a,(hl)			; order[j]
	dec hl
	ld c,(hl)			; order[j-1]
	push hl
	call spr_y			; DE = y of entry A
	push de
	ld a,c
	call spr_y
	pop hl				; y[j]
	ex de,hl			; HL = y[j-1], DE = y[j]
	or a
	sbc hl,de			; y[j-1] - y[j]
	pop hl
	jr c,.ok
	jr z,.ok
	ld a,(hl)			; swap
	inc hl
	ld e,(hl)
	ld (hl),a
	dec hl
	ld (hl),e
	pop bc
	dec b
	jr .inner
.ok:	pop bc
.next:	inc c
	ld a,(spr_n)
	cp c
	jr nz,.outer
.sorted:
	ld a,(spr_n)
	ld b,a
	ld hl,spr_order
.draw:	push bc
	push hl
	ld a,(hl)
	call spr_entry			; IX = entry
	call sprite_one
	pop hl
	pop bc
	inc hl
	djnz .draw
	RAM RAM_C0
	ret

; A = index -> IX = entry
spr_entry:
	ld l,a
	ld h,0
	add hl,hl
	ld e,l
	ld d,h
	add hl,hl
	add hl,de			; *6
	ld de,spr_list
	add hl,de
	push hl
	pop ix
	ret

; A = index -> DE = y
spr_y:
	push hl
	call spr_entry
	ld e,(ix+SE_Y)
	ld d,(ix+SE_Y+1)
	pop hl
	ret

; ---------------------------------------------------------------------------
; Clip, save under and draw the sprite at IX.
sprite_one:
	; bx = x / 2
	ld l,(ix+SE_X)
	ld h,(ix+SE_X+1)
	srl h
	rr l
	ld (sp_bx),hl
	; left = 2cx - bx, clipL = max(0, left), invisible if left >= 16
	ld a,(scr_cx)
	add a,a
	ld e,a
	ld d,0
	ex de,hl			; HL = 2cx, DE = bx
	ld (sp_2cx),hl
	or a
	sbc hl,de			; 2cx - bx
	jr c,.l0			; negative -> clipL = 0
	ld a,h
	or a
	ret nz
	ld a,l
	cp SPR_W
	ret nc
	jr .l1
.l0:	xor a
.l1:	ld (sp_cl),a
	ld hl,(sp_2cx)
	ld bc,VIEW_CW*2
	add hl,bc			; right edge of the view
	or a
	sbc hl,de			; bytes from bx to the right edge
	ret c
	ret z
	ld a,h
	or a
	ld a,SPR_W
	jr nz,.r1
	ld a,l
	cp SPR_W
	jr c,.r1
	ld a,SPR_W
.r1:	ld (sp_cr),a

	; lines: ly0 = max(y, sy), ly1 = min(y+48, sy+168)
	ld l,(ix+SE_Y)
	ld h,(ix+SE_Y+1)
	ld de,(scr_sy)
	push hl
	or a
	sbc hl,de
	pop hl
	jr nc,.y0			; y >= sy
	ex de,hl			; ly0 = sy
.y0:	ld (sp_ly0),hl
	ld l,(ix+SE_Y)
	ld h,(ix+SE_Y+1)
	ld bc,SPR_H
	add hl,bc			; y + 48
	ex de,hl
	ld hl,(scr_sy)
	ld bc,PF_ROWS*8
	add hl,bc			; sy + 168
	push hl
	or a
	sbc hl,de
	pop hl
	jr c,.y1			; sy+168 < y+48
	ex de,hl
.y1:	ld de,(sp_ly0)			; HL = ly1
	or a
	sbc hl,de			; lines to draw
	ret c
	ret z
	ld a,l
	ld (sp_lines),a
	ld l,(ix+SE_Y)
	ld h,(ix+SE_Y+1)
	ex de,hl
	or a
	sbc hl,de			; ly0 - y = lines skipped at the top
	ld a,l
	ld (sp_skip),a

	; row offset of ly0: (2*((Y*40 + bx>>1) & 1023) + (bx&1)) & 2047
	ld hl,(sp_ly0)
	ld a,l
	and 7
	ld (sp_r0),a
	srl h
	rr l
	srl h
	rr l
	srl h
	rr l				; Y
	add hl,hl
	add hl,hl
	add hl,hl
	ld d,h
	ld e,l
	add hl,hl
	add hl,hl
	add hl,de			; 40Y
	ld de,(sp_bx)
	srl d
	rr e
	add hl,de
	add hl,hl
	ld a,(sp_bx)
	and 1
	or l
	ld l,a
	ld a,h
	and 7
	ld h,a
	ld (sp_row0),hl

	ld a,(sp_cr)			; clipped width
	ld b,a
	ld a,(sp_cl)
	ld c,a
	ld a,b
	sub c
	ld (sp_w),a
	ld a,c				; full width? (fast rows possible)
	or a
	jr nz,.part
	ld a,b
	cp SPR_W
	jr nz,.part
	ld a,1
	jr .fw
.part:	xor a
.fw:	ld (sp_full),a

	; --- per line: save the bytes it covers, then draw it ---
	call save_count_ptr		; record pointer into the table
	ld a,(hl)
	inc (hl)
	push af
	call save_table
	pop af
	add a,a
	ld e,a
	ld d,0
	add hl,de
	ld de,(save_ptr)
	ld (hl),e
	inc hl
	ld (hl),d
	RAM RAM_C4			; sprite graphics
	ld l,(ix+SE_FRAME)
	ld h,(ix+SE_FRAME+1)
	ld a,(sp_skip)			; skip clipped lines at the top
	or a
	jr z,.dr0
	ld b,a
.skip:	inc hl
	ld a,(hl)			; nl+no+nr
	inc hl
	add a,(hl)
	inc hl
	add a,(hl)
	inc hl
	add a,l
	ld l,a
	jr nc,.sk1
	inc h
.sk1:	djnz .skip
.dr0:	ld (sp_data),hl
	call rows_start
.drow:	call row_setup
.dline:	ld a,(rs_fast)
	or a
	jr z,.slow
	; fast: whole line inside the view, no wrap
	ld hl,(sp_data)
	ld e,(hl)			; start
	inc hl
	ld a,(hl)
	ld (f_nl),a
	inc hl
	ld b,(hl)
	inc hl
	ld c,(hl)
	inc hl
	ld (sp_data),hl
	ld (f_no),bc			; f_no = no, f_nr = nr
	add a,b
	add a,c				; total
	jr z,.dnext
	ld c,a
	ld hl,(rs_addr)			; screen = line + start
	ld d,0
	add hl,de
	ex de,hl			; DE = screen
	ld hl,(save_ptr)		; record segment [total][address][bytes]
	ld (hl),c
	inc hl
	ld (hl),e
	inc hl
	ld (hl),d
	inc hl
	ex de,hl			; HL = screen, DE = save
	push hl
	ld b,0
	ldir
	ld (save_ptr),de
	pop hl
	ld de,(sp_data)			; draw
	ld a,(f_nl)
	or a
	call nz,mask_loop
	ld a,(f_no)
	or a
	jr z,.d2
	ld c,a
	ld b,0
	ex de,hl
	ldir
	ex de,hl
.d2:	ld a,(f_nr)
	or a
	call nz,mask_loop
	ld (sp_data),de
	jr .dnext
.slow:	call line_clipped
.dnext:	call line_next
	jr nz,.dline
	call row_next
	jr nz,.drow
	ld hl,(save_ptr)		; end of the record
	ld (hl),0
	inc hl
	ld (save_ptr),hl
	ret

; A masked bytes from DE to HL. Destroys A, BC, IXL.
mask_loop:
	ld ixl,a
	ld b,hi(mask_table)
.lp:	ld a,(de)
	ld c,a
	ld a,(bc)
	and (hl)
	or c
	ld (hl),a
	inc de
	inc hl
	dec ixl
	jr nz,.lp
	ret

; --- iteration over the visible lines, row by row ---
rows_start:
	ld a,(sp_r0)
	ld (sp_r),a
	ld hl,(sp_row0)
	ld (sp_row),hl
	ld a,(sp_lines)
	ld (sp_left),a
	ret

; Set up the current row: rs_addr = address of byte clipL on the current
; line, rs_wrap = bytes from there to the block end (capped 255), rs_fast,
; rs_n = lines of this row still to draw.
row_setup:
	ld a,(sp_r)
	ld b,a
	ld a,8
	sub b
	ld b,a
	ld a,(sp_left)
	cp b
	jr c,.n
	ld a,b
.n:	ld (rs_n),a
	ld hl,(sp_row)
	ld a,(sp_cl)
	add a,l
	ld l,a
	jr nc,.c
	inc h
.c:	ld a,h
	and 7
	ld h,a				; offset of byte clipL in the block
	ld a,8				; bytes to wrap = 2048 - offset
	sub h
	ld d,a
	xor a
	sub l
	ld e,a
	jr nc,.w
	dec d
.w:	ld a,d
	or a
	ld a,e
	jr z,.cap
	ld a,255
.cap:	ld (rs_wrap),a
	ld b,a				; fast = full width and no wrap
	ld a,(sp_full)
	or a
	jr z,.nf
	ld a,b
	cp SPR_W
	ld a,0
	jr c,.nf
	inc a
.nf:	ld (rs_fast),a
	ld a,(sp_r)
	add a,a
	add a,a
	add a,a
	add a,h
	ld h,a
	ld a,(scr_page)
	add a,h
	ld h,a
	ld (rs_addr),hl
	ret

; Next line inside the row: NZ while the row has lines left.
line_next:
	ld hl,rs_addr+1			; next raster: +&800
	ld a,(hl)
	add a,8
	ld (hl),a
	ld hl,sp_r
	inc (hl)
	ld hl,sp_left
	dec (hl)
	ld hl,rs_n
	dec (hl)
	ret

; Next row: NZ while lines are left.
row_next:
	xor a
	ld (sp_r),a
	ld hl,(sp_row)			; +80 bytes mod 2048
	ld de,80
	add hl,de
	ld a,h
	and 7
	ld h,a
	ld (sp_row),hl
	ld a,(sp_left)
	or a
	ret

; Save and draw one sprite line byte by byte, with clipping and block wrap
; (rows at the view edges or across the end of a 2K block). Each visible
; byte is saved as its own segment.
line_clipped:
	ld hl,(sp_data)
	ld a,(hl)			; start
	ld (dc_j),a
	inc hl
	ld a,(hl)
	inc hl
	add a,(hl)
	inc hl
	add a,(hl)
	inc hl
	ld (dc_cnt),a			; bytes in the line
	or a
	jr z,.end
	ex de,hl			; DE = bytes
.lp:	ld a,(dc_j)			; j inside [clipL, clipR)?
	ld c,a
	ld a,(sp_cl)
	ld b,a
	ld a,c
	sub b				; j - clipL
	jr c,.skip
	ld b,a
	ld a,(sp_w)
	dec a
	cp b
	jr c,.skip
	ld a,(rs_wrap)			; address = rs_addr + (j - clipL), wrapped
	ld c,a
	ld a,b
	ld hl,(rs_addr)
	cp c
	jr c,.nw
	ld c,a				; past the block end: -2048
	ld a,h
	sub 8
	ld h,a
	ld a,c
.nw:	add a,l
	ld l,a
	jr nc,.nc
	inc h
.nc:	push de				; save [1][address][byte]
	ex de,hl
	ld hl,(save_ptr)
	ld (hl),1
	inc hl
	ld (hl),e
	inc hl
	ld (hl),d
	inc hl
	ld a,(de)
	ld (hl),a
	inc hl
	ld (save_ptr),hl
	ex de,hl			; HL = screen
	pop de
	ld b,hi(mask_table)
	ld a,(de)
	ld c,a
	ld a,(bc)
	and (hl)
	or c
	ld (hl),a
.skip:	inc de
	ld hl,dc_j
	inc (hl)
	ld hl,dc_cnt
	dec (hl)
	jr nz,.lp
	ex de,hl
.end:	ld (sp_data),hl
	ret

; mask_table[b]: bits of the background to keep (pixels with pen 0 in b).
	align 256
mask_table:
	repeat 256,mb
	db (((mb-1)&#AA)==0)*#AA | (((mb-1)&#55)==0)*#55
	rend

spr_n:		db 0
spr_list:	ds SPR_MAX*SE_SIZE,0
spr_order:	ds SPR_MAX,0
save_n:		ds 2,0
save_ptrs:	ds SPR_MAX*2*2,0
save_ptr:	dw 0
sp_bx:		dw 0
sp_2cx:		dw 0
sp_cl:		db 0
sp_cr:		db 0
sp_ly0:		dw 0
sp_lines:	db 0
sp_skip:	db 0
sp_r0:		db 0
sp_row0:	dw 0
sp_r:		db 0
sp_row:		dw 0
sp_left:	db 0
sp_data:	dw 0
sp_w:		db 0
sp_full:	db 0
sp_nr:		db 0
f_nl:		db 0
f_no:		db 0
f_nr:		db 0
sp_st:		db 0
rs_addr:	dw 0
rs_wrap:	db 0
rs_fast:	db 0
rs_n:		db 0
dc_j:		db 0
dc_cnt:		db 0
