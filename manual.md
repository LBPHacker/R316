# R3 reference manual

*This is a computer. All [crafthackership](https://dwarffortresswiki.org/) is of the highest quality. On the item is an image of the Subframe Inside™ logo. This object menaces with spikes of questionable time management.*

*TODO: save link*

Note: ordinal numbers throughout this manual start at 0, yielding odd-looking constructs such as *0th* and *bit 0* (the LSB). For clarity's sake the English word *first* is never used to refer to ordinals.

Note: Instruction spellings and expansions reflect the state of integration with [TPTASM](https://github.com/LBPHacker/tptasm).

## Features

 - **data path**: quasi-32-bit, works with *almost every* 32-bit value
 - **registers**: 32-bit words, 31 general purpose read/write, 1 read-only *almost zero*
 - **memory**: 2K (2048), 4K (4096), or 8K (8192) 32-bit words
 - **ALU**: 16-bit addition, logic, and shifting
 - ***spatial unrolling***: many CPU cycles per frame depending on configuration
 - **input and output**: memory-mapped, control lines are exposed, *wait cycles* can be injected

## Quasi-32-bit

Turns out that FILT's 2 MSBs can be used after all, although their handling is somewhat finicky: any ctype that is one of `0x00000000`, `0x40000000`, `0x80000000`, or `0xC0000000` (which this manual refers to as *dead values*) is treated as zero by some mechanics of the game, and so they get misinterpreted as the infamous temperature-dependent `0x0000001F` value.

The bottom line is that these values cannot be read or written by the computer. Reading them results in the aforementioned value, while writing them results in a value that also has the the `0x20000000` bit set in it. This behaviour is referred to as working with *almost every* 32-bit value.

## Registers

There are 31 general purpose read/write registers `r1` to `r31`, and also one read-only register `r0` that always reads `0x20000000`, referred to as *almost zero* because from the ALU's perspective, which only considers the 16 LSBs, it is indeed zero. This read-only register can be used as the destination operand to an operation, in which case the output produced by the operation is discarded.

## ALU

The ALU operates on the 16 LSBs of registers and on 16-bit immediate values. It is capable of addition and subtraction, with or without carry and borrow, bitwise OR, AND, XOR, and CLR (AND NOT), and left and logical (i.e. not arithmetic) right shifting. All of these operations also output flags, which may optionally be stored for later use with conditional jumps, or discarded. Note that these flags carry information only about the output of the ALU operation, which is only 16 bits wide.

The zero flag `Zf` indicates that the result of the ALU operation is zero. The sign flag `Sf` indicates that the MSB of the result is set. In the case of addition and subtraction, the carry flag `Cf` indicates that there was a carry out of the MSB, while the overflow flag `Of` indicates that the carry out was different from the MSB than from the bit of one lower order, essentially indicating signed carry, as opposed to unsigned carry.

The carry and overflow flags are left in an unspecified state by other ALU operations if they are allowed to update flags. Further, all flags are left in an unspecified state by operations that are not documented to produce flags if they are allowed to update them.

The 16 MSBs of the output produced by ALU operations are the 16 MSBs of the primary operand. The ALU blindly forwards these bits and does nothing else with them.

## Spatial unrolling

Depending on configuration, multiple execution units may be vertically stacked on top of one another. These act as a single core sped up by a factor of however many execution units there are compared to a core with only one execution unit, resulting in a cycles per frame figure larger than 1.

This makes synchronizing with memory-mapped external hardware difficult because it is difficult to predict which execution unit an instruction will be executed on. To make this easier, conditional jumps are given a way to detect that they are being executed on the last (bottommost) execution unit, see the relevant section.

## Input and output

Input and output are implemented via memory mapping, i.e. treating write and read accesses to specific addresses as sending data to and receiving data from external hardware.

The computer has internal memory, which it maps to a contiguous, whole-power-of-2-sized range of addresses starting at 0. Reads are by default served by this memory, even ones that address outside this range, which just wrap around. Writes to this range are also handled by this memory, but writes outside this range are ignored by it.

Each execution unit exposes its memory control lines. These can be used to effectively put external hardware on the bus, letting it intercept reads and writes, or they can be left disconnected altogether, in which case they do not influence execution in any way. They are, from top to bottom, as follows:

### Address output

Produces the address being accessed by the execution unit. Hardware may decide to act based on this address.

Bit layout:

| bits | function |
|-|-|
| 31 to 30 | 0, unused |
| 29 | 1, sentinel |
| 28 to 20 | 0, unused |
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
| 31 to 30 | must be 0, unused |
| 29 | must be 1, sentinel |
| 28 to 4 | must be 0, unused |
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

## Instruction reference

Each instruction encodes an operation, three operands, and whether the operation is allowed to update flags. There is a destination register operand, a primary source register operand, and a secondary operand that is either a source register or a 16-bit immediate value.

Different operations take different sets of operands: some take all three, some take none at all. In general, operations combine their source operands to produce an output that they then store in their destination operand.

Bit layout:

| bits | function |
|-|-|
| 31 | enables updating flags |
| 30 | secondary operand is an immediate |
| 29 to 25 | destination register index |
| 24 to 20 | primary source register index |
| 19 to 16 | operation index |
| 15 to 0 | secondary source register index, or an immediate value |

Jumps encode their conditions *instead of* a primary source register index. Bit layout:

| bits | function |
|-|-|
| 4 | sync bit |
| 3 to 0 | condition index |

Operations:

| operation | operation index | cycles taken | produces flags | carry and overflow valid |
|-|-|-|-|-|
| `mov` | 0 | 1 | x | |
| jumps (`jmp`, `jc`, ...) | 1 | 1 | | |
| `ld` | 2 | 2 | | |
| `exh` | 3 | 1 | x | |
| `sub` | 4 | 1 | x | x |
| `sbb` | 5 | 1 | x | x |
| `add` | 6 | 1 | x | x |
| `adc` | 7 | 1 | x | x |
| `shl` | 8 | 1 | x | |
| `shr` | 9 | 1 | x | |
| `st` | 10 | 2 | | |
| `hlt` | 11 | 1 | | |
| `and` | 12 | 1 | x | |
| `or` | 13 | 1 | x | |
| `xor` | 14 | 1 | x | |
| `clr` | 15 | 1 | x | |

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

Adds `P` to `S`, and stores the result in `D`.

### `adc`: add with carry

```asm
adc  D, P, S
adc  D, S    ; expands to adc D, D, S
adcs D, P, S ; leaves flags unchanged
```

Adds `P` to `S` treating the carry flag as carry in, and stores the result in `D`.

### `sub`: subtract

```asm
sub  D, P, S
sub  D, Sreg ; expands to sub D, D, Sreg
sub  D, Simm ; expands to add D, D, -Simm
subs D, P, S ; leaves flags unchanged
cmp  S, P    ; expands to sub r0, S, P
```

Subtracts `S` from `P`, and stores the result in `D`. Note that in the case of this instruction, it is `P` that may take an immediate value rather than `S`. Accordingly, the following:

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

Subtracts `S` from `P` treating the carry flag as borrow in, and stores the result in `D`. Note that in the case of this instruction, it is `P` that may take an immediate value rather than `S`. Accordingly, the following:

```asm
sbb r3, 8
sbb r3, r5, 8
```

are interpreted as the following semantically equivalent spellings:

```asm
adc r3, -8
adc r3, r5, -8
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

### `clr`: bitwise AND NOT a.k.a. clear

```asm
clr  D, P, S
clr  D, Sreg ; expands to clr D, D, Sreg
clr  D, Simm ; expands to and D, D, ~Simm
clrs D, P, S ; leaves flags unchanged
```

Executes a bitwise AND operation on `P` and **an inverted copy of `S`**, and stores the result in `D`. Note that in the case of this instruction, it is `P` that may take an immediate value rather than `S`. Accordingly, the following:

```asm
clr r3, 0x0008
clr r3, r5, 0x0008
```

are interpreted as the following semantically equivalent spellings:

```asm
and r3, 0xFFF7
and r3, r5, 0xFFF7
```

### `mov`: move

```asm
mov D, P, S
mov D, Treg ; expands to mov D, Treg, Treg
mov D, Timm ; expands to mov D, r0, Timm
nop         ; expands to mov r0, r0, r1
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
