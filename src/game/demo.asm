; -DDEMO=1 (src/main.asm): the scripted input, in bank 5.

	if DEMO
; Scripted input: pairs (keys, frames), looped. Advances by the frames drawn.
demo_input:
	ld a,(demo_left)
	or a
	jr nz,.cur
	ld hl,(demo_ptr)
	ld a,(hl)
	cp #FF
	jr nz,.n
	ld hl,demo_script
.n:	ld a,(hl)
	ld (demo_keys),a
	inc hl
	ld a,(hl)
	inc hl
	ld (demo_ptr),hl
.cur:	dec a
	ld (demo_left),a
	ld a,(demo_keys)
	ret
R	equ 1<<KEY_RIGHT
L	equ 1<<KEY_LEFT
D	equ 1<<KEY_DOWN
U	equ 1<<KEY_UP
F	equ 1<<KEY_FIRE
demo_script:
	if MAP_TEST==0			; level 1: Easy, the morning (a portion of
	db 0,8, F,1, 0,2		; the first 4), then the first group,
	repeat 4			; all the service
	db U,1, 0,1, R,1, 0,1
	rend
	db 0,20, F,1
	db 0,30, L,4, 0,6, F,1, 0,4, U,22, R,20, 0,8, F,1, 0,120	; to a table for 4
	db F,1, R,32, U,27, 0,90, F,1	; order, to the pass, take the plates
	db D,27, L,32, 0,4, F,1, 0,165, F,1	; serve, they eat, pay
	db 0,60, F,1, R,32, U,27, F,1	; clear the table, plates to the pass
	db 0,250, #FF
	else
	db R,90, D,70, 0,10, L,120, U,40, R|D,60, L|U,50, D,140, R,200, U,120, L,40, L|D,80, 0,15, U,200, #FF
	endif
demo_ptr:	dw demo_script
demo_left:	db 0
demo_keys:	db 0
	endif
