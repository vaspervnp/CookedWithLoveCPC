; The menu's recipes: the first 8 (DISH_N), then the ones bought in the
; evening (src/ovl/prep.asm), in the order of data/recipes/recipes.tsv, each
; for more money (RC_COST0, + RC_STEP each). In the morning after, the
; player picks the dish of the menu it replaces: the two change places in
; all the per-dish tables (tools/recipes2asm.py), the HUD icon and its ink,
; so the rest of the game knows only dishes 0-7. A new game undoes it.
; The data here, the code and the icons in the overlay (src/ovl/menu.asm).

RC_N		equ DISHES-DISH_N
RC_COST0	equ 100
RC_STEP		equ 25

rc_cnt:		db 0		; recipes put on the menu
rc_new:		db 0		; 1: bought, to put on the menu (DISH_N + rc_cnt)
rc_log:		ds RC_N,0	; the dish each one replaced

