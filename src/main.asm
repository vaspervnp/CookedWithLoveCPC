; Cooked with Love - Amstrad CPC 6128
; Build: rasm src/main.asm -Isrc -Ibuild -DLANG_EN=1 (or -DLANG_GR=1)
;
; M2: Bill walks around the 4x4-screen test map (cursor keys / joystick),
; the camera follows him.
;
; Scroll test builds (no actors, camera only):
;   -DTEST_X=<sx> -DTEST_Y=<sy>  start at that position
;   -DTEST_PATH=1                start at 0,0 and scroll there step by step
;   -DTEST_PATH=2                start at the bottom-right corner, scroll back
;   -DTEST_PATH=3                bounce forever between 0,0 and TEST_X,TEST_Y
; -DDEMO=1: Bill walks a scripted path (collision/camera tests).
; -DDBGPOS=1 (implied by DEMO): HUD line 0 shows camera, sprite position and
; frame as bits, read by tools/gamecheck.py.

	ifndef LANG_EN
LANG_EN	equ 0
	endif
	ifndef LANG_GR
LANG_GR	equ 0
	endif
	assert LANG_EN+LANG_GR==1,"define exactly one of LANG_EN / LANG_GR"
TESTMODE = 0
	ifdef TEST_X
TESTMODE = 1
	endif
	ifdef TEST_Y
TESTMODE = 1
	endif
	ifdef TEST_PATH
TESTMODE = 1
	endif
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
	ifndef DEMO
DEMO	equ 0
	endif
	ifndef DBGPOS
DBGPOS	equ DEMO
	endif
	ifndef MAP_TEST			; 1: the scroll test map, 0: level 1
MAP_TEST	equ TESTMODE
	endif
	ifndef BILL_X0			; start position (tests)
	if MAP_TEST
BILL_X0	equ 96
	else
BILL_X0	equ 176			; level 1: in the dining room, by the entrance
	endif
	endif
	ifndef BILL_Y0
	if MAP_TEST
BILL_Y0	equ 110
	else
BILL_Y0	equ 652
	endif
	endif
	ifndef AREAS			; 0: no area loading (sprite tests)
AREAS	equ 1
	endif
	ifndef TEST_AREA		; test: load area TEST_AREA-1 after the boot
TEST_AREA	equ 0
	endif
	ifndef DBGFPS			; debug band: render count instead of the sprite frame
DBGFPS	equ 0
	endif
	ifndef STAFF			; the cook (test script)
STAFF	equ 1
	endif
	ifndef CUSTOMERS		; test customers (combined parts)
CUSTOMERS	equ 1
	endif
	ifndef CUST_BENCH		; frame rate test: 5 walking customers
CUST_BENCH	equ 0
	endif
SERVICE	equ CUSTOMERS && MAP_TEST==0 && CUST_BENCH==0	; customer groups (game/service.asm)
	ifndef CLONES			; stress test: extra copies of Bill
CLONES	equ 0
	endif
	ifndef FINE_X			; 0 = fallback: 4-pixel horizontal steps
FINE_X	equ 1
	endif
	ifndef FINE_Y			; 0 = fallback: 8-line vertical steps
FINE_Y	equ 1
	endif

	include "engine/defs.asm"
	if MAP_TEST			; SOLID_FIRST of the map, META_N
	include "test.asm"
	include "test_meta.asm"
	else
	include "lvl1.asm"
	include "lvl1_meta.asm"
	endif

STACK_TOP	equ #0100
MAX_TICKS	equ 4		; game ticks run per drawn frame at most (test modes)
FRAME_VBL	equ 4		; the game: a frame every 4 VBLs = 12.5 fps

	org #0100
	buildcpc
	run start

	jp start			; &0100: entry
	jp next_row			; &0103: new char row for compiled sprites
	assert $==#0106

	include "spr.asm"		; frame descriptors (code in banks 4, 6, 7)

