; Display engine: CRTC vertical ruptures for a scrolling playfield + fixed HUD.
;
; One VBL (312 lines) = 3 CRTC frames. R9 = 7 everywhere; the fine vertical
; scroll uses the vertical total adjust (R5) at the end of a frame, whose lines
; show rasters 0.. of the row that follows the last one. Line numbers are
; relative to the start of frame B. fy = fine vertical scroll (0..7).
;
;   frame  lines          rows       content
;   B      0..111         14         row 0 shows black memory, then R6=1 turns
;                                     the display off; VSYNC at row 7
;   H      112..151-fy    4 + R5     HUD (4 rows, base &4000 page) + R5 = 8-fy
;                                     lines: top playfield rasters fy..7 (copy)
;   A      152-fy..311    20 + R5    playfield rows cy+1..cy+20 (screen buffer
;                                     &8000 or &C000) + R5 = fy lines: rasters
;                                     0..fy-1 of row cy+21
;
; The playfield is double buffered: the main loop draws the back buffer and
; its HUD set, and the commit at I1 flips to it.
;
; No register write is cycle-critical: every write has at least one row of
; slack. Interrupts (300 Hz, fixed positions relative to VSYNC at line 56):
;   I5 (line 6, B)    constants of B
;   I0 (58, VSYNC)    latch "commit pending", R3 + R12/R13 of H of that state,
;                     R6 = 127 (display on for H and A)
;   I1 (110, end B)   commit; then (in H) R4/R5 of H, R12/R13 of A
;   I2 (162, A row 1) R4/R5/R7 of A
;   I3 (214, A)       R6 = 1 (ends the display at B row 1)
;   I4 (266, A)       R12/R13 of B (black)
; R6 is never 0: on CRTC 1 that blanks the screen immediately.

; --- state block (built by scroll_build_state, committed at I1) ---
ST_HMA		equ 0		; R12/R13 of H (HUD set)
ST_AMA		equ 2		; R12/R13 of A
ST_HR5		equ 4		; R5 of H = 8-fy
ST_AR5		equ 5		; R5 of A = fy
ST_R3		equ 6
ST_SIZE		equ 7

B_ROWS		equ 14
B_MA		equ #1000+200	; 40 words that stay black (base &4000 page)
B_VSYNC_ROW	equ 7
HUD_ROWS	equ 4
PF_ROWS		equ 21		; playfield height in char rows (168 lines)
A_ROWS		equ PF_ROWS-1	; full rows in frame A

R3_STD		equ #86		; VSYNC 8 lines, HSYNC 6 chars
R3_ALT		equ #85		; HSYNC 5 chars: picture 1 byte (2 pixels) right

; Write CRTC register (constant value).
macro CRTC_SET reg,val
	ld bc,#BC00+{reg}
	out (c),c
	ld bc,#BD00+{val}
	out (c),c
mend

