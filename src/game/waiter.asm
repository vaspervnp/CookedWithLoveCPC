; The hired waiter (sv_exp EXP_WAITER, hired in the evening: src/ovl/prep.asm;
; his wage with the rent): Bill's figure, on his own. He waits at the pass
; (Bill's spot there); an order ready and not on Bill's tray: he takes it,
; walks to its table by the turning points of his way (tools/buildmap.py
; waiter_paths: wt_paths, wt_pts), serves it (sv_serve), walks back.

	if DEMO==0			; (DEMO builds: no room, no one hires)
WT_OFF		equ 0
WT_HOME		equ 1		; at the pass
WT_GO		equ 2		; to the table
WT_BACK		equ 3		; to the pass
WT_WAGE		equ 20		; a day
WT_HIRE		equ 100		; to hire him

wt_rec:		ds 10,0		; actor record (AC_*)
wt_state:	db 0
wt_grp:		db 0		; group + 1 whose plates he carries (0: none)
wt_tab:		db 0
wt_wp:		db 0		; point of the way: 0.. n-1, n the table, #FF home
wt_plates:	db 0

; The morning: at the pass, if hired.
wt_reset:
	xor a
	ld (wt_grp),a
	ld (wt_plates),a
	ld (wt_rec+AC_DIR),a
	ld a,(sv_exp)
	and EXP_WAITER
	jr z,.s
	ld a,WT_HOME
.s:	ld (wt_state),a
	ld hl,PASS_BX
	ld (wt_rec+AC_X),hl
	ld hl,PASS_BY
	ld (wt_rec+AC_Y),hl
	ret

; A tick of the service.
wt_tick:
	ld a,(wt_state)
	or a
	ret z
	dec a
	jr z,.home
	call wt_target			; on his way
	call wt_step
	ret nz
	ld a,(wt_state)
	cp WT_GO
	ld hl,wt_wp
	jr nz,.back
	call wt_way			; B = turning points
	ld a,(hl)
	cp b
	jr nc,.table
	inc (hl)			; the next one
	ret
.table:	ld a,b				; there: back by the same way
	dec a
	ld (hl),a			; (none: #FF, home)
	ld a,WT_BACK
	ld (wt_state),a
	ld a,(wt_grp)			; still theirs (not gone)?
	or a
	ret z
	call wt_group
	xor a
	ld (wt_grp),a
	ld (wt_plates),a
	ld a,(ix+GR_STATE)
	cp GS_CARRIED
	ret nz
	jp sv_serve
.back:	ld a,(hl)
	inc a
	jr z,.home0			; home
	dec (hl)
	ret
.home0:	ld a,WT_HOME
	ld (wt_state),a
	ret
.home:	ld ix,groups			; an order ready: his
	ld b,G_MAX
.g:	ld a,(ix+GR_STATE)
	cp GS_READY
	jr z,.pick
	ld de,GR_SIZE
	add ix,de
	djnz .g
	ret
.pick:	ld (ix+GR_STATE),GS_CARRIED
	ld a,G_MAX
	sub b
	inc a
	ld (wt_grp),a
	ld a,(ix+GR_TABLE)
	ld (wt_tab),a
	ld a,(ix+GR_N)			; (the tray holds 3)
	cp 4
	jr c,.p3
	ld a,3
.p3:	ld (wt_plates),a
	xor a
	ld (wt_wp),a
	ld a,WT_GO
	ld (wt_state),a
	jp sv_hud_tickets

; IX = group wt_grp - 1
wt_group:
	dec a
	add a,a
	add a,a
	add a,a
	add a,a
	ld e,a
	ld d,0
	ld ix,groups
	add ix,de
	ret

; HL = wt_wp, B = the turning points of the way to wt_tab (its first at
; wt_ptr).
wt_way:
	ld a,(wt_tab)
	ld hl,wt_paths
	call st_add
	ld a,(hl)
	ld hl,wt_pts
	call st_add
	ld b,(hl)
	inc hl
	ld (wt_ptr),hl
	ld hl,wt_wp
	ret
wt_ptr:		dw 0

; HL = x, DE = y of the point wt_wp: a turning point (its metatile's
; centre), the table's spot, home.
wt_target:
	call wt_way
	ld a,(hl)
	cp #FF
	jr z,.home
	cp b
	jr nc,.spot
	add a,a				; the point: column, row
	ld hl,(wt_ptr)
	call st_add
	ld e,(hl)
	inc hl
	ld d,(hl)
	ld l,e				; x = 16 c + 8
	ld h,0
	call .m16
	ld bc,8
	add hl,bc
	push hl
	ld l,d				; y = 16 r + 12
	ld h,0
	call .m16
	ld bc,12
	add hl,bc
	ex de,hl
	pop hl
	ret
.m16:	add hl,hl
	add hl,hl
	add hl,hl
	add hl,hl
	ret
.spot:	ld a,(wt_tab)			; the table's spot (as Bill's)
	call sv_table
	inc hl
	ld e,(hl)
	inc hl
	ld d,(hl)
	inc hl
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	ex de,hl
	ret
.home:	ld hl,PASS_BX
	ld de,PASS_BY
	ret

; A step towards HL, DE (x first, then y): Z there.
wt_step:
	ld ix,wt_rec
	push de
	ld e,(ix+AC_X)
	ld d,(ix+AC_X+1)
	ex de,hl
	or a
	sbc hl,de			; x - target
	pop de
	ld a,1<<KEY_LEFT
	jr z,.y
	jr nc,.go
	ld a,1<<KEY_RIGHT
	jr .go
.y:	ld l,(ix+AC_Y)
	ld h,(ix+AC_Y+1)
	or a
	sbc hl,de			; y - target: within a line, there
	inc hl
	ld a,h
	or a
	jr nz,.ny
	ld a,l
	cp 3
	jr nc,.ny
	xor a				; (Z: -1, 0, 1)
	ret
.ny:	dec hl
	bit 7,h
	ld a,1<<KEY_UP
	jr z,.go
	ld a,1<<KEY_DOWN
.go:	call actor_move
	or 1				; NZ
	ret

; His sprite and his tray, if hired (in the view).
wt_sprites:
	ld a,(wt_state)
	or a
	ret z
	ld ix,wt_rec
	ld hl,bill_frames
	call ac_frame
	push hl
	call spr_visible
	pop hl
	ret nc
	ld (tray_x),de
	ld (tray_y),bc
	call sprites_add
	ld a,(wt_rec+AC_DIR)
	ld b,a
	ld a,(wt_plates)
	jp tray_ab
	else
wt_tick:
wt_sprites:
wt_reset:
	ret
wt_grp:		db 0
WT_WAGE		equ 0
WT_HIRE		equ 0
	endif