; End of the boot, in the common code (the area loader uses the first save
; area as its directory buffer).
boot_done:
	if TEST_AREA			; test: load an area at once
	ld a,TEST_AREA-1
	call area_load
	endif
	jp main_loop

; Start the display from scratch (boot, after a disc load): the rings are
; drawn again for the camera, the sprites' save-unders are dropped, the
; first frame goes into buffer 0 and is shown at once.
view_restart:
	ld a,(scr_sx)
	ld hl,(scr_sy)
	call scroll_set
	xor a
	ld (save_n),a
	ld (save_n+1),a
	ld hl,palette_hw
	call set_palette
	xor a
	call render
	ld hl,nxt_state
	ld de,cur_state
	ld bc,ST_SIZE
	ldir
	xor a
	ld (nxt_ready),a
	call crtc_init
	ld a,(frame_count)
	ld (last_frame),a
	ei
	ret

main_loop:
.wait:	ld a,(nxt_ready)		; previous frame committed?
	or a
	jr nz,.wait
	if DEBUG
	ld bc,GA_PORT*256+GA_PEN_BORDER
	out (c),c
	ld a,#4B
	out (c),a
	endif

	if TESTMODE
	; ticks since the last update (1..MAX_TICKS)
	ld a,(last_frame)
	ld b,a
	ld a,(frame_count)
	ld (last_frame),a
	sub b
	jr nz,.t1
	inc a
.t1:	cp MAX_TICKS+1
	jr c,.t2
	ld a,MAX_TICKS
.t2:	ld (ticks),a
	else
	; fixed rate: a frame every FRAME_VBL VBLs (12.5 fps), FRAME_VBL ticks
.pace:	ld a,(last_frame)
	ld b,a
	ld a,(frame_count)
	sub b
	cp FRAME_VBL
	jr c,.pace
	cp FRAME_VBL*2			; a frame late: start counting again
	ld a,b
	jr c,.ph
	ld a,(frame_count)
	sub FRAME_VBL
.ph:	add a,FRAME_VBL
	ld (last_frame),a
	ld a,FRAME_VBL
	ld (ticks),a
	endif

	if TESTMODE
	call test_path_input
	ld (input),a
	call camera_steps
	else
	if DEMO
	call demo_input
	else
	call read_input
	endif
	ld (input),a
	RAM RAM_C5
.tick:	ld a,(input)
	call actor_tick
	if SERVICE
	call service_tick
	elseif CUSTOMERS
	call cust_tick
	endif
	if STAFF
	call staff_tick
	endif
	ld hl,ticks
	dec (hl)
	jr nz,.tick
	RAM RAM_C0
	endif

	if TESTMODE==0 && SPR_AREAS && AREAS
	call area_check			; (may stop for a disc load)
	endif
	ld a,(back)			; draw the other buffer
	xor 1
	call render

	if DEBUG
	ld bc,GA_PORT*256+GA_PEN_BORDER
	out (c),c
	ld a,#54
	out (c),a
	endif
	jr main_loop

; Draw a complete frame into buffer A and flag it for display.
render:
	ld hl,render_n			; renders so far (frame rate test)
	inc (hl)
	call scroll_select
	if DBGPOS
	call prof_start
	endif
	call sprites_restore
	if DBGPOS
	call prof_mark
	endif
	RAM RAM_C5
	call buffer_sync
	if DBGPOS
	call prof_mark
	endif
	call sprites_clear
	if TESTMODE==0
	call actor_sprites
	if CUSTOMERS
	call cust_sprites
	endif
	if SERVICE
	call service_sprites
	endif
	if STAFF
	call staff_sprites
	endif
	endif
	call sprites_draw
	if DBGPOS
	call prof_mark
	endif
	RAM RAM_C0			; HUD sets (copy_top) are in the base &4000 page
	call scroll_build_state
	call copy_top_if
	if DBGPOS
	call prof_mark
	call dbg_band
	endif
	ld a,1
	ld (nxt_ready),a
	ret

	if TESTMODE
