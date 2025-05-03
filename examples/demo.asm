%include "common"

; * There is not much of a calling convention used in this set of demos because
;   the individual demos are fairly simple and do not nest complex functionality
;   in a way that would warrant policing registers beyond about r8. The lifetime
;   of the values stored in higher registers is usually the entire demo, or a
;   non-nested subsection of the demo.
; * Thus, r1 through r8 are considered callee-saved, r9 through r29 are
;   unspecified, r30 is used as the stack pointer, and r31 as the link register.
; * Plain zero-terminated strings are used throughout the demos, which are just
;   sequences of one (mostly) ASCII character per cell, terminated with a 0
;   cell. Only the 16 LSB matter, which allows encoding the entire string,
;   including the terminating zero, with dw.
; * Some comments also refer to "terminal format" when describing values. For
;   the meaning behind this, consult the R3 manual.



%define term_base 0x9F80      ; * Terminal is expected to be mapped to this
                              ;   address. Macros aliasing individual registers
                              ;   follow. See the R3 manual for the meaning and
                              ;   function of these registers.
                              ; * TODO: encode as metadata
%eval term_input  term_base 0x00 +
%eval term_raw    term_base 0x04 +
%eval term_single term_base 0x05 +
%eval term_term   term_base 0x35 +
%eval term_hrange term_base 0x42 +
%eval term_vrange term_base 0x43 +
%eval term_cursor term_base 0x44 +
%eval term_nlchar term_base 0x45 +
%eval term_colour term_base 0x46 +

%define term_width 12         ; * Terminal size in characters. Different demos
%define term_height 8         ;   take this into account to varying extents;
                              ;   some work well on screens of different size,
                              ;   some do not.
%define nlchar 10             ; * Use ASCII '\n' as the newline character.

%define lr r31                ; * Designate registers for return addresses and
%define sp r30                ;   as the stack pointer. No registers have these
                              ;   fixed functions; we pick whatever
                              ;   register we want other than r0, if we need
                              ;   such functions at all.

%macro call thing             ; * There is no hardware support for functions,
    jmp lr, thing             ;   so we roll our own call and ret primitives.
%endmacro                     ;   We store the current address in lr in call and
%macro ret                    ;   jump as normal, then we jump back to lr in
    jmp lr                    ;   ret. This means that functions that call
%endmacro                     ;   other functions have to save lr somewhere
                              ;   (in this demo, the stack), but functions
                              ;   that do not (i.e. leaf functions) are free
                              ;   from this burden.
                              ; * This is the explanation behind the next pair
                              ;   of twin enter/leave macros: one pair for
                              ;   leaf functions, one pair for everything else.

                              ; * For clarity, enter/leave are primitives that
                              ;   create a stack "frame" for a function call:
                              ;   an area of memory where local variables of the
                              ;   function live, either all the time or only
                              ;   when register pressure forces them to memory.
%macro enter frame_size       ; * The non-leaf variant of enter saves lr at
    st lr, sp, 0xFFFF         ;   sp-1, then decreases sp by the requested frame
    sub sp, { frame_size 1 + } ;  size plus one, to account for lr.
%endmacro
%macro leave frame_size       ; * The non-leaf variant of leave restores sp,
    add sp, { frame_size 1 + } ;  then restores lr left by enter at (now) sp-1.
    ld lr, sp, 0xFFFF
%endmacro
%macro enter_leaf frame_size  ; * The leaf variant of enter does not need to
    sub sp, frame_size        ;   manage lr, so it simply decreases sp by the
%endmacro                     ;   requested frame size.
%macro leave_leaf frame_size  ; * Accordingly, the leaf variant of leave simply
    add sp, frame_size        ;   restores sp.
%endmacro
%macro ldl reg, index         ; * In both leaf and non-leaf stack frames, locals
    ld reg, sp, index         ;   (say, k of them, after invoking enter k or
%endmacro                     ;   enter_leaf k) are stored in the half-open
%macro stl reg, index         ;   range [sp, sp+k). These locals are accessed
    st reg, sp, index         ;   with these macros, where index is in the
%endmacro                     ;   half-open range [0, k).



; * Entry point: presents the demo menu in an infinite loop.
; * Sets up the stack. Does not return.
; * Has no inputs.
; * Has no outputs.
; * Only clobbers callee-saved registers.
start:
    mov sp, 0x800             ; * Target a 2K memory configuration.
                              ; * TODO: encode as metadata
                              ; * We would normally invoke enter here because
                              ;   this is a function prologue and this function
                              ;   is not a leaf function, but start is a
                              ;   "no-return" function: one that never returns.
                              ; * In hosted environments this is useful when
                              ;   the function requests program termination from
                              ;   the environment, but in free-standing
                              ;   environments, it is typical of the top-level
                              ;   infinite loop. start is of the latter kind.
.again:
    mov r1, .demos            ; * Load menu descriptor and hand control over to
    call menu                 ;   menu. menu returns only when the selected menu
                              ;   item has also returned.
    jmp .again                ; * Loop indefinitely.
.demos:
    dw "Select demo", 0
    dw fibonacci , "fibonacci" , 0
    dw primes    , "primes"    , 0
    dw dayofweek , "dayofweek" , 0
    dw mandelbrot, "mandelbrot", 0
    dw 0



; * Generic menu: displays a menu title and allows selecting one of at most 9
;   menu items by pressing the corresponding number key from 1 to 9.
; * A function associated with the menu item is called when the item is
;   selected, then menu returns.
; * Care should be taken so that the menu title and all menu items fit on the
;   terminal's screen.
; * Inputs:
;   * r1: pointer to menu descriptor,
;     * the descriptor has the following structure:
;       * plain zero-terminated string: menu title,
;       * at most 9 menu items,
;         * any items after the 9th one are ignored,
;       * one zero cell where the function pointer of the next menu item
;         would otherwise be,
;     * menu items have the following structure:
;       * pointer to a function: executed when the menu item is selected,
;         * this must not be zero,
;       * plain zero-terminated string: item title.
; * Has no outputs.
; * Only clobbers callee-saved registers.
%define max_items 9           ; * menu supports at most 9 items.
%eval frame_size    max_items 1 + ; * The function pointers will be stored on
                                  ;   the stack, along with 1 other value.
%eval menuinfo_size max_items 0 + ; * These two locals can share frame indices
%eval menuinfo_addr max_items 0 + ;   because their lifetimes do not overlap.
menu:
    enter frame_size          ; * Create stack frame.
    stl r1, menuinfo_addr     ; * Back up menu descriptor address before calling
                              ;   term_clear because it is in a callee-saved
                              ;   register.
    call term_clear           ; * Clear screen.
    st r0, term_cursor        ; * Move cursor to the top-left corner.
    ldl r1, menuinfo_addr     ; * Restore menu descriptor address. r1 now also
                              ;   points to the menu title, and is thus the
    call term_print           ;   parameter to term_print. Print menu title.
                              ; * term_print returns in r1 a pointer to just
                              ;   after the plain zero-terminated string it was
                              ;   passed in r1, so r1 now holds a pointer to the
                              ;   array of menu items in the menu descriptor.
    mov r2, nlchar            ; * Print two newlines.
    st r2, term_term
    st r2, term_term