; ---------------------------------------------------------------------------
; Initialise the CRTC and the interrupt handler.
; Call with interrupts disabled and cur_state already valid.
crtc_init:
	ld a,#C3			; JP irq at #0038
	ld (#0038),a
	ld hl,irq
	ld (#0039),hl

	CRTC_SET 0,63
	CRTC_SET 1,40
	CRTC_SET 2,46
	CRTC_SET 3,R3_STD
	CRTC_SET 9,7

	; Sync: at VSYNC of the standard frame we are at row 30. Our layout has
	; VSYNC at B row 7 and H starts 7 rows later, so end this frame at row 36.
	call wait_vsync
	CRTC_SET 4,36
	CRTC_SET 5,0
	CRTC_SET 6,127
	ld hl,(cur_state+ST_HMA)
	call crtc_set_ma
	xor a
	ld (irq_n),a
	ld (commit_pending),a
	ret

; A standard full frame (no splits, no interrupts needed) with all pens
; black: the display while the CPU is busy with interrupts off (disc).
crtc_plain:
	call sfx_off
	ld bc,GA_PORT*256
.pal:	out (c),c
	ld a,#54			; black
	out (c),a
	inc c
	ld a,c
	cp GA_PEN_BORDER+1
	jr nz,.pal
	; no wait for VSYNC here: in frame A (R7 = 127) none would come. The
	; first frame may come out odd; the picture is black anyway.
	CRTC_SET 7,30
	CRTC_SET 4,38
	CRTC_SET 5,0
	CRTC_SET 6,25
	CRTC_SET 3,R3_STD
	ret

; HL = R12/R13 value. Destroys BC.
crtc_set_ma:
	ld bc,#BC0C
	out (c),c
	inc b
	out (c),h
	dec b
	inc c
	out (c),c
	inc b
	out (c),l
	ret

; A = value, C = register. Destroys B.
crtc_write:
	ld b,#BC
	out (c),c
	inc b
	out (c),a
	ret

; ---------------------------------------------------------------------------
irq:
	push af
	push bc
	push de
	push hl
	ld b,PPI_B
	in a,(c)
	rra
	jr nc,.disp
	xor a				; VSYNC -> this is I0
	ld (irq_n),a
.disp:	ld hl,(irq_ticks)		; 300 Hz time base
	inc hl
	ld (irq_ticks),hl
	ld hl,irq_n
	ld a,(hl)
	inc (hl)
	and 7
	add a,a
	add a,lo(irq_table)
	ld l,a
	ld h,hi(irq_table)
	ld a,(hl)
	inc l
	ld h,(hl)
	ld l,a
	jp (hl)

irq_ret:
	pop hl
	pop de
	pop bc
	pop af
	ei
	ret

; I0: VSYNC. Decide whether the prepared state is committed this VBL; set its
; R3 now (HSYNC width changes are best done during VSYNC) and the R12/R13 of
; H, which the CRTC latches at the start of H (line 112).
irq_i0:
	ld a,(nxt_ready)
	ld (commit_pending),a
	ld hl,cur_state
	or a
	jr z,.set
	ld hl,nxt_state
.set:	push hl
	ld de,ST_R3
	add hl,de
	ld a,(hl)
	ld c,3
	call crtc_write
	pop hl
	ld a,(hl)			; ST_HMA (R12/R13 hold A's value since I1)
	inc hl
	ld h,(hl)
	ld l,a
	call crtc_set_ma
	ld a,127			; B is past row 1: display stays off until H
	ld c,6
	call crtc_write
	ld hl,frame_count
	inc (hl)
	call sfx_tick
	jp irq_ret

; I1: last lines of B. Commit, then program H and A.
irq_i1:
	ld a,(commit_pending)
	or a
	jr z,.keep
	ld hl,nxt_state
	ld de,cur_state
	ld bc,ST_SIZE
	ldir
	xor a
	ld (nxt_ready),a
	ld (commit_pending),a
.keep:	; wait until H has started (B's last row must still end with R4 = 13)
	ld b,2*64/4
.w1:	djnz .w1			; ~2 lines
	ld a,HUD_ROWS-1
	ld c,4
	call crtc_write
	ld a,(cur_state+ST_HR5)
	ld c,5
	call crtc_write
	; R12/R13 of A: after H row 0 (CRTC 1 reloads R12/R13 during row 0)
	ld b,8*64/4
.w2:	djnz .w2			; ~8 lines
	ld hl,(cur_state+ST_AMA)
	call crtc_set_ma
	jp irq_ret

; I2: A row 1. Program A, B's display off.
irq_i2:
	ld a,A_ROWS-1
	ld c,4
	call crtc_write
	ld a,(cur_state+ST_AR5)
	ld c,5
	call crtc_write
	ld a,127			; no VSYNC inside A
	ld c,7
	call crtc_write
	jp irq_ret

; I3: A row ~8. Display off from B row 1 on.
irq_i3:
	ld a,1
	ld c,6
	call crtc_write
	jp irq_ret

; I4: late in A. B's row 0 shows black memory.
irq_i4:
	ld hl,B_MA
	call crtc_set_ma
	jp irq_ret

; I5: B row 0. Constants of B.
irq_i5:
	ld a,B_ROWS-1
	ld c,4
	call crtc_write
	xor a
	ld c,5
	call crtc_write
	ld a,B_VSYNC_ROW
	ld c,7
	call crtc_write
	jp irq_ret

	align 16
irq_table:
	dw irq_i0, irq_i1, irq_i2, irq_i3, irq_i4, irq_i5, irq_ret, irq_ret

irq_n:		db 0
irq_ticks:	dw 0		; +1 per interrupt (300 Hz)
frame_count:	db 0
nxt_ready:	db 0
commit_pending:	db 0
cur_state:	ds ST_SIZE,0
nxt_state:	ds ST_SIZE,0