; Test camera: one step per frame per axis (2/8 steps in fallback modes).
camera_steps:
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
	ret

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
	elseif TEST_PATH
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
	else
	xor a
	ret
	endif
	endif

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
	if MAP_TEST==0			; level 1: the first group, all the service
	db 0,30, L,4, 0,6, F,1, 0,4, U,22, R,20, 0,8, F,1, 0,120	; to a table for 4
	db F,1, R,32, U,27, 0,90, F,1	; order, to the pass, take the plates
	db D,27, L,32, 0,4, F,1, 0,165, F,1	; serve, they eat, pay
	db 0,60, F,1, R,32, U,27, F,1	; clear the table, plates to the pass
	db 0,250, 0,250, 0,250, #FF
	else
	db R,90, D,70, 0,10, L,120, U,40, R|D,60, L|U,50, D,140, R,200, U,120, L,40, L|D,80, 0,15, U,200, #FF
	endif
demo_ptr:	dw demo_script
demo_left:	db 0
demo_keys:	db 0
	endif

	if DBGPOS
; Debug band on HUD line 0 of the set being drawn: 64 bits, MSB first, one
; byte each (#FF = 1, 0 = 0): sx(8), sy(16), sprite 0 left(16), top(16),
; frame number(8). Needs RAM_C0.
dbg_band:
	ld hl,(nxt_state+ST_HMA)	; set s -> byte s*512 of the &4000 page
	ld a,h
	and 3
	add a,a
	add a,#40
	ld d,a
	ld e,0
	ld a,(scr_sx)
	call .byte
	if DBGFPS			; frame rate test: stage times in whole bytes
	ld hl,(prof_t)
	call .word
	ld hl,(prof_t+2)
	call .word
	ld a,(spr_n)			; sprites, of which drawn by the clipped path
	ld h,a
	ld a,(clip_count)
	ld l,a
	call .word
	else
	ld hl,(scr_sy)
	call .word
	ld hl,(spr_list+SE_X)
	call .word
	ld hl,(spr_list+SE_Y)
	call .word
	endif
	if DBGFPS
	ld a,(render_n)			; frame rate test: renders so far
	else
	ld a,(dbg_frame)
	endif
	call .byte
	ld hl,prof_t			; 4 stage times (1/300 s), 4 bits each
	ld a,(hl)
	rlca
	rlca
	rlca
	rlca
	inc hl
	or (hl)
	push hl
	call .byte
	pop hl
	inc hl
	ld a,(hl)
	rlca
	rlca
	rlca
	rlca
	inc hl
	or (hl)
.byte:	ld b,8
.bit:	rlca
	ld c,0
	jr nc,.z
	dec c
.z:	ex de,hl
	ld (hl),c
	ex de,hl
	inc de
	djnz .bit
	ret
.word:	ld a,h
	push hl
	call .byte
	pop hl
	ld a,l
	jr .byte

; Stage timing for the debug band.
prof_start:
	ld hl,(irq_ticks)
	ld (prof_last),hl
	ld hl,prof_t
	ld (prof_ptr),hl
	ret
prof_mark:
	ld hl,(irq_ticks)
	ld de,(prof_last)
	ld (prof_last),hl
	or a
	sbc hl,de
	ld a,l
	if DBGFPS==0			; 4 bits in the normal band
	cp 16
	jr c,.ok
	ld a,15
	endif
.ok:	ld hl,(prof_ptr)
	ld (hl),a
	inc hl
	ld (prof_ptr),hl
	ret
prof_last:	dw 0
prof_ptr:	dw prof_t
prof_t:		ds 4,0
	endif

HUD_SHIFT1	equ 1		; HUD pattern shift (bytes) for R3 phase 1

input:		db 0
dbg_frame:	db 0		; Bill's frame (debug band; set in game/actor.asm)
lb_addr:	dw 0
render_n:	db 0
ticks:		db 0
last_frame:	db 0
hf_src:		db 0
; Scroll steps per frame in test builds: 1 = fine (2 px / 1 line), 2 / 8 =
; CRTC fallback.
scroll_step_x:	db 2-FINE_X
scroll_step_y:	db 8-7*FINE_Y

	include "engine/hw.asm"
	include "engine/input.asm"
	include "engine/crtc.asm"
	include "engine/scroll.asm"
	include "engine/sprite.asm"
	include "engine/hud.asm"
	include "game/area.asm"
	include "engine/fdc.asm"
	include "palette.asm"




	if LANG_EN
	; language-specific data will go here (text, font)
	endif
	if LANG_GR
	endif

; --- boot: runs once before the game, in the second save-under area after
; the cassette buffer (the sprites overwrite it later; the binary covers it
; anyway, bank 5 is staged at &4000). Not the first one: the boot's first
; frame (view_restart) is drawn into buffer 0, saving under into it ---
code_resume = $
	org SAVE_AREA1+#800		; (CAS_BUFFER = SAVE_AREA1, 2K)
boot_start:

; Bank files loaded with the firmware before it is switched off: name,
; RAM config, load address.
bank_files:				; length, name, RAM config, address
	if SPR_BANKS&#10
	db 8,"SPR4.DAT",RAM_C4 : dw #4000
	endif
	if SPR_BANKS&#40
	db 8,"SPR6.DAT",RAM_C6 : dw #4000
	endif
	if SPR_FIXED_B5
	db 6,"B5.SPR",RAM_C5 : dw SPR_FIXED_B5_BASE	; top of bank 5 (the rest: mem_relocate)
	endif
	if SPR_AREAS
	db 11,"KITCHEN.SPR",RAM_C7 : dw #4000	; the first area (others: src/game/area.asm)
	endif
	db 0
CAS_IN_OPEN	equ #BC77
CAS_IN_DIRECT	equ #BC83
CAS_IN_CLOSE	equ #BC7A
CAS_BUFFER	equ #3000		; 2K, free until the game starts

KL_INIT_BACK	equ #BCCE

load_banks:
	; a binary started with RUN" runs with the cassette vectors: initialise
	; AMSDOS (ROM 7) again so that CAS IN reads from the disc
	ld c,7
	ld de,#0040
	ld hl,#ABFF
	call KL_INIT_BACK
	ld hl,bank_files
.next:	ld a,(hl)			; name length
	or a
	ret z
	inc hl
	push hl
	ld e,a
	ld d,0
	add hl,de
	ld c,(hl)			; RAM config
	ld b,GA_PORT
	out (c),c
	inc hl
	ld e,(hl)			; load address
	inc hl
	ld d,(hl)
	inc hl
	ld (lb_addr),de
	ex (sp),hl			; (sp) = next entry, HL = name
	ld b,a
	ld de,CAS_BUFFER
	call CAS_IN_OPEN
	ld hl,(lb_addr)
	call CAS_IN_DIRECT
	call CAS_IN_CLOSE
	ld bc,GA_PORT*256+RAM_C0
	out (c),c
	pop hl
	jr .next

start:
	call load_banks			; firmware still active
	di
	ld sp,STACK_TOP
	im 1
	ld bc,GA_PORT*256+GA_RMR_MODE0
	out (c),c			; mode 0, ROMs off (firmware no longer used)

	call mem_relocate		; data into banks 4/5, clear &4000-&FFFF
	call wait_vsync
	ld hl,palette_hw
	call set_palette

	if SERVICE			; the game's HUD (texts: game/service.asm)
	call hud_clear
	else
	ld de,0				; test pattern in the HUD sets: (phase 0,
	ld a,1				; buffer 0/1), (phase 1, ...)
	call hud_fill
	ld de,512
	ld a,1
	call hud_fill
	ld de,1024
	ld a,1+HUD_SHIFT1
	call hud_fill
	ld de,1536
	ld a,1+HUD_SHIFT1
	call hud_fill
	endif

	if TESTMODE
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
	else
	RAM RAM_C5			; (game code in bank 5)
	if SERVICE
	call service_init
	endif
	call actor_init
	xor a
	ld hl,0
	call scroll_set
	xor a
	call actor_tick			; place the camera
	RAM RAM_C0
	endif

	call view_restart
	jp boot_done

; Fill the 4 HUD rows at byte offset DE of the base &4000 page from the test
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
	add a,#40
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
	pop de
	push de
	add hl,de
	ex de,hl			; DE = dst
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

hud_pattern:
	incbin "testhud.bin"
; The game's HUD: all four sets in the background colour, a line under it.
; Needs RAM_C0.
hud_clear:
	ld hl,#4000			; line l of the sets: &4000 + l*&800, 2K
	ld b,8
.l:	push bc
	push hl
	ld d,h
	ld e,l
	inc de
	ld (hl),0			; (HUD_BG = pen 0)
	ld bc,#7FF
	ldir
	pop hl
	pop bc
	ld a,b
	dec a
	jr nz,.n
	push hl				; last line: row 3 of every set
	ld de,3*80
	add hl,de
	ld c,4
.s:	push hl
	ld b,80
.b:	ld (hl),(HUD_LINE&1)*#C0 | ((HUD_LINE>>1)&1)*#0C | ((HUD_LINE>>2)&1)*#30 | ((HUD_LINE>>3)&1)*#03
	inc hl
	djnz .b
	pop hl
	ld de,512
	add hl,de
	dec c
	jr nz,.s
	pop hl
	ret				; (that was the last line)
.n:	ld a,h
	add a,8
	ld h,a
	djnz .l
	ret

	include "engine/mem.asm"
boot_end:
	assert boot_end<=#4000,"boot code too big"
	print "boot code end: ",{hex}boot_end
	org code_resume

code_end:
	assert code_end<=CL_BUF,"code overlaps the sprite buffers"
	print "code end: ",{hex}code_end

; --- bank 5: map and tiles (staged at &4000 in base RAM) ---
	org #4000
bank5_start:
	if MAP_TEST
meta_data:				; 4 planes of 256 (tools/maps2asm.py), 1K
	incbin "test_meta.bin"		; aligned: the plane is picked with xor
tile_data:				; (aligned: draw_char)
	incbin "test_tiles.bin"
map_data:
	incbin "test_map.bin"
VARS_BLK = 0				; the big tables (game/vars.asm), after it
	repeat 4
	include "game/vars.asm"
VARS_BLK = VARS_BLK+1
	rend
	else
meta_data:				; level 1: each plane uses META_N bytes,
VARS_BLK = 0				; the rest of it holds a block of the big
	repeat 4			; tables (game/vars.asm)
	incbin "lvl1_meta.bin",VARS_BLK*256,META_N
	include "game/vars.asm"
	assert $<=meta_data+(VARS_BLK+1)*256,"no room for the tables in a metatile plane"
	ds meta_data+(VARS_BLK+1)*256-$,0
VARS_BLK = VARS_BLK+1
	rend
tile_data:
	incbin "lvl1_tiles.bin"
map_data:
	incbin "lvl1_map.bin"
	endif
	assert (meta_data&#3FF)==0

	if MAP_TEST==0			; tables, stations (tools/buildmap.py)
	include "lvl1_objs.asm"
	endif

	; game logic that runs with bank 5 mapped (game ticks: the map for
	; collisions; adding sprites in render, after buffer_sync)
	include "recipes.asm"		; dish times and prices (tools/recipes2asm.py)
	include "game/hudtext.asm"
	include "game/stamps.asm"
	include "game/actor.asm"
	include "game/customer.asm"
	include "game/staff.asm"
	include "game/items.asm"
	if SERVICE
	include "game/service.asm"
	endif
bank5_end:
	if SPR_FIXED_B5
	assert bank5_end<=SPR_FIXED_B5_BASE,"bank 5 overlaps its sprites (b5)"
	endif
	assert bank5_end<=#8000,"bank 5 full"
	assert bank5_end-bank5_start<=#4000,"bank 5 staging too big"
	print "bank 5 used: ",{hex}bank5_end-#4000