.print_menu_items:
    stl r0, menuinfo_size     ; * Print and count menu items starting from 0.
..loop:
    ldl r3, menuinfo_size     ; * If we have already seen 9 menu items, do not
    cmp r3, 9                 ;   even bother with the next one.
    je ..done
    ld r2, r1                 ; * Load the function pointer associated with the
    test r2, r2               ;   next menu item. If it is zero, we are done.
    jz ..done
    stl r2, r3                ; * Store function pointer on the stack,
    add r3, 1                 ;   increment count,
    stl r3, menuinfo_size     ;   store it.
    add r3, '0'               ; * Print the number key that will be associated
    st r3, term_term          ;   with the item,
    mov r2, ':'
    st r2, term_term
    add r1, 1                 ;   then skip over the function pointer so r1
    call term_print           ;   points to the item title, to print it.
                              ; * r1 now points to the next menu item.
    mov r2, nlchar            ; * Print a newline after the item title.
    st r2, term_term
    jmp ..loop
..done:
.get_char:
    ldl r5, menuinfo_size     ; * Grab a character from the keyboard.
    add r5, 2                 ; * Same colour as the text, with a space
    shl r5, 5                 ;   character blinking under the last menu item.
    mov r2, 30
    mov r3, 0xA0
    mov r4, ' '
    call term_get_char_blink
    sub r1, '0'               ; * If it is between 1 and the number of menu
    cmp r1, 1                 ;   items (in ASCII), proceed. If not, go
                              ;   again.
    ja .get_char              ; * TODO: inverted carry, this is jb
    ldl r3, menuinfo_size
    cmp r1, r3
    ja .get_char
    sub r1, 1
    ldl r1, r1                ; * Load function pointer associated with the
                              ;   selected menu item.
    leave frame_size          ; * Destroy stack frame.
    jmp r1                    ; * Jump to the function pointer associated with
                              ;   the selected menu item; this is a tail call.
%undef menuinfo_size
%undef menuinfo_addr
%undef frame_size
%undef max_items



; * Get keyboard character: waits until a key is pressed on the terminal's
;   keyboard.
; * Has no inputs.
; * Outputs:
;   * r1: the keyboard code of the key pressed; never 0,
; * Only clobbers callee-saved registers.
term_get_char:
    ld r1, term_input         ; * Get the keyboard buffer of the terminal. If
    test r1, r1               ;   it holds zero, that means no key has been
    jz term_get_char          ;   pressed since the last time; go again.
    ret                       ; * Otherwise, return what we got.



; * Get keyboard character while blinking: Waits until a key is pressed on the
;   terminal's keyboard, while also drawing a character at a given position
;   using a given colour.
; * The character is redrawn and its foreground and background colours are
;   swapped at a given interval.
; * Inputs:
;   * r2: blink interval (in some unspecified unit of time),
;   * r3: colour to print character with in terminal format,
;   * r4: character to print in terminal format,
;   * r5: position to print character at in terminal format,
; * Outputs:
;   * r1: the keyboard code of the key pressed; never 0,
; * Only clobbers callee-saved registers.
; * TODO: fix jank register usage (inputs should be r1..r4 instead of r2..r5)
term_get_char_blink:
    mov r8, r2                ; * Start countdown.
.loop:
    ld r1, term_input         ; * Same idea as in term_get_char, except do
    test r1, r1               ;   not immediately go again if a key has not yet
    jnz .done                 ;   been pressed.
    sub r8, 1                 ; * Advance countdown. If it has not reached zero,
    jnz .loop                 ;   go again.
    st r3, term_colour        ; * Set character colour.
    shl r8, r3, 4             ; * Swap the first and second 4 bits of the
    shr r3, 4                 ;   character colour value, essentially swapping
    or r3, r8                 ;   foreground and background colours. The
                              ;   terminal cares only about the 8 LSB.
    st r5, term_cursor        ; * Set cursor position,
    st r4, term_single        ;   then print the character with the colour
                              ;   before the swapping. It will be printed with
                              ;   swapped colours the next time around.
    mov r8, r2                ; * Restart countdown.
    jmp .loop
.done:
    ret



; * Print a plain zero-terminated string, leaving formatting up to the terminal
;   (which will not perform proper text wrapping, see term_print_wrapped).
; * Inputs:
;   * r1: pointer to the string to print.
; * Outputs:
;   * r1: pointer to just after the string, including its zero termination.
; * Only clobbers callee-saved registers.
term_print:
    ld r2, r1                 ; * Load character,
    add r1, 1                 ;   increment pointer.
    test r2, r2               ; * If the character terminates the string, exit.
    jz .done
    st r2, term_term          ; * Otherwise, print the character and go again.
    jmp term_print
.done:
    ret



; * Print a plain zero-terminated string, wrapping lines at word boundaries such
;   that no word is ever broken in the best case. Still break words up that are
;   too wide to fit in a single line even on their own.
; * Word boundaries are where ASCII space characters are adjacent to any other
;   character. Newline characters in the string are treated like any non-space
;   character, i.e. are effectively ignored.
; * Consecutive space characters are printed as a single space character.
; * This function assumes that the screen's printing range is set to the entire
;   surface of the screen, as defined by term_width and term_height.
; * Inputs:
;   * r1: pointer to the string to print.
; * Outputs:
;   * r1: pointer to just after the string, including its zero termination.
; * Only clobbers callee-saved registers.
term_print_wrapped:
    mov r3, 0                 ; * Current horizontal cursor position is 0.
.next_word:
    mov r5, 0                 ; * Note that we have not found a space before the
                              ;   current word yet.
.find_space_end:              ; * Find the end of the current (possibly empty)
                              ;   run of spaces.
    ld r2, r1                 ; * Load the next character, exit if it is the
    test r2, r2               ;   zero termination.
    jz ..done
    cmp r2, ' '               ; * If it is not a space, we have reached the end
    jne ..done                ;   of the current run of spaces.
    add r1, 1                 ; * If it is, consume it and note that we 
    mov r5, 1                 ;   have found a space before the current word.
    jmp .find_space_end       ; * Go again.
..done:
    mov r6, r1                ; * Remember where the run of spaces ended and the
                              ;   word begins.
.find_word_end:               ; * Find the end of the current (possibly empty)
                              ;   run of non-spaces.
    ld r2, r1                 ; * Load the next character, exit if it is the
    test r2, r2               ;   zero termination.
    jz ..done
    cmp r2, ' '               ; * If it a space, we have reached the end of the
    je ..done                 ;   current run of non-spaces.
    add r1, 1                 ; * If it is now, consume it.
    jmp .find_word_end        ; * Go again.
