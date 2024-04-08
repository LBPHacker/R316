%include "common"

start:
	mov r16, 0x9000
reset:
	exh r1, 0x2001
	mov r1, r1, 0x0000
	st r1, r16
.wait:
	ld r1, r16
	exh r1, r1, r1
	test r1, 0x0001
	jz .wait
fill:
	exh r1, 0x2002
	mov r4, 0x200F
outer:
	mov r1, r1, 0x1000
	st r1, r16
	mov r1, r1, r4
	st r1, r16
	mov r3, 192
	mov r2, 0x20
loop:
	mov r1, r1, r2
	st r1, r16
	add r2, 1
	sub r3, 1
	jnz loop
	add r4, 5
	jmp outer
die:
	hlt
	jmp die
