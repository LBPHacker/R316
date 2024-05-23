; * Very basic day of the week demo. Requires a terminal. See id:3112214

%include "common"

start:
                              ; * The R2 I/O adapter is very barebones. It
                              ;   consists of any number of expanders and a
                              ;   terminator. Each expander exposes a data
                              ;   register independent from all other expanders
                              ;   at a unique address, and in tandem with the
                              ;   terminator they also expose a control register
                              ;   for the entire R2 I/O bus. In theory, any
                              ;   number of such R2 I/O buses can be connected
                              ;   to the R3 I/O bus; these would act as separate
                              ;   attention request domains.
                              ; * The addresses of the control register and the
                              ;   per-expander data register can be chosen
                              ;   arbitrarily, as long as the data register's
                              ;   address is not 0x0000. This choice is coded
                              ;   into the expander hardware.
    mov r16, 0x8000           ; * I/O control register is at 0x8000.
                              ;   This is where the 16-bit address of the data
                              ;   register address of the leftmost I/O port
                              ;   requesting attention can be read from,
                              ;   prefixed with 0x2000.
                              ; * This register is read-only. When no port
                              ;   requests attention, it returns 0x20000000.
                              ; * Oops, this demo never even uses this register.
                              ;   Oh well, nice documentation effort regardless.
    mov r17, 0x9000           ; * Terminal data register is at 0x9000. This is
                              ;   where the state of the input side of the
                              ;   terminal's I/O expander can be read from and
                              ;   where the state of the output side thereof can
                              ;   be written to.
                              ; * This register is read-write. Reads mirror the
                              ;   state of the input side of the port exactly,
                              ;   and the state of the output side mirrors the
                              ;   state of writes exactly for one frame. If the
                              ;   register isn't written for a frame, the state
                              ;   of the output side is 0x20000000.
                              ; * Naturally, this means that R2 I/O states need
                              ;   to be interpreted from and reconstructed into
                              ;   the raw state values read from and written to
                              ;   this register.

    jmp r31, reset_term       ; * Reset terminal.
    mov r1, hello_str         ; * Print hello string.
    jmp r31, send_string
    jmp r29, initial_date     ; * Print initial date.

    jmp r29, refresh_output   ; * Run calculation.
.input_loop:
    mov r18, 0x20F0           ; * Blink colour: black on white.
..blink:
    mov r19, 0                ; * Timeout counter: initialized to 0.
...timeout:
    ld r1, r17                ; * Get terminal port state.
    exh r1, r1                ; * Extract upper half.
    test r1, 0x0001           ; * Check for attention request.
    jnz ..read                ; * Stop blinking if detected.
    add r19, 1                ; * Increment timeout counter.
    cmp 30, r19               ; * Go again if below 30.
    ja ...timeout
    mov r1, r18               ; * Set colour.
    jmp r31, send_char
    ld r1, input_position     ; * Draw blinker.
    jmp r30, refresh_input
    shr r1, r18, 4            ; * Flip colour in r18 via a few shifts.
    shl r18, 4
    or r18, r1
    or r18, 0x2000
    and r18, 0xF0FF
    jmp ..blink               ; * Blink again.
..read:
    jmp r31, reset_term       ; * Ask for keyboard buffer contents.
...wait:
    ld r1, r17                ; * Get terminal port state.
    exh r2, r1, r1            ; * Extract upper half.
    test r2, 0x0002           ; * Check for data frame.
    jz ...wait                ; * Stop blinking if detected.
    cmp '9', r1
    jb .letters               ; * Letters have higher codes than '9'.
    cmp '0', r1
    ja .input_loop            ; * Nonsense input, give up.
    sub r1, '0'               ; * Some key between '0' and '9' detected, update
    ld r2, input_position     ;   cell at input position accordingly.
    add r2, r2
    add r2, { input 1 + }
    st r1, r2
    mov r1, 0x200F
    jmp r31, send_char
    ld r1, input_position     ; * Draw blinker.
    jmp r30, refresh_input
    ld r3, input_position
    add r3, 1                 ; * Increment value.
    and r3, 7                 ; * Wrap value around if needed.
    st r3, input_position
.update_cell:
    mov r1, 0x200F
    jmp r31, send_char
    ld r1, input_position     ; * Draw blinker.
    jmp r30, refresh_input
    jmp r29, refresh_output   ; * Run calculation.
    jmp .input_loop
