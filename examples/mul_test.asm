%include "common"

start:
	mov r1, 0xDEAD                     ; 4200DEAD
	mov r2, 0xBEEF                     ; 4400BEEF
	uml r4, r2, r1, r2                 ; 081E0002
