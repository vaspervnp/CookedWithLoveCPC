; The hired waiter (sv_exp EXP_WAITER, hired in the evening: src/ovl/prep.asm;
; his wage with the rent): Bill's figure, on his own. He waits at the pass
; (Bill's spot there); an order ready and not on Bill's tray: he takes it,
; walks to its table by the turning points of his way (tools/buildmap.py
; waiter_paths: HP_WTP in the second HUD page store, hp_get2), serves it
; (sv_serve), walks back. The walking (hw_*) is the hired cook's too
; (src/game/cook.asm).

	if DEMO==0			; (DEMO builds: no room, no one hires)
WT_OFF		equ 0		; (the hired ones' HW_STATE)
WT_HOME		equ 1		; at the pass
WT_GO		equ 2		; to the table (the cook: the station)
WT_BACK		equ 3		; to the pass
WT_WAGE		equ 20		; a day
WT_HIRE		equ 100		; to hire him

	; wt_rec, wt_grp, wt_tab, wt_plates: src/game/vars.asm

; A tick of the service.
wt_tick:
	ld ix,wt_rec
	ld a,(ix+HW_STATE)
	or a
	ret z
	dec a
	jr z,.home
	call hw_walk			; on his way
	ret nz
	ld a,(ix+HW_STATE)
	cp WT_GO
	jr nz,hw_home
	ld (ix+HW_STATE),WT_BACK	; at the table: back by the same way
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
	ld a,(ix+GR_N)			; (the tray holds 3)
	cp 4
	jr c,.p3
	ld a,3
.p3:	ld (wt_plates),a
	ld a,(ix+GR_TABLE)
	ld (wt_tab),a
	ld ix,wt_rec
	add a,HP_WTP
	call hw_go
	ld a,(wt_tab)			; its end: the table's spot (as Bill's)
	call sv_table
	inc hl
	ld e,(hl)
	inc hl
	ld d,(hl)
	inc hl
	ld (ix+HW_EX),e
	ld (ix+HW_EX+1),d
	ld e,(hl)
	inc hl
	ld d,(hl)
	ld (ix+HW_EY),e
	ld (ix+HW_EY+1),d
	jp sv_hud_tickets
hw_home:
	ld (ix+HW_STATE),WT_HOME
	ret

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

; IX = record: on the way at store index A (hp_get2: its index there), its
; end the last point.
hw_go:
	call hp_get2
	ld (ix+HW_PTR),a
	ld (ix+HW_WP),0
	ld (ix+HW_STATE),WT_GO
	ld c,a
	call hp_get2
	add a,a
	add a,c
	dec a
	call hw_point
	ld (ix+HW_EX),l
	ld (ix+HW_EX+1),h
	ld (ix+HW_EY),e
	ld (ix+HW_EY+1),d
	ret

; IX = record going (WT_GO) or back (WT_BACK): a step; Z at the way's end
; (or home), then back by the same way.
hw_walk:
	call hw_target
	call wt_step
	ret nz
	ld a,(ix+HW_PTR)
	call hp_get2
	ld b,a
	ld a,(ix+HW_STATE)
	cp WT_GO
	jr nz,.back
	ld a,(ix+HW_WP)
	cp b
	jr nc,.end
	inc (ix+HW_WP)			; the next one (NZ)
	ret
.end:	dec b				; (none: #FF, home)
	ld (ix+HW_WP),b
	xor a
	ret
.back:	ld a,(ix+HW_WP)
	dec (ix+HW_WP)
	inc a
	ret

; IX = record -> HL = x, DE = y of its point: a turning point (its
; metatile's centre: hw_point, in the common code), the end, home.
hw_target:
	ld a,(ix+HW_PTR)
	call hp_get2
	ld b,a
	ld a,(ix+HW_WP)
	cp #FF
	jr z,.home
	cp b
	jr nc,.end
	add a,a
	add a,(ix+HW_PTR)
	inc a
	jp hw_point
.home:	ld l,(ix+HW_HX)
	ld h,(ix+HW_HX+1)
	ld e,(ix+HW_HY)
	ld d,(ix+HW_HY+1)
	ret
.end:	ld l,(ix+HW_EX)
	ld h,(ix+HW_EX+1)
	ld e,(ix+HW_EY)
	ld d,(ix+HW_EY+1)
	ret

; IX = record: a step towards HL, DE (x first, then y): Z there.
wt_step:
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
	ret
wt_grp:		db 0
WT_WAGE		equ 0
WT_HIRE		equ 0
	endif