.letters:
    mov r4, 1
    cmp 'w', r1
    je ..incr                 ; * 'W' detected, increment.
    cmp 'd', r1
    je ..move                 ; * 'D' detected, go right.
    mov r4, 0xFFFF
    cmp 's', r1
    je ..incr                 ; * 'S' detected, decrement.
    cmp 'a', r1
    je ..move                 ; * 'A' detected, go left.
    jmp .input_loop           ; * Nonsense input, give up.
..incr:
    ld r2, input_position
    add r2, r2
    add r2, { input 1 + }
    ld r3, r2
    add r3, r4                ; * Increment or decrement value.
    cmp 9, r3                 ; * Check whether new value is in range.
    jb .input_loop
    cmp 0, r3
    ja .input_loop
    st r3, r2                 ; * Update cell if it is.
    jmp .update_cell
..move:
    ld r3, input_position
    mov r5, r3                ; * Back up old input position.
    add r3, r4                ; * Increment or decrement value.
    and r3, 7                 ; * Wrap value around if needed.
    st r3, input_position
    mov r1, 0x200F
    jmp r31, send_char
    mov r1, r5                ; * Restore old input position.
    jmp r30, refresh_input    ; * Draw blinker.
    jmp .input_loop


; * Print initial date.
; * r29 in: return address
; * Clobbers: r4, indirectly r1 to r3
initial_date:
    mov r4, 7
.loop:
    mov r1, r4
    jmp r30, refresh_input
    add r4, 0xFFFF
    jc .loop
    jmp r29


; * Print a single cell of the date.
; * r1 in: cell index, in [0, 8)
; * r30 in: return address
; * Clobbers: r1, r3, indirectly r2
refresh_input:
    add r3, r1, r1
    ld r1, r3, input          ; * Load position.
    jmp r31, send_char        ; * Send to terminal.
    ld r1, r3, { input 1 + }  ; * Load value.
    add r1, '0'               ; * Convert to a character code.
    mov r31, r30              ; * Tail call.
    jmp send_char             ; * Send to terminal.


; * Do calculation and output answer.
; * r29 in: return address
; * Clobbers: r1 to r5
refresh_output:
    ld r1, { input 1 + }      ; * Load the first two digits of the year into r2.
    shl r2, r1, 1
    shl r1, 3
    add r2, r1
    ld r1, { input 3 + }
    add r2, r1
    ld r1, { input 5 + }      ; * Load the second two digits of the year into r3.
    shl r3, r1, 1
    shl r1, 3
    add r3, r1
    ld r1, { input 7 + }
    add r3, r1
    ld r1, { input 9 + }      ; * Load the digits of the month into r4.
    shl r4, r1, 1
    shl r1, 3
    add r4, r1
    ld r1, { input 11 + }
    add r4, r1
    ld r1, { input 13 + }     ; * Load the digits of the day into r5.
    shl r5, r1, 1
    shl r1, 3
    add r5, r1
    ld r1, { input 15 + }
    add r5, r1
.range_check:
    cmp 12, r4                ; * Check whether the month value is in range.
    jb .invalid
    cmp 1, r4
    ja .invalid
    ld r1, r4, { .months_days 1 - }
    test r1, r1               ; * Month is not February: no adjustment needed.
    jns ..no_feb_adjust
    test r3, 3                ; * Year not a multiple of 4: not a leap year.
    jnz ..no_feb_adjust
    test r3, r3               ; * Year is not the end of a century: a leap year.
    jnz ..feb_adjust
    test r2, 3                ; * Century not a multiple of 4: not a leap year.
    jnz ..no_feb_adjust
..feb_adjust:
    add r1, 1
..no_feb_adjust:
    and r1, 0x7FFF            ; * Mask off February bit.
    cmp r1, r5                ; * Check whether the day value is in range.
    jb .invalid
    cmp 1, r5
    ja .invalid
    cmp 3, r4
    jna .no_decr_year34
    add r3, 0xFFFF
    jc .no_decr_year12
    mov r3, 99
    add r2, 0xFFFF
.no_decr_year12:
.no_decr_year34:
.total:
    shl r1, r2, 2             ; * Standard day of the week formula.
    add r3, r1
    shl r1, r2, 5
    add r3, r1
    shl r1, r2, 6
    add r3, r1
    shr r1, r3, 2
    add r3, r1
    sub r3, r2
    shr r1, r2, 2
    add r3, r1
    ld r1, r4, { .months_mod 1 - }
    add r3, r1
    add r3, r5
