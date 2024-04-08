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
echo:
	exh r1, 0x2002
	mov r1, r1, 0x1000
	st r1, r16
	mov r1, r1, 0x200F
	st r1, r16
loop:
.read:
..wait:
	ld r3, r16
	exh r3, r3, r3
	test r3, 0x0001
	jz ..wait
..done:
	exh r1, 0x2001
	mov r1, r1, 0x0000
	st r1, r16
.write:
..wait:
	ld r2, r16
	exh r3, r2, r2
	test r3, 0x0002
	jz ..wait
..done:
	exh r1, 0x2002
	mov r1, r1, r2
	st r1, r16
	jmp loop
die:
	hlt
	jmp die