..done:
    cmp r3, 0                 ; * If we have not yet printed anything in this
    je .print_word            ;   line, do not have to bother with spaces and
                              ;   just print the word immediately with
                              ;   potentially a space before it.
    sub r2, r1, r6            ; * Calculate the length of the word,
    add r2, r3                ;   add to it the horizontal cursor position,
    add r2, r5                ;   and an extra 1 if we have to also print a
                              ;   space before the word.
    cmp term_width, r2        ; * If this sum ends up being at most as large as
    jae .print_word           ;   the screen is wide, just print the word with
                              ;   potentially a space before it.
    mov r5, 0                 ; * If the sum is larger than the screen is wide,
                              ;   give up on printing the space because the word
                              ;   will be printed on the next line anyway.
    mov r2, nlchar            ; * Print a newline,
    st r2, term_term
    mov r3, 0                 ;   reset current horizontal cursor position.
.print_word:                  ; * Print the word with potentially a space before
    test r5, r5               ;   it. 
    jz ..skip_space
    mov r2, ' '               ; * Potentially print the space,
    st r2, term_term
    add r3, 1                 ;   adjust current horizontal cursor position.
..skip_space:
    add r3, r1                ; * Adjust current horizontal cursor position,
    sub r3, r6                ;   taking the length of the word into account.
..loop:
    ld r2, r6                 ; * Load the next character of the word
    st r2, term_term          ;   and print it.
    add r6, 1                 ; * Increment word pointer, compare it against the
    cmp r6, r1                ;   current input pointer, loop until they are the
    jne ..loop                ;   same.
    ld r2, r1                 ; * Check if we have reached the end of the
    test r2, r2               ;   string, return if we have.
    jnz .next_word
    ret



; * Reset and clear terminal screen to pure black.
; * The printing range is set to the entire surface of the screen. The cursor is
;   moved to the top left corner. Colour is set to green on black. The newline
;   character is configured.
; * Has no inputs.
; * Has no outputs.
; * Only clobbers callee-saved registers.
term_clear:
    st r0, term_cursor        ; * Move cursor to top left corner.
    mov r1, { term_width 1 - } ; * Encode the ordered closed range [0,
    shl r1, 5                  ;   term_width - 1] in terminal format, then pass
    st r1, term_hrange         ;   it to the terminal.
    mov r1, { term_height 1 - } ; * Encode the ordered closed range [0,
    shl r1, 5                   ;   term_height - 1] in terminal format, then
    st r1, term_vrange          ;   pass it to the terminal.
    mov r1, 0x0A              ; * Set colour to green on black.
    st r1, term_colour
    mov r1, nlchar            ; * Configure newline character.
    st r1, term_nlchar
    mov r1, ' '
    mov r2, 0                 ; * Do as many full-row scrollprints as there are
.loop:                        ;   screen lines, clearing the screen.
    st r1, term_raw
    add r2, 1
    cmp r2, term_height
    jne .loop
    ret



; * Fibonacci demo.
; * Has no inputs.
; * Has no outputs.
; * Only clobbers callee-saved registers.
%define frame_size 0
fibonacci:
    enter frame_size          ; * Create an empty frame so functions can be
                              ;   called.
    call term_clear           ; * Clear terminal, print info.
    mov r1, .message
    call term_print_wrapped
    mov r2, nlchar            ; * Print two newlines.
    st r2, term_term
    st r2, term_term
    mov r2, 8                 ; * Sequence items will be printed with varying
                              ;   colours because the individual items can be
                              ;   very long and extend over multiple lines.
                              ; * The colours will cycle between 8 to 15 (bright
                              ;   foreground on black background).
    st r2, term_colour        ; * Set colour to the first one of these so the
                              ;   first, hardcoded sequence item can be printed.
    mov r1, .f0               ; * Print first sequence item.
    call term_print
    mov r1, scratch           ; * Two variable-length integers are used to track
                              ;   progress. They are encoded as little-endian
                              ;   arrays of base-10000 digits.
                              ; * The scratch space is divided into two
                              ;   subsequences: even-indexed cells (counting
                              ;   from the base address scratch) will hold one
                              ;   of the integers, while odd-indexed cells the
                              ;   other.
    mov r3, 1                 ; * r3 will track the length of both arrays, which
                              ;   will always be the same, as the smaller number
                              ;   is never smaller by more than a factor of 2.
    st r0, r1                 ; * They are only a single digit each initially.
    mov r2, 1                 ;   One is initialized to 0, while the other to 1.
    st r2, r1, 1
    mov r9, 1                 ; * r9 will track the colour to print the numbers
.loop:                        ;   with, in the half-open range [0, 8). Since
                              ;   colour 0 (colour 8) has already been used
                              ;   above, it starts counting from 1 (colour 9).
    and r2, r9, 7             ; * The [0, 8) range is mapped to bright colours,
    or r2, 8                  ;   by simply offsetting them by 8. Then this
    st r2, term_colour        ;   colour is sent to the terminal.
%macro print_digit            ; * This macro prints the digit in r7 only if
    or r0, r2, r7             ;   either it is not zero, or some non-zero digit
    jz ...skip_digit_ _Macrounique ; has already been printed, as recorded by
    add r8, r7, '0'           ;   r2. If the macro does decide to print, it
    st r8, term_term          ;   records this in r2. This implements ripple
    mov r2, 1                 ;   blanking.
...skip_digit_ _Macrounique:
%endmacro
%macro print_group            ; * This macro prints a base-10000 digit in r4 as
                              ;   a group of four digits. It relies on
                              ;   print_digit to do this with ripple blanking
                              ;   enabled.
    mulh r6, r4, 5243         ; * r4 is divided into r6 by 100. (i * 5243) >> 19
    shr r6, 3                 ;   is equal to floor(i / 100) for all i in the
                              ;   half-open range [0, 10000).
                              ; * This gets us the "high half" of the base-10000
                              ;   digit, which is in the half-open range
                              ;   [0, 100), essentially a base-100 digit.
    mulh r7, r6, 6554         ; * r6 is divided into r7 by 10. (i * 6554) >> 16
                              ;   is equal to floor(i / 10) for all i in the
                              ;   half-open range [0, 100).
                              ; * This gets us the "high half" of the base-100
                              ;   digit, which is in the half-open range
                              ;   [0, 10), essentially a normal decimal digit.
    print_digit               ; * Which we then print.
    mul r7, r7, 10            ; * We extract the lower half of the base-100
    sub r7, r6, r7            ;   digit by calculating the remainder of the
    print_digit               ;   last division, and print it.
    mul r6, r6, 100           ; * We extract the lower half of the base-10000
    sub r4, r6                ;   digit by calculating the remainder of the
                              ;   second to last division.
    mulh r7, r4, 6554         ; * We then use the same method as above to print
    print_digit               ;   the last two digits.
    mul r7, r7, 10
    sub r7, r4, r7
    print_digit
