%include "common"

%define max_y 128

start:
	sub r1, max_y                      ; C216FF80
	sub r1, r1, max_y                  ; C216FF80
	add r1, { 0xFFFF 0 max_y - & }     ; C216FF80
	cmp r1, max_y                      ; C016FF80
	sub r0, r1, max_y                  ; C016FF80
	add r0, r1, { 0xFFFF 0 max_y - & } ; C016FF80
	sub r1, r2                         ; 82240001
	sub r1, r1, r2                     ; 82240001
	cmp r1, r2                         ; 80240001
	sub r0, r1, r2                     ; 80240001
