_Model "R3A.*"

%include "common"

start:
	mov r1, 20
	mov r2, 3
again:
	st r2, r1, 0
	st r2, r1, 1
	st r2, r1, 2
	st r2, r1, 3
	st r2, r1, 4
	st r2, r1, 5
	st r2, r1, 6
	add r1, 7
	jmp again