%endmacro
..print_index:
    mov r8, 'F'               ; * Print the index of the sequence item.
    st r8, term_term
    mov r4, r9                ; * Print the number part of the index with
    mov r2, 0                 ;   print_group. This limits the printout to 10000
    print_group               ;   items, but this should be enough. Note that we
                              ;   set r2 to 0 to enable ripple blanking.
    mov r8, '='
    st r8, term_term
    add r5, r1, r3            ; * Start outputting the larger number of the two,
    add r5, r3                ;   stored at odd-indexed offsets from scratch. We
                              ;   start from the end of the active scratch space
                              ;   because the digit arrays are little-endian.
    mov r2, 0                 ; * Again, set r2 to 0 to enable ripple blanking.
..print_loop:
    sub r5, 2                 ; * Position r5 to the next (really, previous)
    ld r4, r5, 1              ;   digit and load it,
    print_group               ;   then print it.
%unmacro print_digit
%unmacro print_group
    cmp r5, r1                ; * If we are back at the first digit, exit the
    jne ..print_loop          ;   loop.
    mov r2, nlchar            ; * Print a newline after the number. Note that
    st r2, term_term          ;   the number may span many lines.
    mov r5, r1                ; * Once this is done, start adding the smaller
    add r4, r5, r3            ;   number to the larger number. r5 points to the
    add r4, r3                ;   digit arrays, while r4 points where they end.
    mov r2, 0                 ; * r2 will handle the cross-digit carry.
..component_loop:
    ld r6, r5                 ; * Load one digit from both numbers.
    ld r7, r5, 1
    st r7, r5                 ; * Copy the larger number's digit over to where
                              ;   the smaller number's was, eventually copying
                              ;   the entire larger number to where the smaller
                              ;   number was.
    add r6, r2                ; * Add carry from the previous iteration to the
                              ;   larger number's digit,
    add r6, r7                ;   then add the smaller number's digit to it.
                              ; * No adc is used because none of these additions
                              ;   can overflow: we sum two numbers in the
                              ;   half-open range [0, 10000), plus a potential
                              ;   carry that is either 0 or 1, so the largest
                              ;   possible sum is 19999.
    add r0, r6, { 0x10000 10000 - } ; * We do however want to be able to easily
                              ;   detect overflowing into the next base-10000
                              ;   digit, so we bridge the gap between 10000 and
                              ;   0x10000, forcing any value in r6 larger than
                              ;   or equal to 10000 to set the carry flag.
    adc r2, r0, r0            ; * We then store this carry flag in r2.
    jz ...no_overflow         ; * If overflow was detected,
    sub r6, 10000             ;   subtract 10000 from r6.
...no_overflow:
    st r6, r5, 1              ; * Then store r6 as a digit of the larger number.
    add r5, 2                 ; * Repeat this until r5 reaches r4, i.e. until
    cmp r5, r4                ;   we reach the end of the digit arrays.
    jne ..component_loop
    test r2, r2               ; * If the last addition produced a carry,
    jz ..no_extend            ;   we must extend the digit arrays.
    add r3, 1                 ; * The new digit of the smaller number is
    st r0, r5                 ;   definitely 0, since it is just the old last
    st r2, r5, 1              ;   digit of the larger number.
..no_extend:
    add r9, 1                 ; * We then cycle the colour used to print the
    cmp 2500, r9              ;   digits. The size of the scratch space (about
    jb .done                  ;   256 cells) limits us to about 2500 sequence
                              ;   items, so we must exit when we reach that
                              ;   many, but we keep this a secret from users.
    ld r5, term_input         ; * Exit if requested by a key press.
    test r5, r5
    jz .loop
    jmp .done_early
.done:
    mov r1, 0x0A              ; * Set colour to green on black.
    st r1, term_colour
    mov r1, .theend
    call term_print_wrapped   ; * Congratulate users if they get this far.
    add r5, 0xE3
    mov r2, 30
    mov r3, 0xA0
    mov r4, ' '
    call term_get_char_blink
.done_early:
    leave frame_size
    ret
.message:
    dw "This will loop until you press a key", 0
.theend:
    dw 10, "You have reached the end, wow! Press any key", 0
.f0:
    dw "F0=0", nlchar, 0
%undef frame_size



; * Day of the week demo.
; * Has no inputs.
; * Has no outputs.
; * Only clobbers callee-saved registers.
%define frame_size 1
%define input_cursor 0
dayofweek:
    enter frame_size
.init:
    call term_clear           ; * Clear the terminal, display usage help at the
    mov r1, .info             ;   top, then draw the rest of the user interface
    call term_print_wrapped   ;   minus the digits of the date.
    mov r1, 0x0F
    st r1, term_colour
    mov r1, 0xE0
    st r1, term_cursor
    mov r2, '>'
    st r2, term_single
    mov r1, 0xA5
    st r1, term_cursor
    mov r2, '-'
    st r2, term_single
    mov r1, 0xA8
    st r1, term_cursor
    st r2, term_single
    stl r0, input_cursor      ; * The input cursor is in the range 0 to 7
                              ;   inclusive, and records which date digit the
                              ;   cursor is above.
    mov r1, 8                 ; * Print digits one by one for the first time.
..loop:                       ;   In each iteration, position the cursor, then
    ld r2, r1, { .positions 1 - } ; print the stored digit value. This value is
    add r2, 0xA0              ;   remembered across runs.
    st r2, term_cursor
    ld r2, r1, { .digits 1 - }
    add r2, '0'
    st r2, term_single
    sub r1, 1
    jnz ..loop
    jmp .print_day            ; * Then print the day for the first time. This
                              ;   will be done any time the date is changed.
.loop:
    mov r6, 0                 ; * Record no change yet to the output; see later.
    mov r2, 30                ; * The main loop consists of asking for a
    ldl r5, input_cursor      ;   character and blinking in the meantime, with
    ld r4, r5, .digits        ;   the cursor above a specific digit. This
    ld r5, r5, .positions     ;   requires loading the digit first.
    add r5, 0xA0
    add r4, '0'
    mov r3, 0xF0
    call term_get_char_blink  ; * Then off blinking we go.
    ldl r3, input_cursor
    cmp 's', r1               ; * There is a small search tree type deal going
    jb ..bigger_than_s        ;   on here to quickly select the correct piece of
    ja ..smaller_than_s       ;   code to execute based on the input.
..down:                       ; * If we get 's', we decrease the digit under the
    ld r1, r3, .digits        ;   cursor and do not move the cursor.
    cmp 0, r1                 ; * Only do this if the digit is above 0. If it is
    je .loop                  ;   not, go back to the main loop.
    sub r1, 1
    st r1, r3, .digits
    mov r6, 1                 ; * This changes the day so update the printout.
    jmp .print_changed        ;   r6 set to indicate this.
..bigger_than_s:
    cmp 'x', r1               ; * More search tree action.
    je .done
    cmp 'w', r1
    je ..up
    jmp .loop
..smaller_than_s:
    cmp 'a', r1               ; * More search tree action.
    je ..left
    cmp 'd', r1
    je ..right
    cmp '0', r1               ; * Check if the input is maybe between '0' and
    ja .loop                  ;   '9'.
    cmp '9', r1
    jb .loop
