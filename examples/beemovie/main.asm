%include "common"

%define term_base 0x9F80
%eval term_input  term_base 0x00 +
%eval term_raw    term_base 0x04 +
%eval term_single term_base 0x05 +
%eval term_term   term_base 0x35 +
%eval term_hrange term_base 0x42 +
%eval term_vrange term_base 0x43 +
%eval term_cursor term_base 0x44 +
%eval term_nlchar term_base 0x45 +
%eval term_colour term_base 0x46 +

%define term_width 12
%define term_height 8
%define nlchar 10
%define lr r31
%define sp r30

%macro call thing
    jmp lr, thing
%endmacro
%macro ret
    jmp lr
%endmacro

start:
	call term_clear
	ld r7, data.length
	mov r1, 0
	mov r3, 0
	mov r4, data
	mov r5, 16
	mov r9, 1
.char_loop:
..pull_loop:
	cmp 16, r3
	je ...done
	sub r2, 16, r3
	cmp r2, r5
	jbe ...keep_r2
	mov r2, r5
...keep_r2:
	ld r8, r4
	test r9, r9
	jz ...take_low
	exh r8, r8, r0
...take_low:
	sub r5, r2
	shrs r8, r5
	subs r6, 16, r3
	subs r6, r2
	shls r8, r6
	ors r1, r8
	adds r3, r2
	jnz ..pull_loop
	mov r5, 16
	xor r9, 1
	jz ..pull_loop
	st r7, r4
	add r4, 1
	jmp ..pull_loop
...done:
	call huffman_decode
	shl r1, 1
	and r8, r2, 0xFF
	st r8, term_term
	shr r2, 8
	sub r3, r2
	sub r7, 1
	jnz .char_loop
.die:
	hlt
	jmp .die

term_clear:
    st r0, term_cursor
    mov r1, { term_width 1 - }
    shl r1, 5
    st r1, term_hrange
    mov r1, { term_height 1 - }
    shl r1, 5
    st r1, term_vrange
    mov r1, 0x0A
    st r1, term_colour
    mov r1, nlchar
    st r1, term_nlchar
    mov r1, ' '
    mov r7, 0
.loop:
    st r1, term_raw
    add r7, 1
    cmp r7, term_height
    jne .loop
    ret

%include "generated.asm"
