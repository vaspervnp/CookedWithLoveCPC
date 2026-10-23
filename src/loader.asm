; CWL.BIN, what RUN"CWL starts: the title screen (TITLE.SCR, tools/mktitle.py)
; on the screen at once, through the firmware, then the game (GAME.BIN at
; &0100, src/main.asm), which loads the rest with the title still showing.

KL_INIT_BACK	equ #BCCE
SCR_SET_MODE	equ #BC0E
SCR_SET_INK	equ #BC32
SCR_SET_BORDER	equ #BC38
CAS_IN_OPEN	equ #BC77
CAS_IN_DIRECT	equ #BC83
CAS_IN_CLOSE	equ #BC7A
GAME_BASE	equ #0100
BUFFER		equ #8000	; 2K, for CAS IN OPEN

	org #9000
	; started with RUN": AMSDOS (ROM 7) again, so that CAS IN reads the disc
	ld c,7
	ld de,#0040
	ld hl,#ABFF
	call KL_INIT_BACK
	xor a
	call SCR_SET_MODE
	ld hl,palette_fw
	xor a
.ink:	push af
	push hl
	ld b,(hl)
	ld c,b
	call SCR_SET_INK
	pop hl
	pop af
	inc hl
	inc a
	cp 16
	jr nz,.ink
	ld b,(hl)
	ld c,b
	call SCR_SET_BORDER
	ld hl,title
	ld b,9
	ld de,#C000
	call load
	ld hl,game
	ld b,8
	ld de,GAME_BASE
	call load
	jp GAME_BASE

; File HL (name length B) to DE.
load:	push de
	ld de,BUFFER
	call CAS_IN_OPEN
	pop hl
	call CAS_IN_DIRECT
	jp CAS_IN_CLOSE

title:	db "TITLE.SCR"
game:	db "GAME.BIN"
	include "palette.asm"