..digit:                      ; * At this point we know that the input is
    sub r1, '0'               ;   between '0' and '9'; interpret it as a digit
    st r1, r3, .digits        ;   and update the digit under the cursor with it,
    mov r6, 1                 ;   then fall through into ..right to move the
..right:                      ;   cursor.
    add r5, r3, 1             ; * Move cursor to the right,
    and r5, 7                 ;   wrap around if out of bounds.
    stl r5, input_cursor
    jmp .print_changed        ; * This does not change the day but we still need
                              ;   to redraw the digit we were blinking above.
                              ;   r6 not set.
                              ; * The old input cursor is still in r3 so
                              ;   .print_changed updates the digit we just left
                              ;   behind.
..left:
    sub r5, r3, 1             ; * This branch is the same as ..right but
    and r5, 7                 ;   moves the cursor left. Apply the same
    stl r5, input_cursor      ;   wraparound logic.
    jmp .print_changed
..up:
    ld r1, r3, .digits        ; * This branch is the same as ..down but
    cmp 9, r1                 ;   increases the digit if it is below 9.
    je .loop
    add r1, 1
    st r1, r3, .digits
    mov r6, 1
.print_changed:               ; * Print only the digit that was changed.
    mov r1, 0x0F
    st r1, term_colour
    ld r4, r3, .digits
    ld r3, r3, .positions
    add r3, 0xA0
    st r3, term_cursor
    add r4, '0'
    st r4, term_single
    test r6, r6               ; * Go on if the change also affects the output,
    jz .loop                  ;   go back to the main loop otherwise.
.print_day:
    ld r2,   .digits          ; * Load the four pair of digits and interpret
    ld r1, { .digits 1 + }    ;   them as four numbers in the range 0 to 99.
    mul r2, r2, 10            ; * The mul's are aligned to be executed on every
    ld r3, { .digits 2 + }    ;   5th cycle because every 5th core is an M core.
    ld r7, { .digits 3 + }    ;   ld's are 2 cycles each.
    mul r3, r3, 10            ; * This avoids stalls, though admittedly, they
    ld r4, { .digits 4 + }    ;   would not be that terrible to incur in this
    ld r8, { .digits 5 + }    ;   demo.
    mul r4, r4, 10
    ld r5, { .digits 6 + }
    ld r9, { .digits 7 + }
    mul r5, r5, 10
    add r2, r1                ; * Load the first two digits of the year into r2.
    add r3, r7                ; * Load the second two digits of the year into r3.
    add r4, r8                ; * Load the digits of the month into r4.
    add r5, r9                ; * Load the digits of the day into r5.
..range_check:
    cmp 12, r4                ; * Check whether the month value is in range.
    jb ..invalid
    cmp 1, r4
    ja ..invalid
    ld r1, r4, { .months_days 1 - }
    test r1, r1               ; * Month is not February: no adjustment needed.
    jns ..no_feb_adjust       ;   The sign bit acts as the February bit to
                              ;   indicate this.
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
    jb ..invalid
    cmp 1, r5
    ja ..invalid
    cmp 3, r4
    jna ..no_decr_year34      ; * This is just the day of the week formula from
                              ;   this point onward, as outlined in id:2443356:
                              ;
                              ;     int dayofweek(int d, int m, int y) {
                              ;       int t[] = { 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 };
                              ;       y -= m < 3;
                              ;       return (y + y / 4 - y / 100 + y / 400 + t[m - 1] + d) % 7;
                              ;     }
                              ;
    add r3, 0xFFFF            ; * Decrease the year (across two numbers in the
    jc ..no_decr_year12       ;   range 0 to 99) by one if the month is below
    mov r3, 99                ;   3 (March).
    add r2, 0xFFFF
    jc ..no_overflow_year12
    mov r2, 99
..no_overflow_year12:
..no_decr_year12:
..no_decr_year34:
..total:
    mul r1, r2, 100           ; * Interpret the two pairs of 0-99 numbers as a
    add r3, r1                ;   single 0-9999 number to calculate y.
    shr r1, r3, 2             ; * Calculate y / 4.
    add r3, r1                ; * Start totalling in r3; y + y / 4 so far.
    sub r3, r2                ; * r2 effectively already holds y / 100, subtract
                              ;   that.
    shr r1, r2, 2             ; * Calculate y / 400
    add r3, r1                ;   and add it.
    ld r1, r4, { .months_mod 1 - } ; * Load the appropriate offset for the
    add r3, r1                ;   month and add it.
    add r3, r5                ; * Add the day.
..reduce:
                              ; * Calculate remainder modulo 7.
    mulh r4, r3, 9363         ; * This mulh calculates sum / 7 and is correct in
                              ;   the range that r3 can take values from.
    mul r4, r4, 7             ; * Calculate sum / 7 * 7,
    sub r3, r4                ;   then subtract it from sum, getting sum % 7.
    jmp ..print               ; * Print the appropriate day index.
..invalid:
    mov r3, 7                 ; * The 7th string in the day array says invalid.
..print:
    mul r3, r3, 11            ; * Day strings are 11 cells apart, select the
    mov r1, 0xE2              ;   correct one and print it with its own colour.
    st r1, term_cursor
    ld r1, r3, .days
    st r1, term_colour
    add r1, r3, { .days 1 + } ; * Load the appropriate string for the day and
    call term_print           ;   print it.
    jmp .loop
.done:
    leave frame_size
    ret
.months_mod:
    dw 6, 2, 1, 4, 6, 2, 4, 0, 3, 5, 1, 3
.months_days:
    dw 31, { 28 0x8000 + }, 31, 30, 31, 31, 30, 31, 30, 31, 30, 31
.info:
    dw "Use WASD to navigate, 0-9 to edit, or X to exit", 0
.positions:
    dw 1, 2, 3, 4, 6, 7, 9, 10
.digits:
    dw 1, 9, 5, 7, 0, 3, 0, 6
.days:
    dw 0x0F, "Monday   ", 0
    dw 0x09, "Tuesday  ", 0
    dw 0x0A, "Wednesday", 0
    dw 0x0B, "Thursday ", 0
    dw 0x0C, "Friday   ", 0
    dw 0x0D, "Saturday ", 0
    dw 0x0E, "Sunday   ", 0
    dw 0x07, "(invalid)", 0
%undef input_cursor
%undef frame_size



%define frame_size 0
primes:                       ; * Sorry folks, no documentedion for this yet.
    enter frame_size
    call term_clear
    mov r1, fibonacci.message
    call term_print_wrapped
    mov r2, nlchar
    st r2, term_term
    st r2, term_term
    mov r2, 8
    st r2, term_colour
    mov r1, .p1
    call term_print
    mov r2, 9
    st r2, term_colour
    mov r1, .p2
    call term_print
    mov r2, 10
    st r2, term_colour
    mov r1, .p3
    call term_print
    mov r2, 9
.init_loop:
    ld r3, r2, { .seed 1 - }
    st r3, r2, { scratch 1 - }
    sub r2, 1
    jnz .init_loop
    mov r1, { scratch 9 + }
    mov r10, 1
    mov r11, 0
    mov r12, scratch
    mov r9, 3
    mov r13, 0
