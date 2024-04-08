%include "common"

%macro sync
. _Peerlabel Sync _Macrounique:
	jy _Peerlabel Sync _Macrounique
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
%endmacro

start:
	mov r16, 0x9000
	exh r1, 0x2002
	mov r1, r1, 0x0061
	sync
loop:
	st r1, r16
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	jmp loop
die:
	hlt
	jmp die
