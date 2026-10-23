; Sound effects on AY channel C (tone or noise), one at a time: a new one
; cuts the one playing. sfx_tick runs at each VSYNC (irq_i0); it leaves the
; PSG alone while read_input reads the keyboard through it (psg_busy).
; Not in the DEMO and scroll test builds (no room there, SOUND in
; src/main.asm): the entry points just return.
;
; An effect: steps of 2 bytes, then 0:
;   volume << 4 | frames (1-15 VBLs),  pitch (tone period / 4: 15625 / Hz;
;   0 = noise)

SFX_ORDER	equ 0
SFX_SERVE	equ 1
SFX_COIN	equ 2
SFX_READY	equ 3
SFX_ANGRY	equ 4
SFX_BURN	equ 5
SFX_DONE	equ 6
SFX_BOX		equ 7		; Blossom: a box taken or put
SFX_DELIV	equ 8		; the delivery at the door
SFX_DAY		equ 9		; the day over
	assert SFX_BURN==SFX_DONE-1	; (kitchen_tick)

	if SOUND
; A = SFX_*. Destroys AF.
sfx_play:
	push hl
	add a,a
	ld hl,sfx_tab
	add a,l
	ld l,a
	jr nc,$+3
	inc h
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	di
	ld (sfx_ptr),hl
	xor a
	ld (sfx_left),a
	ei
	pop hl
	ret

; At each VSYNC (interrupt). Destroys AF, BC, DE, HL.
sfx_tick:
	ld a,(psg_busy)
	or a
	ret nz
	ld hl,sfx_left
	ld a,(hl)
	or a
	jr z,.step
	dec (hl)
	ret
.step:	ld hl,(sfx_ptr)
	ld a,h				; (high byte 0: none playing)
	or a
	ret z
	ld a,(hl)
	or a
	jr z,sfx_off
	inc hl
	ld d,(hl)			; pitch
	inc hl
	ld (sfx_ptr),hl
	ld e,a
	and #0F
	dec a
	ld (sfx_left),a
	ld a,e
	rrca
	rrca
	rrca
	rrca
	and #0F
	ld e,a
	ld a,10				; volume C
	call psg_write
	ld a,d
	or a
	jr z,.noise
	rlca				; period = pitch * 4
	rlca
	ld d,a
	and #FC
	ld e,a
	ld a,4
	call psg_write
	ld a,d
	and 3
	ld e,a
	ld a,5
	call psg_write
	ld e,%00111011			; tone C only (port A stays input)
	jr .mix
.noise:	ld e,15
	ld a,6
	call psg_write
	ld e,%00011111			; noise C only
.mix:	ld a,7
	jr psg_write

; Silence (before a disc load: no interrupts then). Destroys AF, BC, E.
sfx_off:
	xor a
	ld (sfx_ptr+1),a
	ld e,a
	ld a,10
	; fall through

; PSG register A = E. Destroys BC.
psg_write:
	ld b,#F4
	out (c),a
	ld bc,#F6C0			; select
	out (c),c
	ld c,0
	out (c),c
	ld b,#F4
	out (c),e
	ld bc,#F680			; write
	out (c),c
	ld c,0
	out (c),c
	ret

sfx_tab:	dw fx_order,fx_serve,fx_coin,fx_ready,fx_angry,fx_burn,fx_done
		dw fx_box,fx_deliv,fx_day
fx_order:	db #C2,20, #82,15, 0				; blip
fx_serve:	db #D3,30, #D3,24, #C4,20, #62,20, 0		; C E G
fx_coin:	db #E3,16, #F4,12, #A4,12, #54,12, 0		; B, E
fx_ready:	db #E2,18, #B3,18, #74,18, #34,18, 0		; ding
fx_angry:	db #C4,40, #C4,47, #C6,60, #66,60, 0		; down
fx_burn:	db #E4,0, #A6,0, #56,0, #38,0, 0		; hiss
fx_done:	db #B2,15, #02,15, #B3,15, #43,15, 0		; ding ding
fx_box:		db #D1,0, #A2,90, #42,90, 0			; thud
fx_deliv:	db #C2,0, #04,1, #C2,0, 0			; knock knock
fx_day:		db #C5,30, #C5,24, #C5,20, #D8,15, #64,15, 0	; C E G C
sfx_ptr:	dw 0
sfx_left:	db 0
psg_busy:	db 0
	else
sfx_play:
sfx_tick:
sfx_off:
	ret
	endif
