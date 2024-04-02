_Model "R3A.*"

%include "common"

start:
	mov r1, primes
	mov r2, 2
	mov r3, 4
outer:
	mov r4, primes
inner:
	ld r5, r4 ; read: mov r5, [r4]
	test r5, r5
	jz is_prime
	ld r6, r4, 1
	cmp r2, r6
	jb is_prime
	mov r8, r2
	shl r5, 8
	mov r7, 9
shift:
	mov r6, r8
	sub r6, r5
	jz is_composite
	jc shift_failed
	mov r8, r6
shift_failed:
	shr r5, 1
	sub r7, 1
	jnz shift
	add r4, 2
	jmp inner
is_prime:
	st r2, r1    ; read: mov [r1], r2
	st r3, r1, 1 ; read: mov [r1+1], r2
	add r1, 2
	st r0, r1
	mov r30, r2
is_composite:
	add r3, r2
	add r3, r2
	add r3, 1
	add r2, 1
	cmp r3, r2
	jb die
	jmp outer
die:
	hlt
	jmp die
primes:
	dw 0x20000000 ; annoying: you have to escape 00000000 to something with set bits in dw
	              ; because otherwise it ends up being read as 0000001F
