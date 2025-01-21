%include "common"

start:
	mov r1, 0xDEAD                     ; 4200DEAD
	mov r2, 0xBEEF                     ; 4400BEEF
	mulh r4, r1, r2                    ; 081F0002
	muls r4, r1, r2                    ; 881E0002
	mulx r4, r1, r2                    ; 881F0002
	mul r5, r1, r2                     ; 0A1E0002
