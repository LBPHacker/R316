_Model "R3A.*"

%include "common"

start:
	mov r1, 0
	mov r2, 1
again:
	mov r3, r1
	mov r1, r2
	add r2, r3
	jnc again
die:
	hlt
	jmp die
