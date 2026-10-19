; Display engine: CRTC vertical rupture for a scrolling playfield + fixed HUD.
;
; One VBL (312 lines) = 2 CRTC frames. Line numbers are relative to the start
; of frame B. fy = fine vertical scroll (0..7), g = fy ? fy : 8.
;
;   frame  lines     rows   content
;   B      0..143    18     HUD (4 rows, &8000 page), border, VSYNC at row 11
;   A      144..311  22/21  playfield (&C000 ring)
;
; Fine vertical scroll changes R9 inside frame A:
;   row 0          R9 = 7-fy  (the top row is stored pre-shifted, see scroll.asm)
;   rows 1..20     R9 = 7
;   row 21         R9 = fy-1  (only when fy > 0)
; Each R9 value must be written during the first scanline of its row, so
; those four writes are timed from the 300 Hz interrupts with NOP slides:
;   I0 (VSYNC, ~line 89)  commit next state, R3, R12/R13 of A
;   I1 (~line 141)        R9 at A row 0 and row 1, then R4/R6/R7 of A
;   I4 (~line 297)        R12/R13 of B, R9 at A last row and B row 0, R4/R6/R7 of B
; I2, I3, I5 are free. All other register writes have several rows of slack.

; --- state block (built by the scroll code, committed at VSYNC) ---
ST_AMA		equ 0		; R12/R13 of A (word: high = R12)
ST_HUDMA	equ 2		; R12/R13 of B
ST_AR4		equ 4		; R4 of A
ST_R9TOP	equ 5		; R9 of A row 0
ST_R9BOT	equ 6		; R9 of A last row
ST_R3		equ 7
ST_W1		equ 8		; NOP slide entry: A row 0 -> row 1
ST_W4A		equ 10		; NOP slide entry: I4 -> A last row
ST_W4B		equ 12		; NOP slide entry: A last row -> B
ST_SIZE		equ 14

B_ROWS		equ 18
B_VSYNC_ROW	equ 11
HUD_ROWS	equ 4
PF_ROWS		equ 21		; playfield height in char rows (168 lines)

R3_STD		equ #86		; VSYNC 8 lines, HSYNC 6 chars
R3_ALT		equ #85		; HSYNC 5 chars: picture 1 byte (2 pixels) right

; Cost of the code between two timed R9 writes, not counting the slide.
SLIDE_OVH1	equ 14		; irq_i1: out, call, jp (iy), ret
SLIDE_OVH4	equ 20		; irq_i4: out, ld iy, call, jp (iy), ret

	ifndef PAD_I1
PAD_I1		equ 72		; NOPs from I1 preload to the first R9 write
	endif
	ifndef C4
C4		equ 796		; slide base for I4 -> A last row (minus 64*g)
	endif

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
	CRTC_SET 5,0
	CRTC_SET 9,7

	; Sync: at VSYNC of the standard frame we are at row 30. Our layout has
	; VSYNC at B row 11 and A starts 7 rows later, so end this frame at row 36.
	call wait_vsync
	CRTC_SET 4,36
	ld hl,(cur_state+ST_AMA)
	call crtc_set_ma
	xor a
	ld (irq_n),a
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
	push iy
	ld b,PPI_B
	in a,(c)
	rra
	jr nc,.disp
	xor a				; VSYNC -> this is I0
	ld (irq_n),a
.disp:	ld hl,irq_n
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
	pop iy
	pop hl
	pop de
	pop bc
	pop af
	ei
	ret

; I0: VSYNC. Commit the prepared state.
irq_i0:
	ld a,(nxt_ready)
	or a
	jr z,.keep
	ld hl,nxt_state
	ld de,cur_state
	ld bc,ST_SIZE
	ldir
	xor a
	ld (nxt_ready),a
.keep:	ld hl,(cur_state+ST_AMA)
	call crtc_set_ma
	ld a,(cur_state+ST_R3)
	ld c,3
	call crtc_write
	ld hl,frame_count
	inc (hl)
	jp irq_ret

; I1: R9 at the start of A row 0 and row 1.
irq_i1:
	ld a,(cur_state+ST_R9TOP)
	ld d,a
	ld e,7
	ld bc,#BC09
	out (c),c			; select R9 in advance
	inc b
	ld iy,(cur_state+ST_W1)
	ds PAD_I1,0
	out (c),d			; A row 0: R9 = 7-fy
	call jp_iy
	out (c),e			; A row 1: R9 = 7
	ld a,(cur_state+ST_AR4)
	ld c,4
	call crtc_write
	ld a,127			; no display end, no VSYNC inside A
	ld c,6
	call crtc_write
	ld c,7
	call crtc_write
	jp irq_ret

; I4: R12/R13 of B, then R9 at the start of A's last row and of B.
irq_i4:
	ld hl,(cur_state+ST_HUDMA)
	call crtc_set_ma
	ld a,(cur_state+ST_R9BOT)
	ld d,a
	ld e,7
	ld bc,#BC09
	out (c),c
	inc b
	ld iy,(cur_state+ST_W4A)
	call jp_iy
	out (c),d			; A last row: R9 = fy-1
	ld iy,(cur_state+ST_W4B)
	call jp_iy
	out (c),e			; B row 0: R9 = 7
	ld a,B_ROWS-1
	ld c,4
	call crtc_write
	ld a,HUD_ROWS
	ld c,6
	call crtc_write
	ld a,B_VSYNC_ROW
	ld c,7
	call crtc_write
	jp irq_ret

jp_iy:	jp (iy)

; NOP slide: entering at slide_end-n waits n NOPs (plus the RET).
SLIDE_MAX	equ 1024
slide:	ds SLIDE_MAX,0
slide_end:
	ret

	align 16
irq_table:
	dw irq_i0, irq_i1, irq_ret, irq_ret, irq_i4, irq_ret, irq_ret, irq_ret

irq_n:		db 0
frame_count:	db 0
nxt_ready:	db 0
cur_state:	ds ST_SIZE,0
nxt_state:	ds ST_SIZE,0