.reduce:
%macro reduce by
    cmp by, r3
    ja ..no_sub_ _Macrounique
    sub r3, by
..no_sub_ _Macrounique:
%endmacro
    reduce 7168               ; * Find remainder modulo 7.
    reduce 3584
    reduce 1792
    reduce 896
    reduce 448
    reduce 224
    reduce 112
    reduce 56
    reduce 28
    reduce 14
    reduce 7
%unmacro reduce
.print:
    mov r1, 0x1084            ; * Load position.
    jmp r31, send_char        ; * Send to terminal.
    shl r1, r3, 1
    add r1, r3
    shl r1, 2
    sub r1, r3                ; * At this point r1 = 11 * r3; a string begins in
    add r1, days_str          ;   the days_str every 11 cells.
    jmp r31, send_string
    jmp r29
.invalid:
    mov r3, 7
    jmp .print
.months_mod:
    dw 0x10006
    dw 0x10002
    dw 0x10001
    dw 0x10004
    dw 0x10006
    dw 0x10002
    dw 0x10004
    dw 0x10000
    dw 0x10003
    dw 0x10005
    dw 0x10001
    dw 0x10003
.months_days:
    dw 31
    dw { 28 0x8000 + }        ; * February bit set.
    dw 31
    dw 30
    dw 31
    dw 31
    dw 30
    dw 31
    dw 30
    dw 31
    dw 30
    dw 31


; * The 8 input cells. Each row holds a terminal cursor position, followed by
;   the current value of the cell, prefixed with 0x2000.
input:
    dw 0x1063, 0x20000002     ; * 2024-05-23
    dw 0x1064, 0x20000000
    dw 0x1065, 0x20000002
    dw 0x1066, 0x20000004
    dw 0x1068, 0x20000000
    dw 0x1069, 0x20000005
    dw 0x106B, 0x20000002
    dw 0x106C, 0x20000003
input_position:
    dw 0x10000                ; * The first digit of the year.
hello_str:
    dw 0x1000                 ; * Start printing at (0, 0).
    dw 0x200C                 ; * Bright red on black.
    dw "Day of the week "
    dw "calculator; "
    dw 0x200F,     "use "     ; * White on black.
    dw "WASD and 0-9 to "
    dw "navigate and to "
    dw "edit input"
    dw 0x1067, "-"
    dw 0x106A, "-"
    dw 0x1082, ">"
    dw 0x10000
days_str:
    dw 0x200A, "Monday   ", 0x10000
    dw 0x200A, "Tuesday  ", 0x10000
    dw 0x200A, "Wednesday", 0x10000
    dw 0x200A, "Thursday ", 0x10000
    dw 0x200A, "Friday   ", 0x10000
    dw 0x200A, "Saturday ", 0x10000
    dw 0x200A, "Sunday   ", 0x10000
    dw 0x2007, "(invalid)", 0x10000


; * Reset the terminal.
; * r17 in: terminal data register address
; * r31 in: return address
; * Clobbers: r1
reset_term:
    exh r1, 0x2001            ; * Upper half of R2 I/O state: attention request.
                              ;   The lower half doesn't matter.
    st r1, r17                ; * Send R2 I/O state to the terminal.
    jmp r31


; * Send a character to the terminal.
; * r1 in: character to send; it can also be a control code, such as colour or
;          cursor positioning codes
; * r17 in: terminal data register address
; * r31 in: return address
; * Clobbers: r1, r2
send_char:
    exh r2, 0x2002            ; * Upper half of R2 I/O state: data frame.
    mov r2, r2, r1            ; * Lower half of R2 I/O state: data value; the
                              ;   character itself.
    st r2, r17                ; * Send R2 I/O state to the terminal.
    jmp r31


; * Send a string to the terminal.
; * r1 in: address of string to send; must be terminated with a functionally
;          zero value, e.g. 0x10000; see send_char for info on what constitutes
;          a character
; * r17 in: terminal data register address
; * r31 in: return address
; * Clobbers: r1 to r3
send_string:
    mov r3, r1
    exh r2, 0x2002            ; * Upper half of R2 I/O state: data frame.
.loop:
    ld r1, r3                 ; * Load character.
    or r0, r1, 0              ; * Check if zero.
    jz .done                  ; * Exit if it is.
    mov r2, r2, r1            ; * Lower half of R2 I/O state: data value; the
                              ;   character itself.
    st r2, r17                ; * Send R2 I/O state to the terminal.
    add r3, 1
    jmp .loop
.done:
    jmp r31