.loop:
    ld r2, r13, .mod30
    add r13, 1
    and r13, 7
    add r10, r2
    adc r11, 0
    cmp r10, 31
    ld r3, r12, 3
    mulh r2, r3, r3
    mul r4, r3, r3
    sub r0, r10, r4
    sbb r0, r11, r2
    jnae ..no_incr_r12
    add r12, 3
    mov r5, 0
    mov r2, 32
    mov r18, 0
..inv_loop:
    shl r18, 1
    shl r5, 1
    or r5, 1
    sub r4, r5, r3
    jc ...discard
    mov r5, r4
    or r18, 1
...discard:
    cmp r2, 17
    jne ...no_save_r18
    mov r19, r18
...no_save_r18:
    sub r2, 1
    jnz ..inv_loop
    add r18, 1
    adc r19, 0
    st r18, r12, 1
    st r19, r12, 2
..no_incr_r12:
    mov r5, scratch
..divisor_loop:
    cmp r5, r12
    ja ...done
    ld r4, r5
    ld r15, r5, 1
    ld r16, r5, 2
    mulh r18, r15, r10
    mul r19, r16, r11
    mulh r21, r16, r10
    mul r20, r16, r10
    add r18, r20
    adc r19, r21
    mulh r21, r15, r11
    mul r20, r15, r11
    add r18, r20
    adc r19, r21
    mulh r18, r19, r4
    mul r17, r19, r4
    sub r0, r17, r10
    sbb r0, r18, r11
    je ..not_prime
    add r5, 3
    jmp ..divisor_loop
...done:
    cmp r1, { scratch 300 + } ; 100 primes, 100th definitely bigger than the square root of the 10k-th
    je ..no_save
    st r10, r1
    add r1, 3
..no_save:
    and r2, r9, 7
    or r2, 8
    st r2, term_colour
%macro print_digit
    or r0, r2, r7
    jz ...skip_digit_ _Macrounique
    add r8, r7, '0'
    st r8, term_term
    mov r2, 1
...skip_digit_ _Macrounique:
%endmacro
%macro print_group
    mulh r6, r4, 5243
    shr r6, 3
    mulh r7, r6, 6554
    print_digit
    mul r7, r7, 10
    sub r7, r6, r7
    print_digit
    mul r6, r6, 100
    sub r4, r6
    mulh r7, r4, 6554
    print_digit
    mul r7, r7, 10
    sub r7, r4, r7
    print_digit
%endmacro
..print_index:
    mov r8, 'P'
    st r8, term_term
    add r4, r9, 1
    mov r2, 0
    print_group
    mov r8, '='
    st r8, term_term
..print_prime:
    mov r18, r10
    mov r19, 0
    mov r3, r11
...reduce_r3:
    test r3, r3
    jz ....done
    sub r3, 1
    add r18, 5536
    adc r3, 0
    add r19, 6
    jmp ...reduce_r3
....done:
    cmp 40000, r18
    jnbe ...no_40k
    sub r18, 40000
    add r19, 4
...no_40k:
    cmp 20000, r18
    jnbe ...no_20k
    sub r18, 20000
    add r19, 2
...no_20k:
    cmp 10000, r18
    jnbe ...no_10k
    sub r18, 10000
    add r19, 1
...no_10k:
    mov r2, 0
    mov r4, r19
    print_group
    mov r4, r18
    print_group
%unmacro print_digit
%unmacro print_group
    mov r2, nlchar
    st r2, term_term
    add r9, 1
    cmp 9999, r9
    jb .done
..not_prime:
    ld r5, term_input
    test r5, r5
    jz .loop
    jmp .done_early
.done:
    mov r1, 0x0A              ; * Set colour to green on black.
    st r1, term_colour
    mov r1, fibonacci.theend
    call term_print_wrapped   ; * Congratulate users if they get this far.
    add r5, 0xE3
    mov r2, 30
    mov r3, 0xA0
    mov r4, ' '
    call term_get_char_blink
.done_early:
    leave frame_size
    ret
.p1:
    dw "P1=2", nlchar, 0
.p2:
    dw "P2=3", nlchar, 0
.p3:
    dw "P3=5", nlchar, 0
.mod30:
    dw 6, 4, 2, 4, 2, 4, 6, 2
.seed:
    dw 2, 0x0000, 0x8000
    dw 3, 0x0000, 0x0000
    dw 5, 0x0000, 0x0000
%undef frame_size



%define block_order 4
%eval image_size_x term_width 8 *
%eval image_size_y term_height 8 *
%eval block_size 1 block_order <<
%eval block_mask block_size 1 -
%define frame_size 8
mandelbrot:                   ; * Sorry folks, no documentedion for this yet.
    enter frame_size
    call term_clear
    mov r1, .message
    call term_print_wrapped
    mov r1, .message2
    call term_print_wrapped
.select_preset:
    mov r2, 30
    mov r3, 0xA0
    mov r4, ' '
    mov r5, 0xCA
    call term_get_char_blink
    cmp '7', r1
    jb .select_preset
    cmp '1', r1
    ja .select_preset
    sub r1, '1'
    sub r3, .presets, r1
    shl r1, 3
    add r3, r1
    call .init_terminal
    mov r5, 7
    mov r1, .smc_ptrs
.smc_loop:
    ld r4, r3
    add r3, 1
..next:
    ld r2, r1
    add r1, 1
    test r2, r2
    jz ..done
    ld r6, r2
    mov r6, r6, r4
    st r6, r2
    jmp ..next
..done:
    sub r5, 1
    jnz .smc_loop
    call mb_colors.init
    stl r0, 2
.next_row:
    stl r0, 1
.next_block:
    ldl r1, 1
    ldl r2, 2
    call mb_block
    ldl r1, 1
    add r1, block_size
    cmp r1, image_size_x
    stl r1, 1
    jne .next_block
    ldl r1, 2
    add r1, block_size
    cmp r1, image_size_y
    stl r1, 2
    jne .next_row
    call term_get_char
    leave frame_size
    ret
.init_terminal:
    ld r0, { term_base 0x00 + }
    mov r1, { term_width 1 - }
    shl r1, 5
    st r1, { term_base 0x42 + }
    mov r1, { term_height 1 - }
    shl r1, 5
    st r1, { term_base 0x43 + }
    mov r1, 0x8020
    mov r2, 0
.loop:
    st r1, { term_base 0x06 + }
    add r2, 1
    cmp r2, term_height
    jne .loop
    ret
.presets:
    dw 0x5495, 0xFFFB, 0x9576, 0xFFEF, 0x2000, 0x0000, 19
    dw 0x89D7, 0xFFF4, 0xF8A5, 0x0006, 0x0200, 0x0000, 31
    dw 0x7B4B, 0x0005, 0xD8DF, 0x0006, 0x0100, 0x0000, 34
    dw 0x2489, 0xFFFE, 0x517C, 0xFFF1, 0x0080, 0x0000, 37
    dw 0xCFE4, 0x0006, 0x4B22, 0x0003, 0x0020, 0x0000, 43
    dw 0x30FA, 0x0000, 0x83B1, 0xFFF2, 0x0010, 0x0000, 46
    dw 0x0129, 0x0006, 0x864A, 0x0009, 0x0008, 0x0000, 49
