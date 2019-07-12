%include "common"

start:
	mov sp, 0x0800
	mov r1, 0x1D00
	mov [r1++], 0xC000
	mov [r1++], 0x8000
	; call test_loop ; LOOPCONTROL
	mov r0, data.compressed
	mov r1, 0x1C00
	mov r2, data.lut
	call print_16_to_6
	mov r0, 0x1F00
.input:
	cmp [r0], 0
	je .input
	mov [r1++], [r0]
	mov [r0], 0
	jmp .input

;test_loop: ; LOOPCONTROL
;	mov r4, 9 ; LOOPCONTROL
;	loop 8, .done, r0 ; LOOPCONTROL
;	add r4, 7 ; LOOPCONTROL
;.done: ; LOOPCONTROL
;	nop ; LOOPCONTROL
;	ret ; LOOPCONTROL

print_16_to_6:
	mov [--sp], r2
	ext [sp-1], [r0], 0xA0   ; extract #0
	ext [sp-2], [r0], 0xA6   ; extract #1
	add r2, [sp-1], [sp]     ; index #0
.loop:
	mov [r1++], [r2]         ; emit #0
	mov lo, [r0++]           ; shuffle #2
	scl [sp-1], [r0], 0xA4   ; extract #2
	add r2, [sp-2], [sp]     ; index #1
	mov [r1++], [r2]         ; emit #1
	nop
	ext [sp-3], [r0], 0xA8   ; extract #4
	add r2, [sp-1], [sp]     ; index #2
	mov [r1++], [r2]         ; emit #2
	ext [sp-2], [r0], 0xA2   ; extract #3
	jz .done
	add r2, [sp-2], [sp]     ; index #3
	mov [r1++], [r2]         ; emit #3
	mov lo, [r0++]           ; shuffle #5
	scl [sp-1], [r0], 0xA2   ; extract #5
	add r2, [sp-3], [sp]     ; index #4
	mov [r1++], [r2]         ; emit #4
	ext [sp-2], [r0], 0xA4   ; extract #6
	jz .done
	add r2, [sp-1], [sp]     ; index #5
	mov [r1++], [r2]         ; emit #5
	nop
	ext [sp-3], [r0++], 0xAA ; extract #7
	add r2, [sp-2], [sp]     ; index #6
	mov [r1++], [r2]         ; emit #6
	ext [sp-1], [r0], 0xA0   ; extract #0
	jz .done
	add r2, [sp-3], [sp]     ; index #7
	mov [r1++], [r2]         ; emit #7
	ext [sp-2], [r0], 0xA6   ; extract #1
	add r2, [sp-1], [sp]     ; index #0
	jmp .loop
.done:
	add sp, 1
	ret

data:
.lut:
org { .lut 0x40 + }
.compressed:
