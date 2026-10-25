; Disc loading without the firmware: the uPD765 FDC driven by polling.
;
; fdc_load reads an AMSDOS file of a DATA format disc (drive A, side 0,
; 9 sectors &C1-&C9 of 512 bytes per track, 1K blocks, the directory in
; blocks 0-1) to memory: it reads the directory, collects the file's blocks
; from all its extents and reads them with one Read Data command per run of
; consecutive sectors on a track (otherwise every sector costs a turn of
; the disc). The data transfer must not be interrupted (a byte every 32 us):
; the caller runs it with interrupts off, so the display is stopped meanwhile.

FDC_MOTOR	equ #FA7E
FDC_MSR		equ #FB7E	; main status: bit 7 RQM, 6 DIO, 5 EXM, 4 busy
FDC_DATA	equ #FB7F
FDC_DIRBUF	equ SAVE_AREA0	; 2K directory buffer (the save areas are
				; invalid after a load: the view is rebuilt)
FDC_TRIES	equ 8
	ifndef FDC_DEBUG		; border colour per stage
FDC_DEBUG	equ 0
	endif

	macro FDC_STAGE col
	if FDC_DEBUG
	push bc
	push af
	ld bc,GA_PORT*256+GA_PEN_BORDER
	out (c),c
	ld a,{col}
	out (c),a
	pop af
	pop bc
	endif
	mend

; Send A to the FDC (command phase).
fdc_out:
	push bc
	push af
	ld bc,FDC_MSR
.w:	in a,(c)
	add a,a				; RQM?
	jr nc,.w
	add a,a				; DIO must be 0 (FDC reading)
	jr c,.w
	pop af
	inc c
	out (c),a
	pop bc
	ret

; Result phase: bytes to fdc_res until the FDC waits for a command.
fdc_result:
	ld hl,fdc_res
	ld bc,FDC_MSR
.w:	in a,(c)
	cp #C0				; RQM and DIO: a result byte
	jr c,.chk
	inc c
	in a,(c)
	ld (hl),a
	inc hl
	dec c
	ld a,8				; let the status settle
.d:	dec a
	jr nz,.d
	jr .w
.chk:	cp #80				; RQM, DIO = 0: done (else still busy)
	jr c,.w
	ret

; Wait for the end of a seek/recalibrate: Sense Interrupt Status until
; ST0 shows "seek end" (bit 5).
fdc_seek_end:
	ld a,#08
	call fdc_out
	call fdc_result
	ld a,(fdc_res)
	and #20
	jr z,fdc_seek_end
	ret

; Motor on and the head back to track 0.
fdc_start:
	FDC_STAGE #4B			; white: motor
	ld bc,FDC_MOTOR
	ld a,1
	out (c),a
	ld b,6				; spin-up: about 0.6 s (6 x 0.1 s)
.sp:	push bc
	call fdc_delay100
	pop bc
	djnz .sp
	FDC_STAGE #4A			; yellow: recalibrate
	ld b,2				; twice: recalibrate steps 77 tracks at most
.rc:	push bc
	ld a,#07
	call fdc_out
	xor a
	call fdc_out
	call fdc_seek_end
	pop bc
	djnz .rc
	ld a,#FF
	ld (fdc_track),a
	ret

fdc_stop:
	ld bc,FDC_MOTOR
	xor a
	out (c),a
	ret

; About 0.1 s busy wait (interrupts may be off).
fdc_delay100:
	ld bc,9000
.l:	dec bc
	ld a,b
	or c
	jr nz,.l
	ret

; Seek to track D (if not there yet), with the head settle time.
fdc_seek:
	ld a,(fdc_track)
	cp d
	ret z
	ld a,d
	ld (fdc_track),a
	ld a,#0F
	call fdc_out
	xor a
	call fdc_out
	ld a,d
	call fdc_out
	call fdc_seek_end
	ld bc,450			; ~15 ms head settle
.l:	dec bc
	ld a,b
	or c
	jr nz,.l
	ret

; Read sectors fr_first..fr_last of track fr_track to fr_dest, retrying.
; Out: fr_dest past the data, carry set on failure.
fdc_read:
	ld a,FDC_TRIES
	ld (fdc_try),a
.again:	ld a,(fr_track)
	ld d,a
	FDC_STAGE #52			; green: seek
	call fdc_seek
	FDC_STAGE #53			; cyan: read
	ld a,#46			; Read Data, MFM
	call fdc_out
	xor a				; drive 0, head 0
	call fdc_out
	ld a,(fr_track)			; C
	call fdc_out
	xor a				; H
	call fdc_out
	ld a,(fr_first)			; R: first sector
	call fdc_out
	ld a,2				; N: 512 bytes
	call fdc_out
	ld a,(fr_last)			; EOT: last sector
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
	in a,(c)
	ld (hl),a
	inc hl
	dec c
	jp .x
.res:	push hl
	call fdc_result
	pop hl
	ld a,(fdc_res)			; ST0: normal, or abnormal with only
	and #C0				; "end of cylinder" (no TC on the CPC)
	jr z,.ok
	cp #40
	jr nz,.err
	ld a,(fdc_res+1)		; ST1
	cp #80
	jr nz,.err
	ld a,(fdc_res+2)		; ST2
	or a
	jr nz,.err
.ok:	ld (fr_dest),hl
	or a
	ret
.err:	FDC_STAGE #4C			; red: error, retry
	ld a,#FF			; seek again
	ld (fdc_track),a
	ld hl,fdc_try
	dec (hl)
	jp nz,.again
	scf
	ret

; The file's sectors: read (the overlay points it at its Write Data while
; it saves: src/ovl/save.asm).
fdc_io:	jp fdc_read

; Load the file named at HL (11 characters, as in the directory: name
; padded with spaces, extension) to DE, AMSDOS header included. Carry set
; if not found or unreadable.
fdc_load:
	ld (fl_name),hl
	ld (fr_dest),de
	call fdc_start
	xor a				; directory: track 0, sectors &C1-&C4
	ld (fr_track),a
	ld a,#C1
	ld (fr_first),a
	ld a,#C4
	ld (fr_last),a
	ld hl,(fr_dest)
	push hl
	ld hl,FDC_DIRBUF
	ld (fr_dest),hl
	call fdc_read
	pop hl
	ld (fr_dest),hl
	jp c,.done
	; logical sectors (L = 2*block, 2*block+1) of extents 0, 1, ...
	ld hl,fl_secs
	ld (fl_bp),hl
	xor a
	ld (fl_ext),a
.ext:	ld ix,FDC_DIRBUF
	ld b,64
.ent:	push bc
	ld a,(ix+0)			; user 0
	or a
	jr nz,.no
	ld a,(fl_ext)			; this extent
	cp (ix+12)
	jr nz,.no
	ld hl,(fl_name)			; name and extension (attribute bits off)
	push ix
	pop de
	inc de
	ld b,11
.cmp:	ld a,(de)
	and #7F
	cp (hl)
	jr nz,.no
	inc de
	inc hl
	djnz .cmp
	push ix				; found: its blocks
	pop hl
	ld de,16
	add hl,de
	ld de,(fl_bp)
	ld b,16
.blk:	ld a,(hl)
	or a
	jr z,.bend
	push hl
	ld l,a
	ld h,0
	add hl,hl
	ex de,hl
	ld (hl),e
	inc hl
	ld (hl),d
	inc hl
	inc de
	ld (hl),e
	inc hl
	ld (hl),d
	inc hl
	ex de,hl
	pop hl
	inc hl
	djnz .blk
.bend:	ld (fl_bp),de
	pop bc
	ld hl,fl_ext
	inc (hl)
	jr .ext
.no:	ld de,32
	add ix,de
	pop bc
	djnz .ent
	ld hl,(fl_bp)			; end of the list
	ld (hl),#FF
	inc hl
	ld (hl),#FF
	ld a,(fl_ext)
	or a
	scf
	jr z,.done			; not found
	; runs of consecutive sectors on one track, one Read Data each
	ld hl,fl_secs
.run:	ld e,(hl)
	inc hl
	ld d,(hl)
	inc hl
	ld a,d
	and e
	inc a
	jr z,.ok			; end (carry clear)
	push hl
	call .ltrack			; D = track, E = sector id
	ld a,d
	ld (fr_track),a
	ld a,e
	ld (fr_first),a
	ld (fr_last),a
	pop hl
.grow:	ld a,(fr_last)			; the run ends at the end of the track
	cp #C9
	jr z,.read
	dec hl				; previous L (high, low) and the next one
	ld d,(hl)
	dec hl
	ld e,(hl)
	inc hl
	inc hl
	inc de				; next must be previous + 1
	ld a,(hl)
	cp e
	jr nz,.read
	inc hl
	ld a,(hl)
	dec hl
	cp d
	jr nz,.read
	inc hl
	inc hl
	ld a,(fr_last)
	inc a
	ld (fr_last),a
	jr .grow
.read:	push hl
	call fdc_io
	pop hl
	jr nc,.run
	jr .done
.ok:	or a
.done:	push af
	call fdc_stop
	pop af
	ret

; DE = logical sector -> D = track (L / 9), E = sector id (&C1 + L % 9)
.ltrack:
	ex de,hl
	ld d,0
.div:	ld a,h
	or a
	jr nz,.sub
	ld a,l
	cp 9
	jr c,.rem
.sub:	ld bc,-9
	add hl,bc
	inc d
	jr .div
.rem:	add a,#C1
	ld e,a
	ret

fdc_res:	ds 8,0
fdc_track:	db #FF
fdc_try:	db 0
fr_track:	db 0
fr_first:	db 0
fr_last:	db 0
fr_dest:	dw 0
fl_name:	dw 0
fl_bp:		dw 0
fl_ext:		db 0
fl_secs:	ds 2*2*32+2,0
