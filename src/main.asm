; Cooked with Love - Amstrad CPC 6128
; Build: rasm src/main.asm -Isrc -Ibuild -DLANG_EN=1 (or -DLANG_GR=1)
;
; M1 scroll prototype: cursor keys / joystick scroll the 4x4-screen test map.
; Test builds: -DTEST_X=<sx> -DTEST_Y=<sy> start at that position.
; -DTEST_PATH=1 starts at 0,0 and scrolls there step by step,
; -DTEST_PATH=2 starts at the bottom-right corner and scrolls back there.
; -DTEST_PATH=3 bounces forever between 0,0 and TEST_X,TEST_Y (timing tests
; on other emulators / real hardware).

	ifndef LANG_EN
LANG_EN	equ 0
	endif
	ifndef LANG_GR
LANG_GR	equ 0
	endif
	assert LANG_EN+LANG_GR==1,"define exactly one of LANG_EN / LANG_GR"
	ifndef TEST_X
TEST_X	equ 0
	endif
	ifndef TEST_Y
TEST_Y	equ 0
	endif
	ifndef TEST_PATH
TEST_PATH equ 0
	endif
	ifndef DEBUG
DEBUG	equ 0
	endif
	ifndef FINE_X			; 0 = fallback: 4-pixel horizontal steps
FINE_X	equ 1
	endif
	ifndef FINE_Y			; 0 = fallback: 8-line vertical steps
FINE_Y	equ 1
	endif

STACK_TOP	equ #0100

	org #0100
	buildcpc
	run start

start:
	di
	ld sp,STACK_TOP
	im 1
	ld bc,GA_PORT*256+GA_RMR_MODE0
	out (c),c			; mode 0, ROMs off (firmware no longer used)

	call wait_vsync
	ld hl,palette_hw
	call set_palette

	ld hl,#8000			; clear HUD page and screen
	ld de,#8001
	ld bc,#7FFF
	ld (hl),0
	ldir

	ld de,HUD_SET0*2		; HUD for R3 phase 0 / 1
	ld a,1
	call hud_fill
	ld de,HUD_SET1*2
	ld a,1+HUD_SHIFT1
	call hud_fill

	if TEST_PATH==1 || TEST_PATH==3
	xor a
	ld hl,0
	elseif TEST_PATH==2
	ld a,MAX_SX
	ld hl,MAX_SY
	else
	ld a,TEST_X
	ld hl,TEST_Y
	endif
	call scroll_set
	call scroll_build_state
	call copy_top
	ld hl,nxt_state
	ld de,cur_state
	ld bc,ST_SIZE
	ldir
	xor a
	ld (nxt_ready),a

	call crtc_init
	ei

main_loop:
.wait:	ld a,(nxt_ready)
	or a
	jr nz,.wait
	if DEBUG
	ld bc,GA_PORT*256+GA_PEN_BORDER
	out (c),c
	ld a,#4B
	out (c),a
	endif

	if TEST_PATH
	call test_path_input
	else
	call read_input
	endif
	ld (input),a
	ld a,(scroll_step_x)
	ld b,a
.right:	push bc
	ld a,(input)
	bit KEY_RIGHT,a
	call nz,scroll_right
	ld a,(input)
	bit KEY_LEFT,a
	call nz,scroll_left
	pop bc
	djnz .right
	ld a,(scroll_step_y)
	ld b,a
.down:	push bc
	ld a,(input)
	bit KEY_DOWN,a
	call nz,scroll_down
	ld a,(input)
	bit KEY_UP,a
	call nz,scroll_up
	pop bc
	djnz .down
	call scroll_update

	if DEBUG
	ld bc,GA_PORT*256+GA_PEN_BORDER
	out (c),c
	ld a,#54
	out (c),a
	endif
	jr main_loop

	if TEST_PATH
; Fake input: move towards (TEST_X, TEST_Y), or bounce (TEST_PATH=3).
test_path_input:
	if TEST_PATH==3
	ld e,0
	ld a,(bounce_dx)
	or a
	ld a,(scr_sx)
	jr nz,.xl
	cp TEST_X
	jr c,.xr
	ld a,1
	ld (bounce_dx),a
	jr .by
.xr:	set KEY_RIGHT,e
	jr .by
.xl:	or a
	jr nz,.xl2
	ld (bounce_dx),a
	jr .by
.xl2:	set KEY_LEFT,e
.by:	ld hl,(scr_sy)
	ld a,(bounce_dy)
	or a
	jr nz,.yu
	ld bc,TEST_Y
	or a
	sbc hl,bc
	jr c,.yd
	ld a,1
	ld (bounce_dy),a
	ld a,e
	ret
.yd:	set KEY_DOWN,e
	ld a,e
	ret
.yu:	ld a,h
	or l
	jr nz,.yu2
	ld (bounce_dy),a
	ld a,e
	ret
.yu2:	set KEY_UP,e
	ld a,e
	ret
bounce_dx:	db 0
bounce_dy:	db 0
	endif
	ld e,0
	ld a,(scr_sx)
	cp TEST_X
	jr z,.y
	jr nc,.l
	set KEY_RIGHT,e
	jr .y
.l:	set KEY_LEFT,e
.y:	ld hl,(scr_sy)
	ld bc,TEST_Y
	or a
	sbc hl,bc
	jr z,.done
	jr nc,.u
	set KEY_DOWN,e
	jr .done
.u:	set KEY_UP,e
.done:	ld a,e
	ret
	endif

HUD_SHIFT1	equ 1		; HUD pattern shift (bytes) for R3 phase 1

; Fill the 4 HUD rows at byte offset DE of the &8000 page from the test
; pattern starting at hud_pattern + A. Line 0 of every row is black.
hud_fill:
	ld (hf_src),a
	ld b,0				; line in char row
.line:	ld c,0				; row
.row:	push bc
	push de
	ld a,b
	add a,a
	add a,a
	add a,a
	add a,#80
	ld h,a
	ld a,c				; + row*80
	add a,a
	add a,a
	add a,a
	add a,a
	ld l,a
	add a,a
	add a,a
	add a,l
	ld l,a
	push hl
	pop ix				; dst (without DE)
	pop de
	push de
	add ix,de
	push ix
	pop de
	ld a,b
	or a
	jr nz,.pat
	ld h,d				; line 0: black
	ld l,e
	ld (hl),0
	inc de
	ld bc,79
	ldir
	jr .done
.pat:	ld a,(hf_src)
	ld l,a
	ld h,0
	ld bc,hud_pattern
	add hl,bc
	ld bc,80
	ldir
.done:	pop de
	pop bc
	inc c
	ld a,c
	cp HUD_ROWS
	jr nz,.row
	inc b
	ld a,b
	cp 8
	jr nz,.line
	ret

input:		db 0
; Scroll steps per frame: 1 = fine (2 px / 1 line), 2 / 8 = CRTC fallback.
; Set at boot; CRTC type detection will choose these later.
scroll_step_x:	db 2-FINE_X
scroll_step_y:	db 8-7*FINE_Y
hf_src:		db 0

	include "engine/hw.asm"
	include "engine/input.asm"
	include "engine/crtc.asm"
	include "engine/scroll.asm"
	include "palette.asm"

hud_pattern:
	incbin "testhud.bin"

	align 256
tile_data:
	incbin "testtiles.bin"
map_data:
	incbin "testmap.bin"

	if LANG_EN
	; language-specific data will go here (text, font)
	endif
	if LANG_GR
	endif

code_end:
	assert code_end<=#8000,"code overlaps the HUD page"
	print "code end: ",{hex}code_end
