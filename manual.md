# R3 reference manual

*This is a computer. All [crafthackership](https://dwarffortresswiki.org/) is of the highest quality. On the item is an image of the Subframe Inside™ logo. This object menaces with spikes of questionable time management.*

*TODO: save link*

Note: ordinal numbers throughout this manual start at 0, yielding odd-looking constructs such as *0th* and *bit 0* (the LSB). For clarity's sake the English word *first* is never used to refer to ordinals.

Note: Instruction spellings and expansions reflect the state of integration with [TPTASM](https://github.com/LBPHacker/tptasm).

## Features

 - **data path**: quasi-32-bit, works with *almost every* 32-bit value
 - **registers**: 32-bit words, 31 general purpose read/write, 1 read-only *almost zero*
 - **memory**: any amount of 32-bit words from 128 to 8192 (8K), in increments of 128
 - **ALU**: 16-bit addition, logic, and shifting, optionally 16×16-bit *multiplication* with 32-bit results
 - ***spatial unrolling***: many CPU cycles per frame depending on configuration
 - **input and output**: memory-mapped, control lines are exposed, *wait cycles* can be injected

## Quasi-32-bit

Turns out that FILT's 2 MSBs can be used after all, although their handling is somewhat finicky: any ctype that is one of `0x00000000`, `0x40000000`, `0x80000000`, or `0xC0000000` (which this manual refers to as *dead values*) is treated as zero by some mechanics of the game, and so they get misinterpreted as the infamous temperature-dependent `0x0000001F` value.

The bottom line is that these values cannot be read or written by the computer. Reading them results in the aforementioned value, while writing them results in a value that also has the the `0x20000000` bit set in it. This behaviour is referred to as working with *almost every* 32-bit value.

## Registers

There are 31 general purpose read/write registers `r1` to `r31`, and also one read-only register `r0` that always reads `0x20000000`, referred to as *almost zero* because from the ALU's perspective, which only considers the 16 LSBs, it is indeed zero. This read-only register can be used as the destination operand to an operation, in which case the output produced by the operation is discarded.

## ALU

The ALU operates on the 16 LSBs of registers and on 16-bit immediate values. It is capable of addition and subtraction, with or without carry and borrow, bitwise OR, AND, and XOR, and left and logical (i.e. not arithmetic) right shifting. All of these operations also output flags, which may optionally be stored for later use with conditional jumps, or discarded. Note that these flags carry information only about the output of the ALU operation, which is only 16 bits wide.

The ALU is also capable of 16×16-bit unsigned and signed multiplication, which yields 32-bit numbers. Either or both halves of the result can be stored. Multiplication does not output flags.

The zero flag `Zf` indicates that the result of the ALU operation is zero. The sign flag `Sf` indicates that the MSB of the result is set. In the case of addition and subtraction, the carry flag `Cf` indicates that there was a carry out of the MSB, while the overflow flag `Of` indicates that the carry out was different from the MSB than from the bit of one lower order, essentially indicating signed carry, as opposed to unsigned carry.

The carry and overflow flags are left in an unspecified state by other ALU operations if they are allowed to update flags. Further, all flags are left in an unspecified state by operations that are not documented to produce flags if they are allowed to update them.

The 16 MSBs of the output produced by ALU operations are the 16 MSBs of the primary operand. The ALU blindly forwards these bits and does nothing else with them.

## Spatial unrolling

Depending on configuration, multiple execution units may be vertically stacked on top of one another. The amount of cores is configurable at creation time. These act as a single core sped up by a factor of however many execution units there are compared to a core with only one execution unit, resulting in a cycles per frame figure larger than 1.

This makes synchronizing with memory-mapped external hardware difficult because it is difficult to predict which execution unit an instruction will be executed on. To make this easier, conditional jumps are given a way to detect that they are being executed on the last (bottommost) execution unit, see the relevant section.

## Memory

The computer has internal memory arranged into rows of 128 quasi-32-bit cells, `mem_cells` cells and `mem_rows` rows overall. These values are configurable at creation time. For illustrative purposes, also keep the number `mem_p2rows` in mind, which is the smallest whole power of 2 larger than or equal to `mem_rows`, and the corresponding number of cells, `mem_p2cells`. The 16-bit address space is divided into 512 128-cell blocks, which are mapped to the internal memory as follows:

 - `mem_rows` blocks are mapped to the corresponding row in the internal memory in read-write mode
 - `mem_p2rows - mem_rows` blocks are mapped to the highest-address row of internal memory in read-only mode
 - `512 - mem_p2rows` blocks mirror the previous two sets of blocks in terms of being mapped to the internal memory, but only in read-only mode, and accesses in this range are considered external

Blocks being mapped to the internal memory in read-write mode means that reads addressing them are by default served by the internal memory, and writes addressing them are by default handled by it. Blocks being mapped to the internal memory in read-only mode means that reads addressing them are by default served by the internal memory, but writes are ignored by it.

Consider the example of `mem_rows` being 13: in this case, `mem_cells` is 0x680, `mem_p2rows` is 16, `mem_p2cells` is 0x800, and the memory map is as follows:

| cell range | block | reads served by | writes handled by | external |
|-|-|-|-|-|
| 0x0000 to 0x007F | 0 | row 0 | row 0 | |
| 0x0080 to 0x00FF | 1 | row 1 | row 1 | |
| 0x0100 to 0x017F | 2 | row 2 | row 2 | |
| 0x0180 to 0x01FF | 3 | row 3 | row 3 | |
| ... | ... | ... | ... | ... |
| 0x0500 to 0x057F | 10 | row 10 | row 10 | |
| 0x0580 to 0x05FF | 11 | row 11 | row 11 | |
| 0x0600 to 0x067F (`mem_cells` - 1) | 12 | row 12 | row 12 | |
| 0x0680 to 0x06FF | 13 | row 12 | nothing | |
| 0x0700 to 0x077F | 14 | row 12 | nothing | |
| 0x0780 to 0x07FF (`mem_p2cells` - 1) | 15 | row 12 | nothing | |
| 0x0800 to 0x087F | 16 | row 0 | nothing | x |
| 0x0880 to 0x08FF | 17 | row 1 | nothing | x |
| 0x0900 to 0x097F | 18 | row 2 | nothing | x |
| 0x0980 to 0x09FF | 19 | row 3 | nothing | x |
| ... | ... | ... | ... | ... |
| 0x0D00 to 0x0D7F | 26 | row 10 | nothing | x |
| 0x0D80 to 0x0DFF | 27 | row 11 | nothing | x |
| 0x0E00 to 0x0E7F | 28 | row 12 | nothing | x |
| 0x0E80 to 0x0EFF | 29 | row 12 | nothing | x |
| 0x0F00 to 0x0F7F | 30 | row 12 | nothing | x |
| 0x0F80 to 0x0FFF (2 * `mem_p2cells` - 1) | 31 | row 12 | nothing | x |
| 0x1000 to 0x107F | 32 | row 0 | nothing | x |
| 0x1080 to 0x10FF | 33 | row 1 | nothing | x |
| 0x1100 to 0x117F | 34 | row 2 | nothing | x |
| 0x1180 to 0x11FF | 35 | row 3 | nothing | x |
| ... | ... | ... | ... | ... |

Note that this is only the default memory map imposed by the internal memory, in the complete absence of external hardware.

## Input and output

Input and output are implemented via memory mapping, i.e. treating write and read accesses to specific addresses as sending data to and receiving data from external hardware.

Each execution unit exposes its memory control lines. These can be used to effectively put external hardware on the bus, letting it intercept reads and writes, or they can be left disconnected altogether, in which case they do not influence execution in any way.

In response to external memory access, hardware may produce a wait cycle, which causes the execution unit to functionally do nothing and let the next execution unit retry the memory access on its control lines. This repeats until an execution unit finishes the memory access without a wait cycle being produced.

The memory control lines are, from top to bottom, as follows:

### Address output

Produces the address being accessed by the execution unit. Hardware may decide to act based on this address.

Bit layout:

| bits | function |
|-|-|
| 31 to 29 | 0, unused |
| 28 | 1, sentinel |
| 27 to 20 | 0, unused |
| 19 | external read |
| 18 | internal read |
| 17 | external write |
| 16 | internal write |
| 15 to 0 | address being accessed |

Only ever one of the external/internal read/write bits is set in any given frame.

### Data output

Produces the value being written to the address being accessed by the execution unit. Its value is valid only if the address output indicates that the execution unit is executing a write (internal or external); it is indeterminate and should be ignored otherwise.

Bit layout:

| bits | function |
|-|-|
| 31 to 0 | value being written |

The value being written is never *functionally zero*.

### Bus state input

Takes the bus state: external hardware uses this to indicate that it wants the execution unit to wait (for data to be available to be read, for example) or that data is indeed available.

Bit layout:

| bits | function |
|-|-|
| 31 to 29 | must be 0, unused |
| 28 | must be 1, sentinel |
| 27 to 4 | must be 0, unused |
| 3 | indicates that the data input is valid |
| 2 to 1 | must be 0, unused |
| 0 | engages a wait cycle |

If left disconnected, it is internally reset such that it indicates no wait cycle and no valid input data.

### Data input

Takes the value being read from the address being accessed by the execution unit. Its value is considered only if the address output indicates that the execution unit is executing a read (internal or external) and if the bus state indicates that it is valid; it is ignored otherwise.

Bit layout:

| bits | function |
|-|-|
| 31 to 0 | value being read |

The value being read may be *functionally zero*.

## Stack

There is no stack support at the hardware level: no dedicated `push`, `pop`, `call`, `ret` instructions. The stack pointer is a register of your choice, values are pushed to the stack via write accesses and bumping the stack pointer in one direction, and are popped from the stack via read accesses and bumping the stack pointer in the other direction.

Calls can be implemented with jump instructions, which produce as output the address of the instruction that comes after them, see the relevant section.

## Execution control

The computer has a program counter, which always points at the next instruction. When the computer is running, whenever an instruction is executed, it is fetched from memory from whatever address the program counter points at. The program counter is then increased by 1 and the execution of the next instruction follows. When the computer is not running, the program counter stays unchanged.

Note: An instruction freshly written to memory cannot be immediately executed, because a memory write access instruction issues the write later than executing the next instruction issues the read that fetches the instruction. Thus, make sure to delay execution of instructions freshly written by at least one cycle, possibly by using a `nop`, see below.

The computer has three buttons on its bottom side, in this order from left to right:

 - reset: set the program counter to 0; not recommended while the computer is running
 - halt: halt execution
 - start: start execution

It also has an indicator next to these buttons that lights up when the computer is running.

Note: halt requests are ignored if the bottommost core is executing a wait cycle.

## Instruction reference

Each instruction encodes an operation, three operands, and whether the operation is allowed to update flags. There is a destination register operand, a primary source register operand, and a secondary operand that is either a source register or a 16-bit immediate value.

Different operations take different sets of operands: some take all three, some take none at all. In general, operations combine their source operands to produce an output that they then store in their destination operand.

Instruction bit layout:

| bits | function |
|-|-|
| 31 | MSB of operation index, mostly enables updating flags |
| 30 | secondary operand is an immediate value |
| 29 to 25 | destination register index |
| 24 to 20 | primary source register index |
| 19 to 16 | 4 LSB of operation index |
| 15 to 0 | secondary source register index, or an immediate value |

Jumps encode their conditions *instead of* a primary source register index. Bit layout:

| bits | function |
|-|-|
| 4 | sync bit |
| 3 to 0 | condition index |

Operations:

| operation | operation index | cycles taken | produces flags if requested | carry and overflow valid |
|-|-|-|-|-|
| `mov` | 0/F | 1 | x | |
| jumps (`jmp`, `jc`, ...) | 1/0 | 1 | | |
| `ld` | 2/0 | 2 | | |
| `exh` | 3/F | 1 | x | |
| `sub` | 4/F | 1 | x | x |
| `sbb` | 5/F | 1 | x | x |
| `add` | 6/F | 1 | x | x |
| `adc` | 7/F | 1 | x | x |
| `xor` | 8/F | 1 | x | |
| `or` | 9/F | 1 | x | |
| `st` | 10/0 | 2 | | |
| `shl` | 11/F (instruction bit 15 is 0) | 1 | x | |
| `shr` | 11/F (instruction bit 15 is 1) | 1 | x | |
| `and` | 12/F | 1 | x | |
| `hlt` | 13/F | 1 | | |
| `mul` | 14/0 | 1 | | |
| `muls` | 14/1 | 1 | | |
| `mulh` | 15/0 | 1 | | |
| `mulx` | 15/1 | 1 | | |

In this table, operation indices are in the form X/F, where X is the 4 LSB of the operation index, while F is the MSB of the operation index, unspecified in some cases because both possible values yield a valid operation index.

Note that not every type of execution unit necessarily supports multiplication; some types may waste a cycle not doing anything when encountering these instructions, letting the next execution unit handle it. The types of execution units are as follows:

 - **M** (multiply-capable): can execute `mul`, `mulh`, `muls`, and `mulx`
 - **S** (multiply-secondary): can execute `mul` in some cases
 - **F** (multiply-deferring): cannot execute any multiplication instruction

See `mul` for further details.

The effects of using any operation index not listed above are undefined.

Conditions:

| condition | condition index |
|-|-|
| - | 0 |
| be | 1 |
| l | 2 |
| le | 3 |
| s | 4 |
| z | 5 |
| o | 6 |
| c | 7 |
| n | 8 |
| nbe | 9 |
| nl | 10 |
| nle | 11 |
| ns | 12 |
| nz | 13 |
| no | 14 |
| nc | 15 |

### `add`: add

```asm
add  D, P, S
add  D, S    ; expands to add D, D, S
adds D, P, S ; leaves flags unchanged
```

Adds `P` to `S`, and stores the result in `D`. Note that due to properties of 2's complement arithmetic, whether both operands are signed or both are unsigned does not matter, as long as they are the same signedness.

### `adc`: add with carry

```asm
adc  D, P, S
adc  D, S    ; expands to adc D, D, S
adcs D, P, S ; leaves flags unchanged
```

Adds `P` to `S` treating the carry flag as carry in, and stores the result in `D`. Note that due to properties of 2's complement arithmetic, whether both operands are signed or both are unsigned does not matter, as long as they are the same signedness.

### `sub`: subtract

```asm
sub  D, P, S
sub  D, Sreg ; expands to sub D, D, Sreg
sub  D, Simm ; expands to add D, D, -Simm
subs D, P, S ; leaves flags unchanged
cmp  S, P    ; expands to sub r0, S, P
```

Subtracts `S` from `P`, and stores the result in `D`. Note that due to properties of 2's complement arithmetic, whether both operands are signed or both are unsigned does not matter, as long as they are the same signedness.

Note that in the case of this instruction, it is `P` that may take an immediate value rather than `S`. Accordingly, the following:

```asm
sub r3, 8
sub r3, r5, 8
```

are interpreted as the following semantically equivalent spellings:

```asm
add r3, -8
add r3, r5, -8
```

### `sbb`: subtract with borrow

```asm
sbb  D, P, S
sbb  D, Sreg ; expands to sub D, D, Sreg
sbb  D, Simm ; expands to adc D, D, -Simm
sbbs D, P, S ; leaves flags unchanged
```

Subtracts `S` from `P` treating the carry flag as borrow in, and stores the result in `D`. Note that due to properties of 2's complement arithmetic, whether both operands are signed or both are unsigned does not matter, as long as they are the same signedness.

Note that in the case of this instruction, it is `P` that may take an immediate value rather than `S`. Accordingly, the following:

```asm
sbb r3, 8
sbb r3, r5, 8
```

are interpreted as the following semantically equivalent spellings:

```asm
adc r3, -8
adc r3, r5, -8
```

### `mulh`: unsigned multiply high half

```asm
mulh D, P, S
```

Calculates the product of the two unsigned integers `P` and `S`, and stores the high half of the result in `D`.

Note that this instruction can only be executed by **M** (multiply-capable) execution units. All other units do nothing and defer to the next unit when encountering this instruction.

To illustrate the scheduling of instructions around **M** units, consider the list of consecutive execution units [ **F** (multiply-deferring), **F**, **M**, **F** ] about to be utilized at the time of reaching the following sequence of instructions:
```asm
add r1, r2, r3
mulh r4, r5, r6
add r7, r8, r9
```
In this case, the first `add` is scheduled on the first **F** unit, the `mulh` is skipped by the second **F** unit and scheduled on the **M** unit, and the second `add` is scheduled on the third **F** unit. The situation is identical if the **F** units are replaced with **S** (multiply-secondary) units.

### `muls`: signed multiply high half

```asm
muls D, P, S
```

Calculates the product of the two signed integers `P` and `S`, and stores the high half of the result in `D`.

Note that this instruction can only be executed by **M** (multiply-capable) execution units. All other units do nothing and defer to the next unit when encountering this instruction.

See `mulh` for a scheduling example.

### `mulx`: mixed-sign multiply high half

```asm
mulx D, P, S
```

Calculates the product of the unsigned integer `P` and the signed integer `S`, and stores the high half of the result in `D`. There is no variant that multiplies a signed register with an unsigned immediate value.

Note that this instruction can only be executed by **M** (multiply-capable) execution units. All other units do nothing and defer to the next unit when encountering this instruction.

See `mulh` for a scheduling example.

### `mul`: multiply low half

```asm
mul D, P, S
```

Calculates the product of the two integers `P` and `S`, and stores the low half of the result in `D`. Note that due to properties of 2's complement arithmetic, the signedness of the operands does not matter; any combination is valid and yields the same result.

Note that this instruction can only be executed by **M** (multiply-capable) and, in some cases, **S** (multiply-secondary) execution units. All other units, and in the remaining cases, **S** units, do nothing and defer to the next unit when encountering this instruction.

An **S** unit can only execute this instruction if:

 - the most recently utilized **M** unit executed a `mul`, `mulh`, `muls`, or `mulx` instruction
 - the register output operand of this instruction was not also a register input operand to it
 - the operands of this instruction exactly match those of the one about to be executed by the **S** unit

See `mulh` for a scheduling example of the simple case of a single **M** unit and many surrounding **F** (multiply-deferring) or **S** units.

To illustrate the conditions of an **S** unit being able to execute a `mul` instruction, consider the list of consecutive execution units [ **F**, **F**, **M**, **S**, **M** ] about to be utilized at the time of reaching the following sequence of instructions:
```asm
add r1, r2, r3
mulh r4, r5, r6
mul r10, r5, r6
add r7, r8, r9
```
In this case, the first `add` is scheduled on the first **F** unit, the `mulh` skipped by the second **F** unit and scheduled on the first **M** unit, the `mul` is scheduled on the **S** unit, and the second `add` is scheduled on the second **M** unit.

Note that the input operands of the `mulh` and the `mul` match exactly, and neither are written by the `mulh`. In the following sequence of instructions, the **S** unit fails to execute and defers the `mul` instruction to the second **M** unit because the `mulh` outputs to one of its inputs:
```asm
add r1, r2, r3
mulh r5, r5, r6
mul r10, r5, r6
add r7, r8, r9
```
Similarly, in this case, the **S** fails to execute and defers the `mul` instruction to the second **M** unit because its operands are not the same as those of the `mulh`:
```asm
add r1, r2, r3
mulh r4, r5, r6
mul r10, r5, r4
add r7, r8, r9
```

### `shl`: shift left

```asm
shl  D, P, S
shl  D, S    ; expands to shr D, D, S
shls D, P, S ; leaves flags unchanged
```

Shifts `P` by `S` bit positions to the left, shifting in zeros, and stores the result in `D`. Note that only the 4 LSBs of `S` are used; it is thus impossible to shift by 16 bit positions, which would yield zero.

### `shr`: shift logically right

```asm
shr  D, P, S
shr  D, S    ; expands to shr D, D, S
shrs D, P, S ; leaves flags unchanged
```

Shifts `P` by `S` bit positions to the right, shifting in zeros, and stores the result in `D`. Note that only the 4 LSBs of `S` are used; it is thus impossible to shift by 16 bit positions, which would yield zero.

### `and`: bitwise AND

```asm
and  D, P, S
and  D, S    ; expands to and D, D, S
ands D, P, S ; leaves flags unchanged
test S, P    ; expands to and r0, S, P
```

Executes a bitwise AND operation on `P` and `S`, and stores the result in `D`.

### `or`: bitwise OR

```asm
or  D, P, S
or  D, S    ; expands to or D, D, S
ors D, P, S ; leaves flags unchanged
```

Executes a bitwise OR operation on `P` and `S`, and stores the result in `D`.

### `xor`: bitwise XOR

```asm
xor  D, P, S
xor  D, S    ; expands to xor D, D, S
xors D, P, S ; leaves flags unchanged
```

Executes a bitwise XOR operation on `P` and `S`, and stores the result in `D`.

### `mov`: move

```asm
mov D, P, S
mov D, Treg  ; expands to mov D, Treg, Treg
mov D, Timm  ; expands to mov D, r0, Timm
nop          ; expands to mov r0, r0, r1
movf D, P, S ; updates flags
```

Stores `S` in `D`. Note that, as explained above, the 16 MSBs of the result come from `P`.

### `exh`: exchange halves

```asm
exh  D, P, S
exh  D, S    ; expands to exh D, D, S
exhs D, P, S ; leaves flags unchanged
```

Stores the 16 MSBs of `P` in `D`. This instruction is the exception to the rule that the 16 MSBs of the result are the 16 MSBs of `P`: in this case, they are the 16 LSBs of `S`.

### `ld`: load

```asm
ld D, P, S
ld D, S ; expands to ld D, r0, S
```

Executes a memory read access on the address `P`+`S`, and stores the value being read in `D`.

### `st`: store

```asm
st D, P, S
st D, S ; expands to st D, r0, S
```

Executes a memory write access on the address `P`+`S`, with the value being written taken from `D`. This instruction is exceptional in that `D` does not act as a destination operand; its value is preserved.

### `hlt`: halt

```asm
hlt
```

Halts execution. The computer may be restarted or reset at this point, or even halted manually, see above.

### `jmp`: jump

```asm
jmp D, S ; unconditionally
jmp S    ; expands to jmp r0, S
```

Stores the program counter in `D`, then stores `S` in the program counter. This means that the next instruction executed will be the one at the address pointed at by `S`, rather than the one that follows the jump.

This instruction also has conditional variants:

```asm
jbe  D, S ; jump if below (unsigned) or equal
jl   D, S ; jump if lesser (signed)
jle  D, S ; jump if lesser (signed) or equal
js   D, S ; jump if sign set
jz   D, S ; jump if zero set
jo   D, S ; jump if overflow set
jc   D, S ; jump if carry set
jn   D, S ; never jump (useful for reading the program counter)
jnbe D, S ; jump if not below (unsigned) or equal
jnl  D, S ; jump if not lesser (signed)
jnle D, S ; jump if not lesser (signed) or equal
jns  D, S ; jump if sign clear
jnz  D, S ; jump if zero clear
jno  D, S ; jump if overflow clear
jnc  D, S ; jump if carry clear
```

And some of them also have aliases:

```asm
ja   D, S ; jump if above (unsigned, same as jnbe)
jae  D, S ; jump if above (unsigned) or equal (same as jnc)
je   D, S ; jump if equal (same as jz)
jg   D, S ; jump if greater (signed, same as jnle)
jge  D, S ; jump if greater (signed) or equal (same as jnl)
jb   D, S ; jump if below (unsigned, same as jc)
jna  D, S ; jump if not above (unsigned, same as jbe)
jnae D, S ; jump if not above (unsigned) or equal (same as jc)
jne  D, S ; jump if not equal (same as jnz)
jng  D, S ; jump if not greater (signed, same as jle)
jnge D, S ; jump if not greater (signed) or equal (same as jl)
jnb  D, S ; jump if not below (unsigned, same as jnc)
```

All of the above also have a variant that only jumps if the conditions associated with the variants above hold *and* the instruction is being executed by any execution unit other than the last (bottommost) one. These are *synchronizing* conditional jumps, named so because they make it possible to easily synchronize with external hardware. These have the same mnemonics as the ordinary variant, but with an extra `y` after the `j`. The exception is `jy`, which is synchronizing `jmp`.

## Terminal

The display area is a collection of 8×8-pixel blocks, arranged into rows and columns, inside which pixels take any of 16 hard-coded colours. The amount of rows and columns is configurable at creation time.

The supported primitive operations are the *scrollprint* and simple pixel plotting. A scrollprint involves scrolling every block in an arbitrary rectangular sub-area of the display blocks by exactly one block in any of the four basic directions, and then filling the space thus freed up with copies of an arbitrary bitmap of a set of 256 bitmaps, one of which can be customized at the pixel level. Pixel plotting enables changing any pixel on the display.

Scrollprints can be requested directly or through terminal mode. Terminal mode introduces a cursor which respects the boundaries of the selected scrollprint sub-area, and can be configured to take different actions when printing characters and when reaching these boundaries.

The terminal's I/O range is accessible at a 128-cell-aligned block in the address space; the 9 MSB of addresses used to access this range are configurable at creation time. The 7 LSB form an address into the range, used to select read-only and write-only registers and write-triggered sub-ranges:

| addresses | register | access |
|-|-|-|
| 0x00 | `input` | read-only |
| 0x40 | `char0left` | write-only |
| 0x41 | `char0right` | write-only |
| 0x42 | `hrange` | write-only |
| 0x43 | `vrange` | write-only |
| 0x44 | `cursor` | write-only |
| 0x45 | `nlchar` | write-only |
| 0x46 | `colour` | write-only |
| 0x47 | `scrollmask` | write-only |

| addresses | sub-range | access |
|-|-|-|
| 0x00 to 0x3F | `scrollprint` | write-only |
| 0x60 to 0x7F | `plotpix` | write-only |

The effects of accessing any other address in the block are undefined. The effects of accessing any aforementioned register in a manner not appropriate for its capabilities are undefined.

### `input` register: keyboard input

This read-only register returns the code associated with the most recently pressed key, and causes the terminal to forget about this key press. If the value 0 is read from this register, no key has been pressed since the last time this register was read.

### `colour` register: colours used for scrollprints

This write-only register holds the colour used for printing characters.

| data bits | function |
|-|-|
| 31 to 8 | unused |
| 7 to 4 | background colour index |
| 3 to 0 | foreground colour index |

The 16 hard-coded colours are as follows:

| index | rgb888 | name |
|-|-|-|
|  0 | #000000 | black |
|  1 | #AA0000 | dark red |
|  2 | #00AA00 | dark green |
|  3 | #AAAA00 | dark yellow |
|  4 | #0000AA | dark blue |
|  5 | #AA00AA | dark magenta |
|  6 | #00AAAA | dark cyan |
|  7 | #AAAAAA | light grey |
|  8 | #555555 | dark grey |
|  9 | #FF5555 | light red |
| 10 | #55FF55 | light green |
| 11 | #FFFF55 | light yellow |
| 12 | #5555FF | light blue |
| 13 | #FF55FF | light magenta |
| 14 | #55FFFF | light cyan |
| 15 | #FFFFFF | white |

### `hrange` register: horizontal range used for scrollprints

This write-only register holds the horizontal range, or the column-wise extent of the scrollprint sub-area.

| data bits | function |
|-|-|
| 31 to 10 | unused |
| 9 to 5 | high column index |
| 4 to 0 | low column index |

Note that it is perfectly valid for the high column index to hold a value lower than the low column index: in this case, when the horizontal dimension is the secondary dimension during a scrollprint, blocks are scrolled to the left, rather than to the right. When the two values are equal, scrolling is not visible.

### `vrange` register: vertical range used for scrollprints

This write-only register holds the vertical range, or the row-wise extent of the scrollprint sub-area.

| data bits | function |
|-|-|
| 31 to 10 | unused |
| 9 to 5 | high row index |
| 4 to 0 | low row index |

Note that it is perfectly valid for the high row index to hold a value lower than the low row index: in this case, when the vertical dimension is the secondary dimension during a scrollprint, blocks are scrolled upward, rather than downward. When the two values are equal, scrolling is not visible.

### `cursor` register: cursor position used for scrollprints

This write-only register holds the position of the terminal mode cursor.

| data bits | function |
|-|-|
| 31 to 10 | unused |
| 9 to 5 | row index |
| 4 to 0 | column index |

### `nlchar` register: newline trigger character used for scrollprints

This write-only register holds the character used to signal that the terminal mode cursor should be moved to a new line.

| data bits | function |
|-|-|
| 31 to 8 | unused |
| 7 to 0 | character index |

### `scrollmask` register: scroll mask used for scrollprints

This write-only register holds the scroll mask used for printing characters.

| data bits | function |
|-|-|
| 31 to 29 | unused |
| 28 to 0 | enable bit for the column or row of the corresponding index |

Setting or clearing bits that correspond to columns or rows that do not exist have no effect.

### `char0left` register: character #0 left half

This write-only register holds the data for the leftmost 4 columns of character #0. Bits of this register map to the 8×4 grid of pixels according to the following table:

```
 0   8  16  24
 1   9  17  25
 2  10  18  26
 3  11  19  27
 4  12  20  28
 5  13  21  29
 6  14  22  30
 7  15  23  31
```

A set bit results in the corresponding pixel being plotted with the selected background colour, while a clear bit results in it being plotted with the selected foreground colour. Note that the usual limitations of the quasi-32-bit architecture apply.

### `char0right` register: character #0 right half

This write-only register has the exact same semantics as `char0left`, except it holds the data for the rightmost 4 columns of character #0.

### `scrollprint` sub-range: scroll selection and print character

Writing to this sub-range causes a character to be printed. The bitmap used to print the character is loaded from the character ROM, from the index specified by the character index.

If row-oriented printing is enabled, the primary dimension of the scrollprint is the horizontal dimension, while the secondary dimension is the vertical dimension. If it is disabled, these roles are reversed. Scrolling happens along the secondary dimension, in the direction specified by the `hrange` and `vrange` registers.

If terminal mode is enabled, printing a character this way causes the character to be printed under the terminal mode cursor, and advances the cursor by 1 block along the primary dimension. If this causes the cursor to exit the selected sub-area, then at the next terminal mode scrollprint, before a character is printed, it is moved to the low position of the primary range and is advanced by 1 block along the secondary dimension. If this once again causes the cursor to exit the selected sub-area, then what happens next depends on whether terminal mode scrolling is enabled.

If terminal mode scrolling is enabled, the sub-area is automatically scrolled along the secondary dimension by one block, with the space thus feed up filled with the bitmap at the character index stored in the `nlchar` register. The cursor does not move along the secondary dimension, though it will have moved relative to the display's contents. If it is disabled, the cursor is simply moved to the low position of the secondary range.

Note that this automatic scroll can cause the terminal to take two frames to print a single character (one to execute the automatic scroll, and one to print the character). The automatic scroll is executed in the frame in which the terminal received the request, while the character is printed in the next frame. If a command is sent to the terminal in this frame, the terminal temporarily rejects the command by responding on the bus with a wait cycle.

If the newline trigger character is enabled, and the character index matches that stored in the `nlchar` register, everything happens as if the cursor has exited the selected sub-area while being advanced along the primary dimension, except no character is printed.

If terminal mode is disabled, printing a character this way causes a scroll in the selected sub-area, and the space thus feed up is filled with the bitmap at the specified character index.

If the scroll mask is enabled, the set of rows of columns subject to scrolling is determined by the `scrollmask` register for the duration of this scrollprint, rather than from the range of the scrollprint along the primary dimension, as specified by the `hrange` and `vrange` registers. This feature does not combine well with terminal mode.

| address bits | function |
|-|-|
| 5 | enable newline trigger character |
| 4 | enable terminal mode scrolling |
| 3 | enable scroll mask |
| 2 | enable row-oriented printing |
| 1 | take colour from data |
| 0 | enable terminal mode |

| data bits | function |
|-|-|
| 31 to 16 | unused |
| 15 to 12 | background colour index |
| 11 to 8 | foreground colour index |
| 7 to 0 | character index |

The colour indices in the data bits are only consulted if this is enabled by the address bits; otherwise, colours are taken from the `colour` register.

### `plotpix` sub-range: plot pixel

Writing to this sub-range causes a pixel to be plotted, at the intersection of the specified pixel column and row, using the specified colour.

| address bits | function |
|-|-|
| 3 to 0 | colour index |

| data bits | function |
|-|-|
| 31 to 16 | unused |
| 15 to 8 | row index |
| 7 to 0 | column index |

Note that the resolution of the column and row indices is eightfold compared to the indices of the scrollprint range and cursor registers.
