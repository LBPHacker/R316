%include "common"

start:
	mov r2, 0x9F80
	mov r1, 0x0160
	st r1, r2, 0x42
	mov r1, 0x00E0
	st r1, r2, 0x43
	mov r1, 0x0000
	st r1, r2, 0x44
	mov r1, 0x000A
	st r1, r2, 0x45
	mov r1, 0x00F0
	st r1, r2, 0x46
	mov r1, 0xFFFF
	st r1, r2, 0x47
	mov r1, 32
	mov r3, 8
.clear:
	st r1, r2, 0x0C
	sub r3, 1
	jnz .clear
.again:
	ld r1, r2
	test r1, r1
	jz .again
	st r1, r2, 0x35
	jmp .again
