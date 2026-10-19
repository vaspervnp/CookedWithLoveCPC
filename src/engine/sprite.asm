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
;   chunks, ended by 0:
;   &80 compiled run: [&80][bank][span ptr][lines][r0][row offset][page] and
;       the saved bytes; restored by replaying the span table
;   1..16 segment: [count][address][bytes]
;
; Per frame: sprites_restore (erase what this buffer showed, in reverse
; order), then after buffer_sync: sprites_draw (list sorted by depth).

SPR_W		equ 16		; bytes
SPR_MAX		equ 16
SAVE_AREA0	equ #2000	; save-under records, base RAM (4K per buffer)
SAVE_AREA1	equ #3000
CL_BUF		equ #1FF0	; line copy of the clipped path, below the save areas
	assert ((CL_BUF>>8)&#38)!=#38	; STEP (IXH + 8) must not reach a new char row

; sprite list entry
SE_FRAME	equ 0		; frame descriptor pointer
SE_X		equ 2		; left edge, map pixels (even)
SE_Y		equ 4		; top line
SE_Z		equ 6		; depth key (bottom line; shared by the parts of one figure)
SE_SIZE		equ 8

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
; Same with the depth key in spr_z (parts of one figure share it).
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
	add hl,hl			; index*8
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
.chunk:	ld a,(hl)			; chunk tag
	inc hl
	or a
	jr z,.end
	jp m,.run
	ld c,a				; segment [count][address][bytes]
	ld b,0
	ld e,(hl)
	inc hl
	ld d,(hl)
	inc hl
	ldir
	jr .chunk
.run:	call restore_compiled
	jr .chunk
.end:	pop bc
	pop hl
	djnz .rec
	call save_count_ptr
	ld (hl),0
	ret

; Replay a compiled run chunk (HL after the tag); HL = next chunk.
restore_compiled:
	ld c,(hl)			; bank of the span table
	inc hl
	ld b,GA_PORT
	out (c),c
	ld e,(hl)			; IY = span table
	inc hl
	ld d,(hl)
	inc hl
	push de
	pop iy
	ld a,(hl)			; lines (A' = counter)
	inc hl
	ex af,af'
	ld a,(hl)			; r0
	inc hl
	ld e,(hl)			; row offset
	inc hl
	ld d,(hl)
	inc hl
	ld (rc_row),de
	add a,a				; IX = page + r0*&800 + row
	add a,a
	add a,a
	add a,d
	ld d,a
	ld a,(hl)			; page
	inc hl
	ld (rc_page),a
	add a,d
	ld ixh,a
	ld ixl,e
.line:	ld a,ixl			; DE = IX + start
	add a,(iy+0)
	ld e,a
	ld a,ixh
	adc a,0
	ld d,a
	ld a,(iy+1)			; count
	inc iy
	inc iy
	or a
	call nz,ldi_n
	ld a,ixh			; next line
	add a,8
	ld ixh,a
	and #38
	jr nz,.nr
	push hl				; new char row: row + 80 (mod 2048)
	ld hl,(rc_row)
	ld bc,80
	add hl,bc
	ld a,h
	and 7
	ld h,a
	ld (rc_row),hl
	ld a,(rc_page)
	or h
	ld ixh,a
	ld a,l
	ld ixl,a
	pop hl
.nr:	ex af,af'
	dec a
	ret z
	ex af,af'
	jp .line

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
	ld hl,(sp_row0)
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
	xor a
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
	; order: indices sorted by SE_Z (stable insertion sort)
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

; BC = height of the sprite at IX (keeps HL).
spr_h:
	push hl
	ld l,(ix+SE_FRAME)
	ld h,(ix+SE_FRAME+1)
	ld bc,DS_H
	add hl,bc
	ld c,(hl)
	ld b,0
	pop hl
	ret

; A = index -> IX = entry
spr_entry:
	ld l,a
	ld h,0
	add hl,hl
	add hl,hl
	add hl,hl			; *8
	ld de,spr_list
	add hl,de
	push hl
	pop ix
	ret

; A = index -> DE = depth key
spr_y:
	push hl
	call spr_entry
	ld e,(ix+SE_Z)
	ld d,(ix+SE_Z+1)
	pop hl
	ret

; ---------------------------------------------------------------------------
; Clip, save under and draw the sprite at IX.
sprite_one:
	ld l,(ix+SE_FRAME)		; y of the first line = SE_Y + DS_DY
	ld h,(ix+SE_FRAME+1)
	ld de,DS_DY
	add hl,de
	ld e,(hl)
	ld d,0
	ld l,(ix+SE_Y)
	ld h,(ix+SE_Y+1)
	add hl,de
	ld (sp_y),hl
	; bx = x / 2 (signed: a sprite can stick out at the left map edge)
	ld l,(ix+SE_X)
	ld h,(ix+SE_X+1)
	sra h
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
	sbc hl,de			; 2cx - bx (signed)
	jp m,.l0			; negative -> clipL = 0
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
	sbc hl,de			; bytes from bx to the right edge (signed)
	ret m
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

	; lines: ly0 = max(y, sy), ly1 = min(y+h, sy+168)
	ld hl,(sp_y)
	ld de,(scr_sy)
	push hl
	or a
	sbc hl,de
	pop hl
	jp p,.y0			; y >= sy (signed: y < 0 at the top map edge)
	ex de,hl			; ly0 = sy
.y0:	ld (sp_ly0),hl
	ld hl,(sp_y)
	call spr_h
	add hl,bc			; y + height
	ex de,hl
	ld hl,(scr_sy)
	ld bc,PF_ROWS*8
	add hl,bc			; sy + 168
	push hl
	or a
	sbc hl,de
	pop hl
	jp m,.y1			; sy+168 < y+h
	ex de,hl
.y1:	ld de,(sp_ly0)			; HL = ly1
	or a
	sbc hl,de			; lines to draw
	ret m
	ret z
	ld a,l
	ld (sp_lines),a
	ld hl,(sp_y)
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
	sra d
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
	ld l,(ix+SE_FRAME)
	ld h,(ix+SE_FRAME+1)
	ld (sp_desc),hl
	ld a,(sp_full)			; compiled code if fully visible, no wrap
	or a
	jr z,.clip
	call rows_nowrap
	jp z,sprite_compiled
.clip:	jp sprite_clipped

; Compiled path: save record header, then run the frame's program from the
; first visible line, with a RET over the call after the last one.
sprite_compiled:
	ld hl,(sp_desc)
	ld a,(hl)			; DS_BANK
	ld (cs_bank),a
	inc hl
	ld e,(hl)			; program
	inc hl
	ld d,(hl)
	inc hl
	push hl
	ld a,(sp_skip)			; entry = program + 3*skip
	ld c,a
	ld b,0
	ex de,hl
	add hl,bc
	add hl,bc
	add hl,bc
	ld (cs_ent),hl
	ld a,(sp_lines)			; stop = entry + 3*lines
	ld e,a
	ld d,0
	add hl,de
	add hl,de
	add hl,de
	ld (cs_stop),hl
	pop hl
	ld e,(hl)			; span table + 2*skip
	inc hl
	ld d,(hl)
	ex de,hl
	add hl,bc
	add hl,bc
	ld de,(save_ptr)		; [&80][bank][span][lines][r0][row][page]
	ld a,#80
	ld (de),a
	inc de
	ld a,(cs_bank)
	ld (de),a
	inc de
	ld a,l
	ld (de),a
	inc de
	ld a,h
	ld (de),a
	inc de
	ld a,(sp_lines)
	ld (de),a
	inc de
	ld a,(sp_r0)
	ld (de),a
	inc de
	ld hl,(sp_row0)
	ld (cs_row),hl
	ld a,l
	ld (de),a
	inc de
	ld a,h
	ld (de),a
	inc de
	ld a,(scr_page)
	ld (de),a
	inc de
	ld a,(sp_r0)			; IX = first line's byte 0
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
	ld a,(cs_bank)
	ld c,a
	ld b,GA_PORT
	out (c),c
	ld hl,(cs_stop)			; RET after the last visible line
	ld a,(hl)
	ld (cs_byte),a
	ld (hl),#C9
	ld hl,(cs_ent)
	call .run
	ld hl,(cs_stop)
	ld a,(cs_byte)
	ld (hl),a
	xor a				; end of the record
	ld (de),a
	inc de
	ld (save_ptr),de
	ret
.run:	jp (hl)

; Clipped path (cut at the left/right edge, or a row crosses the end of a 2K
; block). Consecutive lines that are whole and inside the block run as one
; piece of the compiled program (a compiled run chunk); each other line is
; copied from the screen into CL_BUF (saved as segments, split at the block
; end), drawn there by its line routine and its visible bytes written back.
sprite_clipped:
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
	ld hl,(cc_span)
	ld (rs_span),hl
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
	call .flush
	ld hl,(save_ptr)		; end of the record
	ld (hl),0
	inc hl
	ld (save_ptr),hl
	ret

; Run the pending compiled run (rs_*, cc_rn lines) with its chunk header.
.flush:	ld a,(cc_rn)
	or a
	ret z
	ld de,(save_ptr)		; [&80][bank][span][lines][r0][row][page]
	ld a,#80
	ld (de),a
	inc de
	ld a,(cs_bank)
	ld (de),a
	inc de
	ld hl,(rs_span)
	ld a,l
	ld (de),a
	inc de
	ld a,h
	ld (de),a
	inc de
	ld a,(cc_rn)
	ld (de),a
	inc de
	ld a,(rs_r)
	ld (de),a
	inc de
	ld hl,(rs_row)
	ld (cs_row),hl
	ld a,l
	ld (de),a
	inc de
	ld a,h
	ld (de),a
	inc de
	ld a,(scr_page)
	ld (de),a
	inc de
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
cc_prog:	dw 0
cc_prog0:	dw 0
cc_li:		db 0
cc_rn:		db 0
rs_li:		db 0
rs_r:		db 0
rs_row:		dw 0
rs_span:	dw 0
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
sp_desc:	dw 0
cs_bank:	db 0
cs_ent:		dw 0
cs_stop:	dw 0
cs_byte:	db 0
cs_row:		dw 0
rc_row:		dw 0
rc_page:	db 0
sp_full:	db 0
sp_w:		db 0
sp_y:		dw 0
