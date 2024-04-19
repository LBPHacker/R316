%include "common"

; %define block_w      8
; %define block_h      8
%define max_x        128
%define max_y        128
%define plotter_addr 0x8200

start:
	; mov r1, 30443
	; mov r2, 0
	; mov r3, 21985
	; mov r4, 0
	; jmp r29, gen_pixel
	; hlt

	mov r1, 0
	st r1, .block_y
	ld r1, fig_ty
	st r1, .block_fy
	ld r1, { fig_ty 1 + }
	st r1, { .block_fy 1 + }
.loop_y:
	ld r1, .block_y
	cmp r1, max_y
	je .loop_y_done
	mov r1, 0
	st r1, .block_x
	ld r1, fig_tx
	st r1, .block_fx
	ld r1, { fig_tx 1 + }
	st r1, { .block_fx 1 + }
.loop_x:
	ld r1, .block_x
	cmp r1, max_x
	je .loop_x_done

	ld r1, .block_fx
	ld r2, { .block_fx 1 + }
	ld r3, .block_fy
	ld r4, { .block_fy 1 + }
	jmp r29, gen_pixel
	ld r3, r1, .colors
	ld r1, .block_x
	ld r2, .block_y
	jmp r31, plot_pixel

	ld r1, .block_x
	add r1, 1
	st r1, .block_x
	ld r1, .block_fx
	ld r2, { .block_fx 1 + }
	ld r3, fig_d
	ld r4, { fig_d 1 + }
	add r1, r3
	adc r2, r4
	st r1, .block_fx
	st r2, { .block_fx 1 + }

		; ld r1, .block_y
		; add r1, 1
		; st r1, .block_y
		; ld r1, .block_fy
		; ld r2, { .block_fy 1 + }
		; ld r3, fig_d
		; ld r4, { fig_d 1 + }
		; add r1, r3
		; adc r2, r4
		; st r1, .block_fy
		; st r2, { .block_fy 1 + }

	jmp .loop_x
.loop_x_done:
	ld r1, .block_y
	add r1, 1
	st r1, .block_y
	ld r1, .block_fy
	ld r2, { .block_fy 1 + }
	ld r3, fig_d
	ld r4, { fig_d 1 + }
	add r1, r3
	adc r2, r4
	st r1, .block_fy
	st r2, { .block_fy 1 + }
	jmp .loop_y
.loop_y_done:
	

; 	mov r1, 0
; 	st r1, .block_y
; .loop_block_y:
; 	ld r1, .block_y
; 	cmp r1, max_y
; 	je .loop_block_y_done
; 	mov r1, 0
; 	st r1, .block_x
; .loop_block_x:
; 	ld r1, .block_x
; 	cmp r1, max_x
; 	je .loop_block_x_done
; 	ld r2, .block_y
; 	jmp r28, gen_block
; 	ld r1, .block_x
; 	add r1, block_w
; 	st r1, .block_x
; 	jmp .loop_block_x
; .loop_block_x_done:
; 	ld r1, .block_y
; 	add r1, block_h
; 	st r1, .block_y
; 	jmp .loop_block_y
; .loop_block_y_done:

.die:
	hlt
	jmp .die
.block_x:
	dw 0
.block_y:
	dw 0
.block_fx:
	dw 0, 0
.block_fy:
	dw 0, 0
.colors:
	dw 0x20000000
	dw 0x20000008
	dw 0x20000001
	dw 0x20000009
	dw 0x20000003
	dw 0x2000000B
	dw 0x20000002
	dw 0x2000000A
	dw 0x20000006
	dw 0x2000000E
	dw 0x20000004
	dw 0x2000000C
	dw 0x20000005
	dw 0x2000000D
	dw 0x20000007
	dw 0x2000000F

fig_d:
	dw 0x20000600, 0x20000000
fig_tx:
	dw 0x2000CCCD, 0x2000FFFD
fig_ty:
	dw 0x20008000, 0x2000FFFE

; ; * Generate an entire block_w * block_h block.
; ; * r1 in: horizontal position, [0, max_x / block_w) * block_w
; ; * r2 in: vertical position, [0, max_y / block_h) * block_h
; ; * r28 in: return address
; gen_block:
; 	st r1, .x
; 	st r1, .lx
; 	st r2, .y
; 	add r1, block_w
; 	add r2, block_h
; 	st r1, .hx
; 	st r2, .hy
; .loop_y:
; 	ld r1, .y
; 	ld r2, .hy
; 	cmp r1, r2
; 	je .loop_y_done
; 	ld r1, .lx
; 	st r1, .x
; .loop_x:
; 	ld r1, .x
; 	ld r2, .hx
; 	cmp r1, r2
; 	je .loop_x_done

; 	ld r1, .x
; 	ld r2, .y
; 	sub r1, 64
; 	sub r2, 64

