; Add-on sprites drawn together with a figure, as separate sprites with their
; own depth key (sheets tray and bubble, fixed image b5 at the top of bank 5):
; Bill's tray with 1-3 plates, the customers' mood bubbles and Bill's
; bubble (a notepad while he takes an order).

TRAY_DY		equ 19		; tray top below Bill's top (at the hands)
BUBBLE_DY	equ -14		; bubble above a customer's head

MOOD_NONE	equ 0
MOOD_HAPPY	equ 1		; heart
MOOD_ANGRY	equ 2
MOOD_WAIT	equ 3		; ...
MOOD_FOOD	equ 4		; wants food
MOOD_PAY	equ 5		; wants to pay
MOOD_ORDER	equ 6		; Bill: taking an order

	ifndef TRAY_PLATES		; tests
TRAY_PLATES	equ 0
	endif
	ifndef TEST_BUBBLE
TEST_BUBBLE	equ 0
	endif

bill_plates:	db TRAY_PLATES	; plates carried, 0-3
bill_bubble:	db TEST_BUBBLE	; MOOD_* above Bill, 0 = none
tray_x:		dw 0		; Bill's sprite (left, top)
tray_y:		dw 0

; Bill's add-ons, right after his sprite: his bubble, and the tray (spr_z =
; his depth: drawn after him; hidden when he faces away, it is in front).
bill_items:
	ld a,(bill_bubble)
	or a
	jr z,tray_sprite
	ld de,(tray_x)
	ld bc,(tray_y)
	ld hl,(spr_z)
	push hl
	call bubble_a
	pop hl
	ld (spr_z),hl
tray_sprite:
	ld a,(bill_dir)
	ld b,a
	ld a,(bill_plates)
; A plates in front of a figure facing B, its sprite at tray_x, tray_y.
tray_ab:
	or a
	ret z
	dec a
	ld c,a
	ld a,b
	cp DIR_UP
	ret z
	or a				; rows: down 0, right 3, left 6
	jr z,.d
	dec a
	ld b,a
	add a,a
	add a,b
.d:	add a,c
	add a,a
	ld l,a
	ld h,0
	ld de,tray_frames
	add hl,de
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	ld de,(tray_x)
	push hl
	ld hl,(tray_y)
	ld bc,TRAY_DY
	add hl,bc
	ld b,h
	ld c,l
	pop hl
	jp sprites_add_z

; Mood bubble of a customer (IX = record, DE = left, BC = top): on top of all.
bubble_sprite:
	ld a,(ix+CU_MOOD)
	or a
	ret z
bubble_a:				; the same with A = MOOD_*
	dec a
	add a,a
	ld l,a
	ld h,0
	push de
	ld de,bubble_frames
	add hl,de
	pop de
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	push hl
	ld hl,BUBBLE_DY
	add hl,bc
	ld b,h
	ld c,l
	ld hl,#7FFF
	ld (spr_z),hl
	pop hl
	jp sprites_add_z
