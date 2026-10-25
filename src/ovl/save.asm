; Saving the progress (the overlay's second half): SAVE.DAT, 1K on the disc
; (the Makefile puts it there, raw), whose sectors the game overwrites; it
; never writes the directory. Each morning but the first of a game it is
; written: "CWL", the version, the game's state that lasts from day to day
; (ov_svtab), a checksum. At the title it is read; valid, the first
; morning's row 3 offers CONTINUE after the modes: the state back, the
; bought expansions' maps and recipes' swaps again, the morning of that day.
; Off in the test builds (short days, TEST_FILL: their timings) unless
; SAVE_TEST.

	ifdef SAVE_TEST
SAVE_ON		equ 1
	else
	ifndef TEST_FILL		; (the test builds' -D: not in the game's
SAVE_ON		equ 0			; symbols)
	else
	ifndef DAY_MIN
SAVE_ON		equ 0
	else
SAVE_ON		equ DEMO==0&&DAY_MIN==180&&TEST_FILL==0
	endif
	endif
	endif
SV_BUF		equ ov_svbuf	; the save (in the overlay's first half)
SV_DISC		equ SAVE_AREA1	; the file, while read or written (the sprites'
				; save-under: invalid then; the directory: FDC_DIRBUF)
SV_LEN		equ 64		; (ov_svbuf, src/ovl/prep.asm)
SV_VER		equ 1

ov_saved:	db 0		; the title read a valid save
ov_svdir:	db 0		; ov_svcopy: 0 save, 1 load, 2 check
ov_svname:	db "SAVE    DAT"
ov_magic:	db "CWL",SV_VER
ov_svtab:	dw sv_money : db 2	; what lasts: address, bytes
		dw sv_day : db 1
		dw sv_mode : db 1
		dw sv_exp : db 1
		dw rc_cnt : db 2+RC_N	; rc_cnt, rc_new, rc_log
		dw st_stock : db 4*ING_N	; the storage: stock, hatch, door, order
		dw 0
	assert 4+2+1+1+1+2+RC_N+4*ING_N+1<=SV_LEN
	assert rc_new==rc_cnt+1&&rc_log==rc_cnt+2
	assert st_hatch==st_stock+ING_N&&st_order==st_stock+3*ING_N

; The state to SV_BUF (A = ov_svdir 0), from it (1) or only summed (2), after
; the magic. Out: A = the sum, DE past the data (the checksum's place).
ov_svcopy:
	ld (ov_svdir),a
	ld de,SV_BUF+4
	ld ix,ov_svtab
	ld c,0
.t:	ld l,(ix+0)
	ld h,(ix+1)
	ld a,h
	or l
	jr z,.e
	ld b,(ix+2)
.b:	ld a,(ov_svdir)
	cp 1
	jr c,.s
	ld a,(de)
	jr nz,.n			; (2: check only)
	ld (hl),a
	jr .n
.s:	ld a,(hl)
	ld (de),a
.n:	add a,c
	ld c,a
	inc hl
	inc de
	djnz .b
	inc ix
	inc ix
	inc ix
	jr .t
.e:	ld a,c
	ret

	if SAVE_ON
; The title: the save, if there and valid (ov_saved). Display off,
; interrupts off (ov_first).
ov_svread:
	ld hl,ov_svname
	ld de,SV_DISC
	call fdc_load
	ret c
	ld hl,SV_DISC
	ld de,SV_BUF
	ld bc,SV_LEN
	ldir
	ld hl,ov_magic
	ld de,SV_BUF
	ld b,4
.m:	ld a,(de)
	cp (hl)
	ret nz
	inc hl
	inc de
	djnz .m
	ld a,2
	call ov_svcopy
	ex de,hl
	cp (hl)
	ret nz
	ld a,1
	ld (ov_saved),a
	ret

; The morning (not the first of a game): the save written. The display
; stops meanwhile (about 2 s), as for a load.
ov_svwrite:
	ld a,(sv_day)
	or a
	ret z
	ld hl,ov_magic
	ld de,SV_BUF
	ld bc,4
	ldir
	xor a
	call ov_svcopy
	ld (de),a
	di
	call crtc_plain
	ld hl,SV_BUF
	ld de,SV_DISC
	ld bc,SV_LEN
	ldir
	ld hl,ov_fdcw			; the file's sectors: written
	ld (fdc_io+1),hl
.try:	ld hl,ov_svname
	ld de,SV_DISC
	call fdc_load
	jr nc,.ok
	ld bc,GA_PORT*256+GA_PEN_BORDER	; an error (write protected?): red, on
	out (c),c
	ld a,#4C
	out (c),a
	ld b,10
.w:	push bc
	call fdc_delay100
	pop bc
	djnz .w
.ok:	ld hl,fdc_read
	ld (fdc_io+1),hl
	call view_restart		; (interrupts on, the base RAM at &4000)
	ld bc,GA_PORT*256+RAM_C5
	out (c),c
	ret

; As fdc_read (src/engine/fdc.asm), with Write Data: sectors fr_first..
; fr_last of track fr_track from fr_dest. Carry set on failure.
ov_fdcw:
	ld a,FDC_TRIES
	ld (fdc_try),a
.again:	ld a,(fr_track)
	ld d,a
	call fdc_seek
	ld a,#45			; Write Data, MFM
	call fdc_out
	xor a				; drive 0, head 0
	call fdc_out
	ld a,(fr_track)			; C
	call fdc_out
	xor a				; H
	call fdc_out
	ld a,(fr_first)			; R
	call fdc_out
	ld a,2				; N: 512 bytes
	call fdc_out
	ld a,(fr_last)			; EOT
	call fdc_out
	ld a,#2A			; GPL
	call fdc_out
	ld a,#FF			; DTL
	call fdc_out
	ld hl,(fr_dest)
	ld bc,FDC_MSR			; execution phase: a byte every 32 us
.x:	in a,(c)
	jp p,.x
	and #20
	jr z,.res
	inc c
	ld a,(hl)
	out (c),a
	inc hl
	dec c
	jp .x
.res:	push hl
	call fdc_result
	pop hl
	ld a,(fdc_res)			; ST0: normal, or "end of cylinder" only
	and #C0
	jr z,.ok
	cp #40
	jr nz,.err
	ld a,(fdc_res+1)		; ST1 (write protected: bit 1)
	cp #80
	jr nz,.err
	ld a,(fdc_res+2)
	or a
	jr nz,.err
.ok:	ld (fr_dest),hl
	or a
	ret
.err:	ld a,(fdc_res+1)		; write protected: no retries
	and 2
	scf
	ret nz
	ld a,#FF
	ld (fdc_track),a
	ld hl,fdc_try
	dec (hl)
	jp nz,.again
	scf
	ret
	else
ov_svread:
ov_svwrite:
	ret
	endif

; CONTINUE chosen: the saved state, the expansions' maps, the recipes'
; swaps; then the morning of that day (ov_morning past its save).
ov_continue:
	ld a,1
	call ov_svcopy
	ld a,(sv_exp)
	bit 0,a				; (EXP_ROOM)
	jr z,.k
	ld hl,patch_open
	call ov_patch
	xor a				; the tables free
	call ov_tables
.k:	ld a,(sv_exp)
	bit 1,a				; (EXP_KITCHEN)
	ld hl,patch_kopen
	call nz,ov_patch
	call ov_view
	ld a,(rc_cnt)			; recipe k replaced dish rc_log[k]
	ld b,a
	ld c,0
.r:	ld a,b
	or a
	jr z,.m
	push bc
	ld a,c
	ld hl,rc_log
	call st_add
	ld b,(hl)
	call rc_swap
	pop bc
	inc c
	dec b
	jr .r
.m:	xor a
	ld (ov_sel),a
	jp ov_morning2