; 	; jmp r29, gen_pixel
; 	; mov r3, r1

; 	ld r1, .x
; 	ld r2, .y
; 	mov r3, 6
; 	jmp r31, plot_pixel
; 	ld r1, .x
; 	add r1, 1
; 	st r1, .x
; 	jmp .loop_x
; .loop_x_done:
; 	ld r1, .y
; 	add r1, 1
; 	st r1, .y
; 	jmp .loop_y
; .loop_y_done:
; 	jmp r28
; .x:
; 	dw 0
; .y:
; 	dw 0
; .lx:
; 	dw 0
; .hx:
; 	dw 0
; .hy:
; 	dw 0

; * Generate a single pixel.
; * r2:r1 in: horizontal position
; * r4:r3 in: vertical position
; * r29 in: return address
; * r1 out: colour
gen_pixel:
	; hlt
	mov r13, r1
	mov r14, r2
	mov r15, r3
	mov r16, r4
	mov r5, 0 ; x2l
	mov r6, 0 ; x2h
	mov r7, 0 ; y2l
	mov r8, 0 ; y2h
	mov r9, 0 ; wl
	mov r10, 0 ; wh
	mov r21, 15
.loop:
	sub r11, r5, r7 ; xal
	sbb r12, r6, r8 ; xah
	add r11, r13    ; xl
	adc r12, r14    ; xh
	sub r9, r5      ; yal
	sbb r10, r6     ; yah
	sub r9, r7      ; ybl
	sbb r10, r8     ; ybh
	add r9, r15     ; yl
	adc r10, r16    ; yh

	mov r19, r9
	movf r20, r10
	jns .no_neg_r19
	xor r19, 0xFFFF
	xor r20, 0xFFFF
	add r19, 1
	adc r20, 0
.no_neg_r19:
	mov r1, r19
	mov r2, r19
	jmp r31, mul_16
	mov r6, r2
	mov r1, r20
	mov r2, r20
	jmp r31, mul_16
	mov r5, r1
	mov r1, r19
	mov r2, r20
	jmp r31, mul_16
	add r1, r1
	adc r2, r2
	add r2, r5
	add r7, r1, r6
	adc r8, r2, 0

	mov r17, r11
	movf r18, r12
	jns .no_neg_r17
	xor r17, 0xFFFF
	xor r18, 0xFFFF
	add r17, 1
	adc r18, 0
.no_neg_r17:
	mov r1, r17
	mov r2, r17
	jmp r31, mul_16
	mov r6, r2
	mov r1, r18
	mov r2, r18
	jmp r31, mul_16
	mov r5, r1
	mov r1, r17
	mov r2, r18
	jmp r31, mul_16
	add r1, r1
	adc r2, r2
	add r2, r5
	add r5, r1, r6
	adc r6, r2, 0

	add r0, r5, r7
	adc r20, r6, r8
	cmp r20, 4
	jb .loop_done ; annoying: cmp reg, imm yields inverted carries

	add r11, r9
	adc r12, r10
	jns .no_neg_r11
	xor r11, 0xFFFF
	xor r12, 0xFFFF
	add r11, 1
	adc r12, 0
.no_neg_r11:
	mov r1, r11
	mov r2, r11
	jmp r31, mul_16
	mov r20, r2
	mov r1, r12
	mov r2, r12
	jmp r31, mul_16
	mov r19, r1
	mov r1, r11
	mov r2, r12
	jmp r31, mul_16
	add r1, r1
	adc r2, r2
	add r2, r19
	add r9, r1, r20
	adc r10, r2, 0

	sub r21, 1
	jnz .loop
.loop_done:
	mov r1, r21
	jmp r29

; * Multiply two 16-bit unsigned integers.
; * r1 in: one multiplicand
; * r2 in: other multiplicand
; * r31 in: return address
; * r2:r1 out: product
; * Clobbers: r3, r4
%macro shift
	add r1, r1
	adc r2, r2
	shl r3, 1
%endmacro
%macro round
	jns .round _Macrounique
	add r1, r4
	adc r2, 0
.round _Macrounique:
%endmacro
%macro round2
	round
	shift
	round
%endmacro
%macro round3
	round2
	shift
	round2
%endmacro
mul_16:
	movf r3, r1
	mov r4, r2
	mov r1, 0
	mov r2, 0
	round3
	shift
	round3
	shift
	round3
	shift
	round3
	jmp r31
%unmacro round3
%unmacro round2
%unmacro round
%unmacro shift

; * Plot a single pixel.
; * r1 in: horizontal position, [0, max_x)
; * r2 in: vertical position, [0, max_y)
; * r3 in: colour, [0, 16)
; * r31 in: return address
plot_pixel:
	shl r2, 8
	or r1, r2                ; * Pack position.
	mov r2, plotter_addr     ; * Set plotter address.
	st r1, r2, r3            ; * Send plot command.
	jmp r31
