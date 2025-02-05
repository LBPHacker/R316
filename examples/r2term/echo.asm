%include "common"

start:
	mov r16, 0x8000
	mov r17, 0x80FF
reset:
	st r16, r17
echo:
	mov r1, 0x1000
	st r1, r16
	mov r1, 0x200F
	st r1, r16
loop:
.read:
..wait:
	ld r3, r17
	cmp r3, 0x8000
	jne ..wait
..done:
	st r16, r17
.write:
..wait:
	ld r2, r16
	exh r3, r2, r2
	test r3, r3
	jz ..wait
..done:
	st r2, r16
	jmp loop
die:
	hlt
	jmp die
