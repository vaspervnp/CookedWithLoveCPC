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
; Frames are compiled to Z80 code (tools/spritec.py): a frame is a program
; of calls, one per line, to line routines shared between frames when lines
; are identical. A line routine calls a SAVE stub (shared by lines with the
; same start/count: HL = IX + start, bytes saved with LDI), writes the bytes
; with immediate masks/values and jumps to STEP (IXH + 8; next_row, via the
; fixed vector at &0103, on a new char row). While the program runs, IX =
; screen address of the line's byte 0 and DE = save pointer. The program is
; entered at the first visible line and stopped after the last one by a RET
; written over the next call. That fast path is used when the whole sprite
; width is visible and no row crosses the end of a 2K block; otherwise
; sprite_clipped runs the same line routines on a copy of each line and
; writes back the visible bytes.
;
; A frame descriptor (base RAM) gives: code bank, program, span table
; (start, count per line), lines, lines trimmed at the top (dy). A figure
; can be one 48-line frame or parts (head, body, legs) added one under the
; other with the same depth key (sprites_add_z), so styles combine.
;
; Save-under records in base RAM (SAVE_AREA0/1, one per buffer):
;   segments [count][address][bytes] (one per line, written by the SAVE
;   stubs or the clipped path), ended by 0
;
; Per frame: sprites_restore (erase what this buffer showed, in reverse
; order), then after buffer_sync: sprites_draw (list sorted by depth).
;
; Stamps (sprites added with spr_stamp = 1: figures that stay still, such
; as sitting customers) stay in the ring: they are drawn first, under the
; others, without save-under, and only when needed: when the stamps of this
; buffer changed (the old ones are erased by redrawing their tiles) or when
; buffer_sync drew new tiles (their parts may have scrolled in). A frame
; without changes costs nothing for them.

