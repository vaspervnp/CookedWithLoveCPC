; The seats of a table (src/game/service.asm), in base RAM (no room in
; bank 5); called with bank 5 mapped (lvl_tables).

; HL = table, A = seat k -> HL = seat_buf: x, y (the sitting customer's
; sprite), dir; from Bill's spot below the table (tools/buildmap.py
; table_seats): left chair x - 32 facing right, right chair x facing left,
; y - 60 (4 seats: the rows y - 76, y - 60).
tb_seat:
	push bc
	push de
	ld c,a
	ld b,(hl)			; seats
	inc hl
	ld e,(hl)			; DE = x
	inc hl
	ld d,(hl)
	inc hl
	push hl
	ld hl,-32
	add hl,de
	bit 0,c
	jr z,.x
	ld de,32
	add hl,de
.x:	ld (seat_buf),hl
	pop hl
	ld e,(hl)			; DE = y
	inc hl
	ld d,(hl)
	ld hl,-60
	add hl,de
	ld a,b
	cp 4
	jr c,.y
	ld de,-16
	bit 1,c
	jr z,.y4
	ld de,0
.y4:	add hl,de
.y:	ld (seat_buf+2),hl
	bit 0,c
	ld a,DIR_RIGHT
	jr z,.d
	ld a,DIR_LEFT
.d:	ld (seat_buf+4),a
	ld hl,seat_buf
	pop de
	pop bc
	ret
seat_buf:	ds 5,0
