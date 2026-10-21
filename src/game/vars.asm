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
	endif
	if VARS_BLK==2
	if SERVICE
trail:		ds TRAIL_N*4,0	; x, y words
	endif
	endif
	if VARS_BLK==3
sd_cur:		ds STAMP_MAX*SDC_SIZE,0
	endif