.smc_ptrs:
    dw mb_block.get_map.smc_init_xl_0
    dw 0
    dw mb_block.get_map.smc_init_xh_0
    dw 0
    dw mb_block.get_map.smc_init_yl_0
    dw 0
    dw mb_block.get_map.smc_init_yh_0
    dw 0
    dw mb_block.get_map.smc_incr_l_0
    dw mb_block.get_map.smc_incr_l_1
    dw mb_block.get_map.smc_incr_l_2
    dw mb_block.get_map.smc_incr_l_3
    dw 0
    dw mb_block.get_map.smc_incr_h_0
    dw mb_block.get_map.smc_incr_h_1
    dw 0
    dw mb_colors.init.smc_max_iter_0
    dw mb_get_point.loop.smc_max_iter_1
    dw 0
.message:
    dw "This demo is really slow!", 0
.message2:
    dw "Pick preset from 1 to 7; preset 1 is fastest, 7 is slowest", 0
%undef frame_size



; * r1: ix
; * r2: iy
; * clobbers: r3 to r9
; * r31: return
%eval mb_map_size block_size block_size *
%define mb_map scratch
%define mb_queue { mb_map mb_map_size + }
%eval mb_queue_size block_size 4 *
%eval mb_queue_mask mb_queue_size 1 -
%define mb_block_stack 16
; 1: ix
; 2: iy
; 3: x1
; 4: y1
; 7: dx
; 8: dy
; 9: px (get_map)
; 10: py (get_map)
; 11: map index (get_map)
; 14: lr (get_map)
mb_block:
    enter mb_block_stack
    stl r1, 1
    stl r2, 2
    mov r8, 0
.clear_map:
    st r0, r8, { mb_map 0 + }
    st r0, r8, { mb_map 1 + }
    st r0, r8, { mb_map 2 + }
    st r0, r8, { mb_map 3 + }
    st r0, r8, { mb_map 4 + }
    st r0, r8, { mb_map 5 + }
    st r0, r8, { mb_map 6 + }
    st r0, r8, { mb_map 7 + }
    add r8, 8
    cmp r8, mb_map_size
    jne .clear_map
    stl r0, 4
.next_row:
    stl r0, 3
.next_pixel:
    ldl r9, 3
    ldl r10, 4
    shl r4, r10, block_order
    or r4, r9
    ld r3, r4, mb_map
    test r3, r3
    js .fill
    call .get_map.unchecked
    mov r27, r8
    mov r1, 0x0000 ; diroffx
    mov r2, 0xFFFF ; diroffy
..loop:
    ; check left
    add r9, r2
    sub r10, r1
    call .get_map
    cmp r27, r8
    jne ..left_bad
    mov r3, r1
    mov r1, r2
    sub r2, 0, r3
    jmp ..found_dir
..left_bad:
    add r10, r1
    sub r9, r2
    ; check forward
    add r9, r1
    add r10, r2
    call .get_map
    cmp r27, r8
    je ..found_dir
    sub r10, r2
    sub r9, r1
    ; check right
    sub r9, r2
    add r10, r1
    call .get_map
    cmp r27, r8
    je ..right_good
    sub r10, r1
    add r9, r2
..right_good:
    mov r3, r2
    mov r2, r1
    sub r1, 0, r3
..found_dir:
    ldl r3, 3
    cmp r9, r3
    jne ..loop
    ldl r3, 4
    cmp r10, r3
    jne ..loop
    cmp r1, 0x0000
    jne ..loop
    cmp r2, 0xFFFF
    jne ..loop
    ldl r9, 3
    ldl r10, 4
    shl r3, r10, block_order
    or r3, r9
    mov r28, 0xA000
    st r28, r3, mb_map
    or r3, 0x2000
    st r3, mb_queue
    mov r7, 0
    mov r8, 1
..queue_pop:
    ld r3, r7, mb_queue
    shr r10, r3, block_order
    and r10, block_mask
    and r9, r3, block_mask
    ldl r1, 1
    add r11, r9, r1
    ldl r1, 2
    add r12, r10, r1
    shl r12, 8
    or r12, r11
    sub r3, r27, 0x2000
    ld r11, r3, mb_colors
    st r12, r11, { term_base 0x60 + }
%macro check xoff, yoff, src
    add r9, xoff
    add r10, yoff
    shl r12, r10, block_order
    or r12, r9
    ld r11, r12, mb_map
    test r11, r11
    js ..skip_neighbour_ _Macrounique
    jz ..do_neighbour_ _Macrounique
    cmp r11, r27
    jne ..skip_neighbour_ _Macrounique
..do_neighbour_ _Macrounique:
    st r28, r12, mb_map
    or r12, src
    st r12, r8, mb_queue
    add r8, 1
    and r8, mb_queue_mask
..skip_neighbour_ _Macrounique:
    sub r10, yoff
    sub r9, xoff
%endmacro
    ld r4, r7, mb_queue
    test r4, 0x8000
    jnz ..skip_xp1
    cmp r9, block_mask
    je ..skip_xp1
    check 0x0001, 0x0000, 0x2000
..skip_xp1:
    test r4, 0x4000
    jnz ..skip_yp1
    cmp r10, block_mask
    je ..skip_yp1
    check 0x0000, 0x0001, 0x1000
..skip_yp1:
    test r4, 0x2000
    jnz ..skip_xm1
    cmp r9, 0
    je ..skip_xm1
    check 0xFFFF, 0x0000, 0x8000
..skip_xm1:
    test r4, 0x1000
    jnz ..skip_ym1
    cmp r10, 0
    je ..skip_ym1
    check 0x0000, 0xFFFF, 0x4000
..skip_ym1:
%unmacro check
    add r7, 1
    and r7, mb_queue_mask
    cmp r7, r8
    jne ..queue_pop
.fill:
    ldl r1, 3
    add r1, 1
    cmp r1, block_size
    stl r1, 3
    jne .next_pixel
    ldl r1, 4
    add r1, 1
    cmp r1, block_size
    stl r1, 4
    jne .next_row
    leave mb_block_stack
    ret
; * r9: block-local x
; * r10: block-local y
; * r8: out, pixel value
.get_map:
    mov r8, 0x4000
    test r9, r9
    js ..done
    test r10, r10
    js ..done
    cmp r9, block_size
    jbe ..done ; inverted carry, this is jae
    cmp r10, block_size
    jbe ..done ; inverted carry, this is jae
..unchecked:
    stl r1, 7
    stl r2, 8
    stl r9, 9
    stl r10, 10
    shl r8, r10, block_order
    or r8, r9
    stl r8, 11
    ld r8, r8, mb_map
    test r8, r8
    jnz ..done
    ldl r8, 1
    add r9, r8
    ldl r8, 2
    add r10, r8
