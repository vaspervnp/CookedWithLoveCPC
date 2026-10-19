; Keyboard / joystick input (firmware off).

KEY_UP		equ 0		; bits of the value returned by read_input
KEY_DOWN	equ 1
KEY_LEFT	equ 2
KEY_RIGHT	equ 3
KEY_FIRE	equ 4

; Read one keyboard matrix line.
; In: A = line (0..9). Out: A = bits, 0 = pressed. Destroys BC.
read_key_line:
	ld bc,#F40E			; PSG register 14
	out (c),c
	ld bc,#F6C0			; select register
	out (c),c
	ld bc,#F600			; inactive
	out (c),c
	ld bc,#F792			; PPI port A input
	out (c),c
	ld b,#F6
	or #40				; PSG read + line
	out (c),a
	ld b,#F4
	in a,(c)
	ld bc,#F782			; PPI port A output
	out (c),c
	ld bc,#F600
	out (c),c
	ret

; Out: A = KEY_* bits set for pressed directions (cursor keys or joystick 0).
; Destroys BC, DE.
read_input:
	ld e,0
	ld a,0				; cursor up (0), right (1), down (2), copy (5)
	call read_key_line
	cpl
	ld d,a
	bit 0,d
	jr z,$+4
	set KEY_UP,e
	bit 1,d
	jr z,$+4
	set KEY_RIGHT,e
	bit 2,d
	jr z,$+4
	set KEY_DOWN,e
	ld a,1				; cursor left (0)
	call read_key_line
	cpl
	bit 0,a
	jr z,$+4
	set KEY_LEFT,e
	ld a,9				; joystick 0: up, down, left, right, fire1
	call read_key_line
	cpl
	and #1F
	ld d,a
	bit 0,d
	jr z,$+4
	set KEY_UP,e
	bit 1,d
	jr z,$+4
	set KEY_DOWN,e
	bit 2,d
	jr z,$+4
	set KEY_LEFT,e
	bit 3,d
	jr z,$+4
	set KEY_RIGHT,e
	bit 4,d
	jr z,$+4
	set KEY_FIRE,e
	ld a,e
	ret