SPR_W		equ 16		; bytes
SPR_MAX		equ 24
SAVE_AREA0	equ #2000	; save-under records, base RAM (4K per buffer)
SAVE_AREA1	equ #3000
CL_BUF		equ #1FF0	; line copy of the clipped path, below the save areas
	assert ((CL_BUF>>8)&#38)!=#38	; STEP (IXH + 8) must not reach a new char row

; sprite list entry
SE_FRAME	equ 0		; frame descriptor pointer
SE_X		equ 2		; left edge, map pixels (even)
SE_Y		equ 4		; top line
SE_Z		equ 6		; depth key (bottom line)
SE_F2		equ 8		; 2nd and 3rd part of a figure (0 = none): descriptors
SE_F3		equ 10		; whose dy counts from the figure's top line
SE_STAMP	equ 12		; 1: a stamp (see above)
SE_SIZE		equ 16
STAMP_MAX	equ 16		; (src/game/stamps.asm)

; frame descriptor (tools/spritec.py)
DS_BANK		equ 0		; RAM config of the compiled code
DS_PROG		equ 1		; program (3 bytes per line)
DS_SPAN		equ 3		; span table
DS_H		equ 5		; lines drawn (empty lines trimmed)
DS_DY		equ 6		; lines trimmed at the top

; Clear the sprite list for this frame.
sprites_clear:
	xor a
	ld (spr_n),a
	ld (clip_count),a
	ret

; Add a sprite. In: HL = frame pointer, DE = x, BC = y.
sprites_add:
	push hl				; depth = bottom line (y + dy + height)
	push de
	ld de,DS_H
	add hl,de
	ld a,(hl)
	inc hl
	add a,(hl)
	ld e,a
	ld d,0
	ld h,b
	ld l,c
	add hl,de
	ld (spr_z),hl
	pop de
	pop hl
; Same with the depth key in spr_z. For a figure in parts (head, body,
; legs), HL = first part and spr_f2/spr_f3 = the others (cleared after).
sprites_add_z:
	ld a,(spr_n)
	cp SPR_MAX
	ret nc
	push hl
	ld l,a
	inc a
	ld (spr_n),a
	ld h,0
	add hl,hl
	add hl,hl
	add hl,hl
	add hl,hl			; index*16
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
	inc hl
	ld de,(spr_z)
	ld (hl),e
	inc hl
	ld (hl),d
	inc hl
	ld de,(spr_f2)
	ld (hl),e
	inc hl
	ld (hl),d
	inc hl
	ld de,(spr_f3)
	ld (hl),e
	inc hl
	ld (hl),d
	inc hl
	ld a,(spr_stamp)
	ld (hl),a
	ld hl,0
	ld (spr_f2),hl
	ld (spr_f3),hl
	xor a
	ld (spr_stamp),a
	; insert the new index into the draw order by depth (spr_keys sorted,
	; after equal keys so the parts of a figure keep their order)
	ld a,(spr_n)
	dec a
	ld c,a				; C = new index
	ld b,a				; B = insert position j
	ld l,a
	ld h,0
	add hl,hl
	ld de,spr_keys
	add hl,de			; HL = &keys[j]
.ins:	ld a,b
	or a
	jr z,.put
	dec hl
	ld d,(hl)
	dec hl
	ld e,(hl)			; DE = keys[j-1]
	push hl
	ld hl,(spr_z)
	or a
	sbc hl,de
	pop hl
	jp p,.at			; z >= keys[j-1]: insert at j
	inc hl				; keys[j] = keys[j-1]
	inc hl
	ld (hl),e
	inc hl
	ld (hl),d
	dec hl
	dec hl
	dec hl
	push hl
	ld hl,spr_order-1		; order[j] = order[j-1]
	ld e,b
	ld d,0
	add hl,de
	ld a,(hl)
	inc hl
	ld (hl),a
	pop hl
	dec b
	jr .ins
.at:	inc hl
	inc hl
.put:	ld de,(spr_z)
	ld (hl),e
	inc hl
	ld (hl),d
	ld hl,spr_order
	ld e,b
	ld d,0
	add hl,de
	ld (hl),c
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
.chunk:	ld a,(hl)			; segment [count][address][bytes], 0 = end
	inc hl
	or a
	jr z,.end
	ld c,a
	ld b,0
	ld e,(hl)
	inc hl
	ld d,(hl)
	inc hl
	ldir
	jr .chunk
.end:	pop bc
	pop hl
	djnz .rec
	call save_count_ptr
	ld (hl),0
	ret

; New char row for the compiled line routines (via the vector at &0103):
; IX = row offset + 80 (mod 2048), raster 0. Keeps DE.
next_row:
	ld hl,(cs_row)
	ld bc,80
	add hl,bc
	ld a,h
	and 7
	ld h,a
	ld (cs_row),hl
	ld a,(scr_page)
	or h
	ld ixh,a
	ld a,l
	ld ixl,a
	ret

; Z if no visible row of the sprite crosses the end of a 2K block.
rows_nowrap:
	ld a,(sp_r0)			; rows = (r0 + lines + 7) / 8
	ld b,a
	ld a,(sp_lines)
	add a,b
	add a,7
	rrca
	rrca
	rrca
	and #1F
	ld b,a
	ld hl,(sp_row0)			; fast: last row's byte 0 = row0 + 80*(rows-1)
	ld a,b				; <= &7F0 without wrapping
	dec a
	add a,a
	ld e,a
	ld d,hi(row80)
	ld a,(de)
	add a,l
	ld c,a
	inc e
	ld a,(de)
	adc a,h
	cp 7
	jr c,.ok0
	jr nz,.lp0
	ld a,c
	cp #F1
	jr c,.ok0
.lp0:
.lp:	ld a,h				; byte 0 offset <= 2032 (&7F0)
	cp 7
	jr c,.ok
	ld a,l
	cp #F1
	jr c,.ok
	or 1
	ret
.ok:	ld de,80
	add hl,de
	ld a,h
	and 7
	ld h,a
	djnz .lp
.ok0:	xor a
	ret

; Copy A (1..16) bytes HL -> DE with an unrolled LDI chain (16 T/byte
; instead of 21 for LDIR). BC is destroyed.
ldi_n:
	neg
	add a,16
	add a,a
	ld (.j+1),a
.j:	jr $+2
	repeat 16
	ldi
	rend
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
	ld hl,(scr_sy)			; first line below the partial top row
	ld a,l
	or 7
	ld l,a
	inc hl
	ld (top_lim),hl
	xor a
	ld (top_hit),a
	call stamps_draw
	ld a,(spr_n)			; spr_order is kept sorted by sprites_add_z
	or a
	jr z,.end
	ld b,a
	ld hl,spr_order
.draw:	push bc
	push hl
	ld a,(hl)
	call spr_entry			; IX = entry
	ld a,(ix+SE_STAMP)
	or a
	call z,sprite_one
	pop hl
	pop bc
	inc hl
	djnz .draw
.end:	RAM RAM_C0
	ret

; The stamps, if this buffer needs them drawn (see the top). Which ones:
; stamp_diff (src/game/stamps.asm, bank 5, mapped here) marks them
; (SE_STAMP = 2) and lists the rectangles to erase.
stamps_draw:
	call stamp_diff
	ret z				; nothing to do
	ld a,(sd_nerase)		; erase: the tiles again
	or a
	jr z,.draw
	ld b,a
	ld hl,sd_erase
.er:	push bc
	ld e,(hl)
	inc hl
	ld d,(hl)
	inc hl
	ld c,(hl)
	inc hl
	ld b,(hl)
	inc hl
	push hl
	call redraw_tiles		; DE = x, BC = y (keeps bank 5)
	pop hl
	pop bc
	djnz .er
.draw:	ld a,(spr_n)			; the marked ones, in depth order
	or a
	jr z,.nd
	ld b,a
	ld hl,spr_order
.d:	push bc
	push hl
	ld a,(hl)
	call spr_entry
	ld a,(ix+SE_STAMP)
	cp 2
	call z,sprite_one
	pop hl
	pop bc
	inc hl
	djnz .d
.nd:	RAM RAM_C5			; (stamp_diff's data)
	call save_count_ptr		; no save-under for them: drop the records
	ld (hl),0
	ld a,(back)
	or a
	ld hl,SAVE_AREA0
	jr z,.s0
	ld hl,SAVE_AREA1
.s0:	ld (save_ptr),hl
	ret

; A = index -> IX = entry
spr_entry:
	ld l,a
	ld h,0
	add hl,hl
	add hl,hl
	add hl,hl
	add hl,hl			; *16
	ld de,spr_list
	add hl,de
	push hl
	pop ix
	ret

; ---------------------------------------------------------------------------
; Clip, save under and draw the sprite at IX (its 1 or 3 parts).
sprite_one:
	; bx = x / 2 (signed: a sprite can stick out at the left map edge)
	ld l,(ix+SE_X)
	ld h,(ix+SE_X+1)
	sra h
	rr l
	ld (sp_bx),hl
	ex de,hl
	ld a,(scr_cx)			; left = 2cx - bx: clipL = max(0, left),
	add a,a				; invisible if left >= 16
	ld l,a
	ld h,0
	or a
	sbc hl,de
	jp m,.l0
	ld a,h
	or a
	ret nz
	ld a,l
	cp SPR_W
	ret nc
	jr .l1
.l0:	xor a
.l1:	ld (sp_cl),a
	ld c,a
	ld de,VIEW_CW*2			; bytes up to the right edge: left + 80
	add hl,de			; (ADD HL does not set S/Z)
	bit 7,h
	ret nz
	ld a,h
	or l
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
	cp SPR_W			; whole width visible? (compiled path)
	ld a,0
	jr nz,.fw
	cp c
	jr nz,.fw
	inc a
.fw:	ld (sp_full),a

	; one save-under record for the whole sprite
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
	ld l,(ix+SE_FRAME)		; parts: 1 (a whole frame) or 3 (figure)
	ld h,(ix+SE_FRAME+1)
	ld (sp_parts),hl
	ld l,(ix+SE_F2)
	ld h,(ix+SE_F2+1)
	ld (sp_parts+2),hl
	ld l,(ix+SE_F3)
	ld h,(ix+SE_F3+1)
	ld (sp_parts+4),hl
	ld hl,sp_parts
	ld (sp_pp),hl
.part:	ld hl,(sp_pp)			; (sp_parts ends with a 0 word)
	ld e,(hl)
	inc hl
	ld d,(hl)
	inc hl
	ld (sp_pp),hl
	ld a,d
	or e
	jp z,.end
	ld (sp_desc),de
	ld hl,DS_H
	add hl,de
	ld b,(hl)			; B = lines of the part
	inc hl
	ld e,(hl)			; y of its first line = SE_Y + dy
	ld d,0
	ld l,(ix+SE_Y)
	ld h,(ix+SE_Y+1)
	add hl,de
	ld de,(scr_sy)
	or a
	sbc hl,de			; y - sy
	jp m,.above
	ld a,h				; starts in the view: skip 0,
	or a				; lines = min(h, 168 - (y - sy))
	jp nz,.part
	ld a,PF_ROWS*8
	sub l
	jp c,.part
	jp z,.part
	cp b
	jr c,.ln
	ld a,b
.ln:	ld (sp_lines),a
	xor a
	ld (sp_skip),a
	add hl,de			; ly0 = y
	jr .vis
.above:	ld a,l				; cut at the top: skip = sy - y,
	neg				; lines = h - skip
	jp z,.part			; 256 lines above
	ld c,a
	ld a,h
	inc a
	jp nz,.part			; more than 255 lines above
	ld a,b
	sub c
	jp c,.part
	jp z,.part
	ld (sp_lines),a
	ld a,c
	ld (sp_skip),a
	ex de,hl			; ly0 = sy
.vis:	ld (sp_ly0),hl
	ld de,(top_lim)			; in the partial top row? (copy_top needed)
	ld a,l
	sub e
	ld a,h
	sbc a,d
	jr nc,.nt
	ld a,1
	ld (top_hit),a
.nt:	ld a,l				; row offset of ly0: (Y*80 + bx) & 2047
	and 7
	ld (sp_r0),a
	ld a,l
	srl h
	rra
	srl h
	rra
	srl h
	rra				; A = Y (< 128)
	add a,a
	ld l,a
	ld h,hi(row80)
	ld a,(hl)
	inc l
	ld h,(hl)
	ld l,a
	ld de,(sp_bx)
	add hl,de
	ld a,h
	and 7
	ld h,a
	ld (sp_row0),hl
	ld a,(sp_full)			; compiled code if fully visible, no wrap
	or a
	push ix				; (the drawing uses IX for the screen)
	jr z,.clip
	call rows_nowrap
	jr z,.cmp
.clip:	call sprite_clipped
	pop ix
	jp .part
.cmp:	call sprite_compiled
	pop ix
	jp .part
.end:	ld hl,(save_ptr)		; end of the record
	ld (hl),0
	inc hl
	ld (save_ptr),hl
	ret

; Compiled path: save record header, then run the frame's program from the
; first visible line, with a RET over the call after the last one.
sprite_compiled:
	ld hl,(sp_desc)
	ld c,(hl)			; DS_BANK
	ld b,GA_PORT
	out (c),c
	inc hl
	ld e,(hl)			; program
	inc hl
	ld d,(hl)
	ld a,(sp_skip)			; entry = program + 3*skip
	ld c,a
	ld b,0
	ex de,hl
	add hl,bc
	add hl,bc
	add hl,bc
	push hl
	ld a,(sp_lines)			; RET after the last visible line
	ld c,a
	add hl,bc
	add hl,bc
	add hl,bc
	ld (cs_stop),hl
	ld a,(hl)
	ld (cs_byte),a
	ld (hl),#C9
	ld hl,(sp_row0)			; IX = first line's byte 0
	ld (cs_row),hl
	ld a,(sp_r0)
	add a,a
	add a,a
	add a,a
	add a,h
	ld h,a
	ld a,(scr_page)
	add a,h
	ld ixh,a
	ld a,l
	ld ixl,a
	ld de,(save_ptr)		; the SAVE stubs write the segments
	pop hl
	call .run
	ld hl,(cs_stop)
	ld a,(cs_byte)
	ld (hl),a
	ld (save_ptr),de
	ret
.run:	jp (hl)

; Clipped path (cut at the left/right edge, or a row crosses the end of a 2K
; block). Consecutive lines that are whole and inside the block run as one
; piece of the compiled program (a compiled run chunk); each other line is
; copied from the screen into CL_BUF (saved as segments, split at the block
; end), drawn there by its line routine and its visible bytes written back.
sprite_clipped:
	ld hl,clip_count		; sprites drawn this way (frame rate test)
	inc (hl)
	ld hl,(sp_desc)
	ld a,(hl)			; DS_BANK
	ld (cs_bank),a
	ld c,a
	ld b,GA_PORT
	out (c),c
	inc hl
	ld e,(hl)			; program
	inc hl
	ld d,(hl)
	inc hl
	ld (cc_prog0),de
	push hl
	ld a,(sp_skip)
	ld (cc_li),a
	ld c,a
	ld b,0
	ex de,hl
	add hl,bc
	add hl,bc
	add hl,bc
	inc hl				; target of the first visible line's call
	ld (cc_prog),hl
	pop hl
	ld e,(hl)			; span table + 2*skip
	inc hl
	ld d,(hl)
	ex de,hl
	add hl,bc
	add hl,bc
	ld (cc_span),hl
	ld a,(sp_r0)
	ld (cc_r),a
	ld hl,(sp_row0)
	ld (cc_row),hl
	ld a,(sp_lines)
	ld (cc_left),a
	xor a
	ld (cc_rn),a
.line:	ld hl,(cc_span)
	ld c,(hl)			; start
	inc hl
	ld a,(hl)			; count
	or a
	jr z,.dir			; empty line: STEP only
	add a,c
	ld b,a				; end
	ld (cc_end),a
	ld a,c
	ld (cc_st),a
	ld a,(cc_row+1)			; row crosses the block end?
	cp 7
	jr c,.nw
	ld a,(cc_row)
	cp #F1
	jr nc,.part0
.nw:	ld a,(sp_cl)			; whole line visible?
	cp c
	jr z,.l
	jr nc,.part0
.l:	ld a,(sp_cr)
	cp b
	jr c,.part0
.dir:	ld a,(cc_rn)			; extend the compiled run
	or a
	jr nz,.inc
	ld a,(cc_li)
	ld (rs_li),a
	ld a,(cc_r)
	ld (rs_r),a
	ld hl,(cc_row)
	ld (rs_row),hl
	xor a
.inc:	inc a
	ld (cc_rn),a
	jp .next
.part0:	call .flush
	ld a,(cc_end)			; visible columns: c = max(start, cl),
	ld b,a				; b = min(end, cr)
	ld a,(cc_st)
	ld c,a
	ld a,(sp_cr)
	cp b
	jr nc,.e
	ld b,a
.e:	ld a,(sp_cl)
	cp c
	jr c,.s
	ld c,a
.s:	ld a,b
	sub c
	jp z,.next
	jp c,.next
	ld (cc_n),a
	ld a,c
	ld (cc_a),a
.part:	ld hl,(cc_row)			; screen = page + r*&800 + (row + c) & 2047
	ld b,0
	add hl,bc
	ld a,h
	and 7
	ld h,a
	ld a,(cc_r)
	add a,a
	add a,a
	add a,a
	or h
	ld h,a
	ld a,(scr_page)
	or h
	ld h,a
	ld a,(cc_n)			; n1 = bytes up to the block end
	ld b,a
	ld a,h
	and 7
	cp 7
	ld a,b
	jr nz,.n1
	ld a,l
	add a,b
	ld a,b
	jr nc,.n1
	jr z,.n1
	xor a
	sub l
.n1:	ld (cc_n1),a
	ld (cc_s1),hl
	ld de,(save_ptr)		; segment 1: [n1][address][bytes]
	call .seg
	ld a,(cc_n)
	ld b,a
	ld a,(cc_n1)
	ld c,a
	ld a,b
	sub c
	ld (cc_n2),a
	jr z,.sv
	ld bc,-#800			; segment 2 from the start of the block
	add hl,bc
	ld (cc_s2),hl
	call .seg
.sv:	ld (save_ptr),de
	ld hl,CL_BUF			; DE = copy position of column c
	ld a,(cc_a)
	add a,l
	ld e,a
	ld a,h
	adc a,0
	ld d,a
	ld hl,(cc_s1)
	ld a,(cc_n1)
	ld c,a
	ld b,0
	ldir
	ld a,(cc_n2)
	or a
	jr z,.dr
	ld hl,(cc_s2)
	ld c,a
	ldir
.dr:	ld hl,(cc_prog)			; draw the line on the copy, entering
	ld e,(hl)			; after the SAVE call: HL = copy + start
	inc hl
	ld d,(hl)
	inc de
	inc de
	inc de
	ld (.call+1),de
	ld ix,CL_BUF
	ld hl,CL_BUF
	ld a,(cc_st)
	add a,l
	ld l,a
	ld a,h
	adc a,0
	ld h,a
.call:	call 0
	ld hl,CL_BUF			; visible bytes back to the screen
	ld a,(cc_a)
	add a,l
	ld l,a
	ld a,h
	adc a,0
	ld h,a
	ld de,(cc_s1)
	ld a,(cc_n1)
	ld c,a
	ld b,0
	ldir
	ld a,(cc_n2)
	or a
	jr z,.next
	ld de,(cc_s2)
	ld c,a
	ldir
.next:	ld hl,(cc_span)
	inc hl
	inc hl
	ld (cc_span),hl
	ld hl,(cc_prog)
	inc hl
	inc hl
	inc hl
	ld (cc_prog),hl
	ld hl,cc_li
	inc (hl)
	ld a,(cc_r)
	inc a
	and 7
	ld (cc_r),a
	jr nz,.nr
	ld hl,(cc_row)
	ld bc,80
	add hl,bc
	ld a,h
	and 7
	ld h,a
	ld (cc_row),hl
.nr:	ld hl,cc_left
	dec (hl)
	jp nz,.line
	jp .flush

; Run the pending compiled run (rs_*, cc_rn lines) with its chunk header.
.flush:	ld a,(cc_rn)
	or a
	ret z
	ld de,(save_ptr)		; the SAVE stubs write the segments
	ld hl,(rs_row)
	ld (cs_row),hl
	ld a,(rs_r)			; IX = first line's byte 0
	add a,a
	add a,a
	add a,a
	add a,h
	ld h,a
	ld a,(scr_page)
	add a,h
	ld ixh,a
	ld a,l
	ld ixl,a
	ld a,(rs_li)			; entry = program + 3*line
	ld c,a
	ld b,0
	ld hl,(cc_prog0)
	add hl,bc
	add hl,bc
	add hl,bc
	push hl
	ld a,(cc_rn)			; RET after the run
	ld c,a
	add hl,bc
	add hl,bc
	add hl,bc
	ld (cs_stop),hl
	ld a,(hl)
	ld (cs_byte),a
	ld (hl),#C9
	pop hl
	call .jhl
	ld hl,(cs_stop)
	ld a,(cs_byte)
	ld (hl),a
	ld (save_ptr),de
	xor a
	ld (cc_rn),a
	ret
.jhl:	jp (hl)

; [A][HL] at DE, then A bytes HL -> DE
.seg:	ld (de),a
	inc de
	ld c,a
	ld a,l
	ld (de),a
	inc de
	ld a,h
	ld (de),a
	inc de
	ld b,0
	ldir
	ret

spr_n:		db 0
top_lim:	dw 0
top_hit:	db 0		; a sprite in the partial top row this frame
clip_count:	db 0
cc_prog:	dw 0
cc_prog0:	dw 0
cc_li:		db 0
cc_rn:		db 0
rs_li:		db 0
rs_r:		db 0
rs_row:		dw 0
cc_span:	dw 0
cc_r:		db 0
cc_row:		dw 0
cc_left:	db 0
cc_n:		db 0
cc_st:		db 0
cc_end:		db 0
cc_a:		db 0
cc_n1:		db 0
cc_n2:		db 0
cc_s1:		dw 0
cc_s2:		dw 0
spr_z:		dw 0
spr_f2:		dw 0
spr_f3:		dw 0
spr_list:	ds SPR_MAX*SE_SIZE,0
spr_stamp:	db 0		; next sprites_add_z: a stamp
spr_order:	ds SPR_MAX,0	; draw order (indices), sorted by depth
spr_keys:	ds SPR_MAX*2,0	; their depth keys
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
sp_desc:	dw 0
cs_bank:	db 0
cs_stop:	dw 0
cs_byte:	db 0
cs_row:		dw 0
sp_full:	db 0
sp_w:		db 0
sp_y:		dw 0
sp_parts:	ds 8,0
sp_pp:		dw 0

; row80[Y] = Y*80 (byte offset of char row Y in the ring, before & 2047)
	align 256
row80:	repeat 128,ry
	dw (ry-1)*80
	rend