..smc_incr_l_0:
    mulh r2, r9, 0xDEAD
..smc_incr_l_1:
    mul r1, r9, 0xDEAD
..smc_incr_h_0:
    mul r8, r9, 0xDEAD
    add r2, r8
..smc_init_xl_0:
    add r1, 0xDEAD
..smc_init_xh_0:
    adc r2, 0xDEAD
..smc_incr_l_2:
    mulh r4, r10, 0xDEAD
..smc_incr_l_3:
    mul r3, r10, 0xDEAD
..smc_incr_h_1:
    mul r8, r10, 0xDEAD
    add r4, r8
..smc_init_yl_0:
    add r3, 0xDEAD
..smc_init_yh_0:
    adc r4, 0xDEAD
    stl lr, 14
    call mb_get_point
    ldl lr, 14
    ldl r9, 9
    ldl r1, 1
    add r9, r1
    ldl r10, 10
    ldl r1, 2
    add r10, r1
    shl r10, 8
    or r10, r9
    ld r9, r8, mb_colors
    st r10, r9, { term_base 0x60 + }
    or r8, 0x2000
    ldl r9, 11
    st r8, r9, mb_map
    ldl r10, 10
    ldl r9, 9
    ldl r2, 8
    ldl r1, 7
..done:
    ret

mb_colors:
    dw 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    dw 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    dw 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    dw 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    dw 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    dw 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
.proto:
    dw 1, 11, 3, 10, 2, 14, 6, 12, 4, 13, 5, 9
.init:
    mov r1, 0
    mov r3, 0
..loop:
    ld r2, r3, .proto
    st r2, r1, mb_colors
    add r3, 1
    cmp r3, 12
    jne ..skip_wrap
    mov r3, 0
..skip_wrap:
    add r1, 1
..smc_max_iter_0:
    cmp 0xDEAD, r1
    jne ..loop
    st r0, r1, mb_colors
    ret

; * r1: x0l
; * r2: x0h
; * r3: y0l
; * r4: y0h
; * r8: iter, out
; * clobbers: r9 to r24
mb_get_point:
    mov r8, 0 ; iter
    cmp r2, 0x40
    jge .done
    cmp r4, 0x40
    jge .done
    cmp r2, 0xFFC0
    jl .done
    cmp r4, 0xFFC0
    jl .done
    mov r9, 0 ; x2l
    mov r10, 0 ; x2h
    mov r11, 0 ; y2l
    mov r12, 0 ; y2h
    mov r13, 0 ; wl
    mov r14, 0 ; wh
.loop:
    sub r15, r9, r11 ; l(x2 - y2) NOTE r15+
    sbb r16, r10, r12 ; h(x2 - y2) NOTE r16+
    add r15, r15, r1 ; l(x2 - y2 + x0) = xl
    adc r16, r16, r2 ; h(x2 - y2 + x0) = xh
    sub r17, r13, r9 ; l(w - x2) NOTE r17+
    mulh r19, r15, r15 ; h(xl * xl) * B NOTE r19+
    mul r20, r16, r16 ; l(xh * xh) * B^2 NOTE r20+
    sbb r18, r14, r10 ; h(w - x2) NOTE r18+
    sub r17, r17, r11 ; l(w - x2 - y2)
    sbb r18, r18, r12 ; h(w - x2 - y2)
    mulx r22, r15, r16 ; h(xh * xl) * B^2 NOTE r22+
    mul r21, r15, r16 ; l(xh * xl) * B NOTE r21+
    add r17, r17, r3 ; l(w - x2 - y2 + y0) = yl
    adc r18, r18, r4 ; h(w - x2 - y2 + y0) = yh
    add r19, r21 ; (h(xl * xl) + l(xh * xl)) * B
    mulh r23, r17, r17 ; h(yl * yl) * B NOTE r23+
    mul r24, r18, r18 ; l(yh * yh) * B^2 NOTE r24+
    adc r20, r22 ; (l(xh * xh) + h(xh * xl)) * B ^ 2
    add r19, r21 ; (h(xl * xl) + 2 * l(xh * xl)) * B = x2l' << 4 NOTE r21-
    adc r20, r22 ; (l(xh * xh) + 2 * h(xh * xl)) * B ^ 2 = x2h' << 4 NOTE r22-
    mulx r22, r17, r18 ; h(yh * yl) * B^22 NOTE r22+
    mul r21, r17, r18 ; l(yh * yl) * BB NOTE r21+
    add r23, r21 ; (h(yl * yl) + l(yh * yl)) * B
    adc r24, r22 ; (l(yh * yh) + h(yh * yl)) * B ^ 2
    add r23, r21 ; (h(yl * yl) + 2 * l(yh * yl)) * B = y2l' << 4 NOTE r21-
    adc r24, r22 ; (l(yh * yh) + 2 * h(yh * yl)) * B ^ 2 = y2h' << 4 NOTE r22-
    add r0, r19, r23
    adc r22, r20, r24 ; NOTE r22+
    cmp r22, 0x400 ; NOTE r22-
    jbe .done ; inverted carry, this is jae
    shr r9, r19, 4 ; NOTE r19-
    shr r10, r20, 4 ; x2h'
    shl r20, r20, 12
    add r15, r17 ; l(x + y) NOTE r17-
    adc r16, r18 ; h(x + y) NOTE r18-
    mulh r21, r15, r15 ; h(l(x + y) * l(x + y)) * B NOTE r21+
    mul r22, r16, r16 ; l(h(x + y) * h(x + y)) * B^2 NOTE r22+
    or r9, r20 ; x2l' NOTE r20-
    shr r11, r23, 4 ;  NOTE r23-
    shr r12, r24, 4 ; y2h'
    mulx r20, r15, r16 ; h(h(x + y) * l(x + y)) * B^2 NOTE r20+
    mul r19, r15, r16 ; l(h(x + y) * l(x + y)) * B NOTE r15- r16- r19+
    shl r24, r24, 12
    or r11, r24 ; y2l' NOTE r24-
    add r21, r19 ; (h(l(x + y) * l(x + y)) + l(h(x + y) * l(x + y))) * B
    adc r22, r20 ; (l(h(x + y) * h(x + y)) + h(h(x + y) * l(x + y))) * B ^ 2
    add r21, r19 ; (h(l(x + y) * l(x + y)) + 2 * l(h(x + y) * l(x + y))) * B = wl' << 4 NOTE r19-
    adc r22, r20 ; (l(h(x + y) * h(x + y)) + 2 * h(h(x + y) * l(x + y))) * B ^ 2 = wh' << 4 NOTE r20-
    shr r13, r21, 4 ; NOTE r21-
    shr r14, r22, 4 ; wh'
    shl r22, r22, 12
    or r13, r22 ; wl' NOTE r22-
    add r8, 1
..smc_max_iter_1:
    cmp 0xDEAD, r8
    jne .loop
.done:
    ret



scratch:
    org { scratch mb_map_size + }
    dw 0
