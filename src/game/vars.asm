; The big tables of the game code in bank 5, in four blocks (VARS_BLK 0-3)
; that go into the free ends of the four metatile planes (meta_data, see
; src/main.asm): each plane uses only META_N of its 256 bytes.

	ifndef G_MAX			; (the file is included once per block)
G_MAX		equ 9		; groups at the same time (one per table)
GR_SIZE		equ 16		; group record (src/game/service.asm)
TRAIL_N		equ 32		; Bill's feet, recorded every 4 ticks he walks
SD_ENT		equ 6		; stamps (src/game/stamps.asm): x, y, hash
SDR_SIZE	equ 1+STAMP_MAX*SD_ENT
SDC_SIZE	equ 8		; x, y, hash, entry index, flags
HW_STATE	equ 10		; a hired one's record (src/game/waiter.asm): an
HW_WP		equ 11		; actor's (AC_*), then: point of the way (0.. n-1,
HW_PTR		equ 12		; n its end, #FF home), the way's index in the
HW_EX		equ 13		; store (hp_get2: n, points), its end (x, y
HW_EY		equ 15		; words), home
HW_HX		equ 17
HW_HY		equ 19
HW_SIZE		equ 21
	endif

	if VARS_BLK==0
	if SERVICE
groups:		ds G_MAX*GR_SIZE,0
tb_busy:	ds TABLE_COUNT,0	; group + 1 at the table, 0 = free
	endif
sd_erase:	ds STAMP_MAX*4,0	; rectangles (x, y) to erase
	endif
	if VARS_BLK==1
sd_rec:		ds 2*SDR_SIZE,0	; per buffer: count, stamps
	if SERVICE&&DEMO==0
ck_rec:		ds HW_SIZE,0	; the hired cook (src/game/cook.asm)
	endif
	if SERVICE
sv_menu:	db 0		; the menu at the pass is open
sv_mcur:	db 0		; its dish
sv_cook_t:	dw 0		; the kitchen: ticks left of the portion cooking
sv_cook_d:	db 0		; (its dish)
	endif
	endif
	if VARS_BLK==2
	if SERVICE
trail:		ds TRAIL_N*4,0	; x, y words
sv_stock:	ds 8,0		; portions of each dish (DISH_N) left today
sv_cook:	ds 8,0		; portions ordered at the pass, cooking
	endif
	if SERVICE&&DEMO==0
ck_carry:	ds 4,0		; as lib_carry: group + 1, dish, order, burnt
ck_stn:		db 0
ck_wait:	db 1
	endif
	endif
	if VARS_BLK==3
sd_cur:		ds STAMP_MAX*SDC_SIZE,0
	if SERVICE&&DEMO==0		; the hired waiter (src/game/waiter.asm)
wt_rec:		ds 10,0
wt_state:	db 0
wt_wp:		db 0
		ds HW_SIZE-12,0
	assert wt_state-wt_rec==HW_STATE&&wt_wp-wt_rec==HW_WP
wt_grp:		db 0		; group + 1 whose plates he carries (0: none)
wt_tab:		db 0
wt_plates:	db 0
	endif
	endif

	if SERVICE			; a few routines of the service in the
	include "game/vcode.asm"	; free ends too (they fit there)
	endif
