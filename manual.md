# R316 reference manual

*This is a computer. All crafthackership is of the highest quality. On the item is an image of the Subframe Inside™ logo. This object menaces with spikes of questionable time management.*

Check out [the showcase save](https://powdertoy.co.uk/Browse/View.html?ID=3236906) in your browser.

![the showcase save](screenshot.png)

Note: ordinal numbers throughout this manual start at 0, yielding odd-looking constructs such as *0th* and *bit 0* (the LSB). For clarity's sake the English word *first* is never used to refer to ordinals.

Note: Instruction spellings and expansions reflect the state of integration with [TPTASM](https://github.com/LBPHacker/tptasm).

Note: Feel free to suggest improvements both to this manual and the computer and its peripherals themselves.

Note: **Please read through this manual, or at least use the "Find in page" / Ctrl+F feature of your browser on it, before asking for help with topics that it already covers.**

## Features

 - **data path**: quasi-32-bit, works with *almost every* 32-bit value
 - **registers**: 32-bit words, 31 general purpose read/write, 1 read-only *functionally zero*
 - **memory**: any amount of 32-bit words from 128 to 8192 (8K), in increments of 128
 - **ALU**: 16-bit addition, logic, and shifting, 16-16-bit *multiplication* with 32-bit results
 - ***spatial unrolling***: many CPU cycles per frame depending on configuration
 - **input and output**: memory-mapped, control lines are exposed, *wait cycles* can be injected

## Quasi-32-bit

It has been revealed that FILT's 2 MSBs can be used after all, though their handling is somewhat finicky: any ctype that is one of `0x00000000`, `0x40000000`, `0x80000000`, or `0xC0000000` is treated as zero by some mechanics of the game, and so they get misinterpreted as the infamous temperature-dependent `0x0000001F` value. These four values are referred to as *physically zero*.

The bottom line is that these values cannot be read or written by the computer. Reading them results in the aforementioned value, while writing them results in a value that also has the the `0x20000000` bit set in it. This behaviour is referred to as working with *almost every* 32-bit value.

## Registers

There are 31 general purpose read/write registers `r1` to `r31`, and also one read-only register `r0` that always reads `0x20000000`, referred to as *functionally zero* because from the ALU's perspective, which only considers the 16 LSBs, it is indeed zero. This read-only register can be used as the destination operand to an operation, in which case the output produced by the operation is discarded.

## ALU

The ALU operates on the 16 LSBs of registers and on 16-bit immediate values. It is capable of addition and subtraction, with or without carry and borrow, bitwise OR, AND, and XOR, and left and logical (i.e. not arithmetic) right shifting. All of these operations also output flags, which may optionally be stored for later use with conditional jumps, or discarded. Note that these flags carry information only about the output of the ALU operation, which is only 16 bits wide.

The ALU is also capable of 16×16-bit unsigned and signed multiplication, which yields 32-bit numbers. Either or both halves of the result can be stored. Multiplication does not output flags.

The zero flag `Zf` indicates that the result of the ALU operation is zero. The sign flag `Sf` indicates that the MSB of the result is set. In the case of addition and subtraction, the carry flag `Cf` indicates that there was a carry out of the MSB, while the overflow flag `Of` indicates that the carry out was different from the MSB than from the bit of one lower order, essentially indicating signed carry, as opposed to unsigned carry.

The carry and overflow flags are left in an unspecified state by other ALU operations if they are allowed to update flags. Further, all flags are left in an unspecified state by operations that are not documented to produce flags if they are allowed to update them.

The 16 MSBs of the output produced by ALU operations are the 16 MSBs of the primary operand. The ALU blindly forwards these bits and does nothing else with them.

## Spatial unrolling

Depending on configuration, multiple execution units may be vertically stacked on top of one another. The amount of execution units is configurable at creation time. These act as a single computer sped up by a factor of however many execution units there are compared to a computer with only one execution unit, resulting in a cycles per frame figure larger than 1.

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

In response to external memory access, hardware may inject a wait cycle, which causes the execution unit to functionally do nothing and let the next execution unit retry the memory access on its control lines. This repeats until an execution unit finishes the memory access without a wait cycle being injected.

### Hardware interface

The memory control lines are, from top to bottom, as follows:

#### Address output

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

#### Data output

Produces the value being written to the address being accessed by the execution unit. Its value is valid only if the address output indicates that the execution unit is executing a write (internal or external); it is indeterminate and should be ignored otherwise.

Bit layout:

| bits | function |
|-|-|
| 31 to 0 | value being written |

The value being written is never *physically zero*.

#### Bus state input

Takes the bus state: external hardware uses this to indicate that it wants the execution unit to wait (for data to be available to be read, for example) or that data is indeed available.

Bit layout:

| bits | function |
|-|-|
| 31 to 29 | must be 0, unused |
| 28 | must be 1, sentinel |
| 27 to 4 | must be 0, unused |
| 3 | indicates that the data input is valid |
| 2 to 1 | must be 0, unused |
| 0 | injects a wait cycle |

If left disconnected, it is internally reset such that it indicates no wait cycle injection and no valid input data.

#### Data input

Takes the value being read from the address being accessed by the execution unit. Its value is considered only if the address output indicates that the execution unit is executing a read (internal or external) and if the bus state indicates that it is valid; it is ignored otherwise.

Bit layout:

| bits | function |
|-|-|
| 31 to 0 | value being read |

The value being read may not be *physically zero*.

### Conventional bus structure

To make the bus, as explained so far, convenient to use, the convention is to include a dummy peripheral at the end of the part of the bus exposed on each execution unit that injects a wait cycle whenever an external read or write happens on the bus. This, combined with peripherals that override the bus state and data input generated by all other peripherals to their right, ensures that all bus accesses that are not handled by a real peripheral result in a wait cycle being injected.

This makes the bus much more convenient to use, as this means an instruction that is meant to access a specific peripheral can be safely executed on any execution unit, not only the one the peripheral is connected to. If it is executed on another execution unit, the dummy peripherals at the ends inject wait cycles until the instruction is attempted to be executed on the correct execution unit.

If there is no ambiguity in which peripheral handles which bus access (i.e. there is no kind of bus access that multiple peripherals present on the bus may handle), this approach ensures that bus accesses are always routed to the correct peripheral, without any consideration required on the code side.

Regardless, synchronizing jump instructions may still be useful for implementing precise timing.

## Stack

There is no stack support at the hardware level: no dedicated `push`, `pop`, `call`, `ret` instructions. The stack pointer is a register of your choice, values are pushed to the stack via write accesses and bumping the stack pointer in one direction, and are popped from the stack via read accesses and bumping the stack pointer in the other direction.

Calls can be implemented with jump instructions, which produce as output the address of the instruction that comes after them, see the relevant section.

## Execution control

The computer has a program counter, which always points at the next instruction. When the computer is running, whenever an instruction is executed, it is fetched from memory from whatever address the program counter points at. The program counter is then increased by 1 and the execution of the next instruction follows. When the computer is not running, the program counter stays unchanged. Assuming no user interaction, all other computer state stay unchanged.

Note: An instruction freshly written to memory cannot be immediately executed, because a memory write access instruction issues the write later than executing the next instruction issues the read that fetches the instruction. Thus, make sure to delay execution of instructions freshly written by at least one cycle, possibly by using a `nop`, see below.

The computer has three buttons on its bottom side, in this order from left to right:

 - reset: force execution to be halted, set the program counter to 0, cancel any injected wait cycles
 - halt: request execution to be halted
 - start: start execution

It also has an indicator next to these buttons that lights up when the computer is running.

The difference between forcing and requesting execution to be halted is that forcing it brings the computer to an indeterminate state in terms of memory and register contents, though at least a state from which execution can be restarted normally nonetheless, while requesting it waits for all pending memory accesses to finish.

Note: As wait cycles prevent memory access from finishing, halt requests are ignored if a wait cycle has been injected into the bottommost execution unit. This can keep happening indefinitely if the execution unit is trying to access an address in memory that is not backed by either the built-in memory or any peripheral. In this case, the computer must be reset instead.

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

Conditions, expressed in terms of the four flags `Zf`, `Sf`, `Cf`, and `Of`:

| name | condition index | condition |
|-|-|-|
| - | 0 | `true` |
| be | 1 | `Cf | Zf` |
| l | 2 | `Sf ^ Of` |
| le | 3 | `Zf | (Sf ^ Of)` |
| s | 4 | `Sf` |
| z | 5 | `Zf` |
| o | 6 | `Of` |
| c | 7 | `Cf` |
| n | 8 | `false` |
| nbe | 9 | `!(Cf | Zf)` |
| nl | 10 | `!(Sf ^ Of)` |
| nle | 11 | `!(Zf | (Sf ^ Of))` |
| ns | 12 | `!Sf` |
| nz | 13 | `!Zf` |
| no | 14 | `!Of` |
| nc | 15 | `!Cf` |

Note that the two halves of the table are the exact same conditions, but negated.

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
sub  D, Simm ; expands to add D, D, -Simm, carry inverted
subs D, P, S ; leaves flags unchanged
cmp  P, Sreg ; expands to sub r0, P, Sreg
cmp  P, Simm ; expands to add r0, P, -Simm, carry inverted
```

Subtracts `S` from `P`, and stores the result in `D`. Note that due to properties of 2's complement arithmetic, whether both operands are signed or both are unsigned does not matter, as long as they are the same signedness.

Note that in the case of this instruction, it is `P` that may take an immediate value rather than `S`. Accordingly, the following:

```asm
sub r3, 8
sub r3, r5, 8
```

are interpreted as the following almost semantically equivalent spellings:

```asm
add r3, -8
add r3, r5, -8
```

the important difference being that the carry flag is inverted compared to what might be expected given the original spelling, because an addition with a 2's-complement-negated constant is done under the hood. **Pay very close attention to this.**

This ultimately means that conditional jumps relying on unsigned overflow detection with the carry flag should be similarly inverted: `ja` instead of `jb`, etc. For this reason, it is recommended to manually rewrite such instances of `sub` to the `add`-based spelling for clarity.

### `sbb`: subtract with borrow

```asm
sbb  D, P, S
sbb  D, Sreg ; expands to sub D, D, Sreg
sbb  D, Simm ; expands to adc D, D, Simm ^ 0xFFFF, carry inverted
sbbs D, P, S ; leaves flags unchanged
```

Subtracts `S` from `P` treating the carry flag as borrow in, and stores the result in `D`. Note that due to properties of 2's complement arithmetic, whether both operands are signed or both are unsigned does not matter, as long as they are the same signedness.

Note that in the case of this instruction, it is `P` that may take an immediate value rather than `S`. Accordingly, the following:

```asm
sbb r3, 8
sbb r3, r5, 8
```

are interpreted as the following almost semantically equivalent spellings:

```asm
adc r3, 0xFFF7
adc r3, r5, 0xFFF7
```

the important difference being that the carry flag is inverted compared to what might be expected given the original spelling, because an addition with a bitwise-negated constant is done under the hood. **Pay very close attention to this.**

This ultimately means that conditional jumps relying on unsigned overflow detection with the carry flag should be similarly inverted: `ja` instead of `jb`, etc. For this reason, it is recommended to manually rewrite such instances of `sbb` to the `adc`-based spelling for clarity.

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

 - the previous unit is an **M** unit and it executed a `mul`, `mulh`, `muls`, or `mulx` instruction
 - the register output operand of this instruction was not also a register input operand to it
 - the operands of this instruction exactly match those of the one about to be executed by the **S** unit

Note that due to the first requirement, **S** units are only useful when they immediately follow **M** units.

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

## Configuration

Feel free to ignore this section if to do not plan on making your own custom R316-based saves.

There exists no single version of the computer and its peripherals; instead, there exists a family of all of them, with distinct *configurations*. The configuration of such a component is the set of properties that determine its capabilities, in-game appearance, location in the simulation, and so on. The configuration options of each component are documented.

The showcase save is just one such configuration. Any configuration can be turned into a simulation using *r3plot.lua*.

Using this script requires some Lua knowledge, but only to the point of familiarity with table syntax. Grab r3plot.lua from [the releases page](https://github.com/LBPHacker/R316/releases). Beware, it is huge in Lua script terms. The script is expected to be run as a Lua function and given a single table as its first parameter: the configuration.

### Configuration structure

Table, required. This is the first and only parameter to r3plot.lua.

#### `.components` property

Table, required. This is an array of component configuration nodes.

#### `.components[...].type` property

String, required. Refers to a component type. Each component has an associated `.type` documented alongside its configuration options.

#### `.components[...].name` property

String, required, must be unique across all component configuration nodes. Can be any string. It is used to create connections between multiple components.

#### `.x` and `.y` properties

Integers, optional, default to `0`. These enable offsetting the position in the simulation of everything by some amount. Helps with cosmetics.

#### `.debug_stacks` property

Table, optional. If present, once the script is done plotting, it enters visual debug mode, with call stacks that resulted in the placement of each particle made visible when hovered. Stacks with multiple particles show multiple call stacks. This mode can be exited by running `r3plot.unregister()` in the console.

#### `.debug_areas` property

Boolean, optional, defaults to `false`. If `true`, once the script is done plotting, it enters visual debug mode, with areas made visible. Areas cover parts of the plotted structures, and hovering over them displays their names. This mode can be exited by running `r3plot.unregister()` in the console.

#### `.clear_sim` property

Boolean, optional, defaults to `false`. If `true`, the script erases the simulation and changes some simulation options to get the best possible performance. The computer and its peripherals are generally not sensitive to these settings, the intent is simply best performance.

### Of the computer itself

The computer exposes exactly as many buses as many execution units it has. These buses can be referred to with tables with two properties: `cpu` and `bus_index`. `cpu` is the `.name` of the computer instance, while `.bus_index` is an integer in the inclusive range `0` to `n - 1`, where `n` is the amount of execution units the computer has.

This component is available under the type `"cpu"`.

#### `.left` or `.right` properties

Integer, at most one of the two allowed. This determines the horizontal placement of the given border (left or right) of the computer.

#### `.top` or `.bottom` properties

Integer, at most one of the two allowed. This determines the vertical placement of the given border (top or bottom) of the computer.

#### `.left_padding` and `.right_padding` properties

Integers, optional, default to `0`. These determine the extra space between the left and right borders of the computer and the particles inside, respectively. Purely cosmetic, can help achieve width alignment with peripherals and other things in the simulation.

#### `.machine_id` property

Integer, optional, defaults to `1337`. The identifier to encode in the TPTASM anchor.

#### `.cores` property

String, required. Each character is one of `"m"`, `"s"`, `"f"`, referring to M, S, and F execution units, respectively. The first character determines the type of the topmost execution unit, the second character of the second one, and so on. Must be at least a single character, and must contain at least a single `"m"`.

#### `.memory_rows` property

Integer, required, in the inclusive range 1 to 64. The amount of 0x80-sized blocks the built-in memory spans.

#### Example configuration

```lua
{
	type        = "cpu",
	name        = "cpu0",
	cores       = "msfffmsfff",
	memory_rows = 16,
	left        = 140,
	bottom      = 253,
}
```

### Example script invocation

This was used to plot the showcase save, barring the text and other cosmetic parts.

```lua
loadfile("/path/to/r3plot.lua")({
	components = {
		{
			type        = "cpu",
			name        = "cpu0",
			cores       = "msfffmsfff",
			memory_rows = 16,
			left        = 140,
			bottom      = 253,
		},
		{
			type          = "terminal",
			name          = "terminal0",
			left          = 330,
			screen_bottom = 233,
			keyboard_top  = 250,
			chars_nh      = 12,
			chars_nv      = 8,
			base_address  = 0x9F80,
			single_pixel  = true,
			bus = {
				cpu       = "cpu0",
				bus_index = 9,
			},
		},
	},
	x = -10,
	y = -10,
})
```

## Terminal

The display area is a collection of 8×8-pixel blocks, arranged into rows and columns, inside which pixels take any of 16 hard-coded colours. The amount of rows and columns is configurable at creation time.

The supported primitive operations are the *scrollprint* and simple pixel plotting. A scrollprint involves scrolling every block in an arbitrary rectangular sub-area of the display blocks by exactly one block in any of the four basic directions, and then filling the space thus freed up with copies of an arbitrary bitmap of a set of 256 bitmaps, one of which can be customized at the pixel level. Pixel plotting enables changing any pixel on the display.

Scrollprints can be requested directly or through terminal mode. Terminal mode introduces a cursor which respects the boundaries of the selected scrollprint sub-area, and can be configured to take different actions when printing characters and when reaching these boundaries.

### I/O range

The terminal's I/O range is accessible at a 0x80-cell-aligned block in the address space; the 9 MSB of addresses used to access this range depend on configuration. The 7 LSB form an address into the range, used to select read-only and write-only registers and write-triggered sub-ranges:

| addresses | register | access |
|-|-|-|
| 0x00 | `input` | read-only |
| 0x40 | `char0odd` | write-only |
| 0x41 | `char0even` | write-only |
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

#### `input` register: keyboard input

This read-only register returns the code associated with the most recently pressed key, and causes the terminal to forget about this key press. If the value 0 is read from this register, no key has been pressed since the last time this register was read.

#### `colour` register: colours used for scrollprints

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

#### `hrange` register: horizontal range used for scrollprints

This write-only register holds the horizontal range, or the column-wise extent of the scrollprint sub-area. The range of meaningful values depends on configuration.

| data bits | function |
|-|-|
| 31 to 10 | unused |
| 9 to 5 | high column index |
| 4 to 0 | low column index |

Note that it is perfectly valid for the high column index to hold a value lower than the low column index: in this case, when the horizontal dimension is the secondary dimension during a scrollprint, blocks are scrolled to the left, rather than to the right. When the two values are equal, scrolling is not visible.

#### `vrange` register: vertical range used for scrollprints

This write-only register holds the vertical range, or the row-wise extent of the scrollprint sub-area. The range of meaningful values depends on configuration.

| data bits | function |
|-|-|
| 31 to 10 | unused |
| 9 to 5 | high row index |
| 4 to 0 | low row index |

Note that it is perfectly valid for the high row index to hold a value lower than the low row index: in this case, when the vertical dimension is the secondary dimension during a scrollprint, blocks are scrolled upward, rather than downward. When the two values are equal, scrolling is not visible.

#### `cursor` register: cursor position used for scrollprints

This write-only register holds the position of the terminal mode cursor.

| data bits | function |
|-|-|
| 31 to 10 | unused |
| 9 to 5 | row index |
| 4 to 0 | column index |

#### `nlchar` register: newline trigger character used for scrollprints

This write-only register holds the character used to signal that the terminal mode cursor should be moved to a new line.

| data bits | function |
|-|-|
| 31 to 8 | unused |
| 7 to 0 | character index |

#### `scrollmask` register: scroll mask used for scrollprints

This write-only register holds the scroll mask used for printing characters.

| data bits | function |
|-|-|
| 31 to 29 | unused |
| 28 to 0 | enable bit for the column or row of the corresponding index |

Setting or clearing bits that correspond to columns or rows that do not exist has no effect.

#### `char0even` register: character #0 odd columns

This write-only register holds the data for the even-numbered columns of character #0. Bits of this register map to the 8×8 grid of pixels according to the following table:

```
 7  --  15  --  23  --  31  --
 6  --  14  --  22  --  30  --
 5  --  13  --  21  --  29  --
 4  --  12  --  20  --  28  --
 3  --  11  --  19  --  27  --
 2  --  10  --  18  --  26  --
 1  --   9  --  17  --  25  --
 0  --   8  --  16  --  24  --
```

A set bit results in the corresponding pixel being plotted with the selected background colour, while a clear bit results in it being plotted with the selected foreground colour. Note that the usual limitations of the quasi-32-bit architecture apply. Spots marked with `--` in the table are mapped by `char0odd`.

#### `char0odd` register: character #0 even columns

This write-only register has the exact same semantics as `char0even`, except it holds the data for the odd-numbered columns of character #0.

```
--   7  --  15  --  23  --  31
--   6  --  14  --  22  --  30
--   5  --  13  --  21  --  29
--   4  --  12  --  20  --  28
--   3  --  11  --  19  --  27
--   2  --  10  --  18  --  26
--   1  --   9  --  17  --  25
--   0  --   8  --  16  --  24
```

Spots marked with `--` in the table are mapped by `char0even`.

#### `scrollprint` sub-range: scroll selection and print character

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

#### `plotpix` sub-range: plot pixel

This sub-range is meaningful only if the pixel plotter has been requested in the configuration.

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

### Configuration

Feel free to ignore this section if to do not plan on making your own custom R316-based saves.

The terminal connects to a bus. It can manifest as a stand-alone keyboard or screen, or it can be both at once. If it is both, their bodies can be requested to be unified. In all cases, the screen is above the bus it is connected to, while the keyboard is below it. Its size, the address of its I/O range, the presence of a pixel plotter, and other cosmetic properties can be configured.

This component is available under the type `"terminal"`.

#### `.bus` property

A bus, required, to which the terminal connects. This determines the vertical placement of the bus interfaces the screen and/or the keyboard use.

#### `.base_address` property

Integer, required, in the inclusive range `0x0000` to `0xFFFF`. Its 7 LSB must be `0`. This determines the address of the 0x80-cell-aligned block that is the terminal's I/O range.

#### `.left` or `.right` properties

Integer, at most one of the two allowed. This determines the horizontal placement of the given border (left or right) of the screen and/or the keyboard.

#### `.screen_top` or `.screen_bottom` properties

Integer, optional, at most one of the two allowed. If present, the terminal has a screen. This determines the vertical placement of the given border (top or bottom) of the screen. Care must be taken so the screen does not overlap with any bus or its own bus interface.

#### `.keyboard_top` or `.keyboard_bottom` properties

Integer, optional, at most one of the two allowed. If present, the terminal has a keyboard. This determines the vertical placement of the given border (top or bottom) of the keyboard. Care must be taken so the keyboard does not overlap with any bus or its own bus interface.

#### `.chars_nh` and `.chars_nv` properties

Integers, required. These determine the amount of columns and rows of characters the terminal has, respectively. They are in the inclusive ranges 12 to 29 and 4 to 29, respectively, though restrictions apply: some aspect ratios are not supported, and some size configurations are incompatible with the presence of a pixel plotter.

The following table specifies this in detail. Rows are row counts, columns are column counts. Empty cells are unsupported combinations, cells with 💯 are supported, cells with ✅ are supported only if a pixel plotter is not requested. Any combination not shown in the table is not supported.

|    | 12 | 13 | 14 | 15 | 16 | 17 | 18 | 19 | 20 | 21 | 22 | 23 | 24 | 25 | 26 | 27 | 28 | 29 |
|----|----|----|----|----|----|----|----|----|----|----|----|----|----|----|----|----|----|----|
|  4 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
|  5 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
|  6 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
|  7 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
|  8 | 💯 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
|  9 | 💯 | 💯 | 💯 | 💯 | 💯 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 10 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 11 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | ✅ | ✅ | ✅ | ✅ | ✅ |
| 12 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | ✅ |
| 13 |    | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 |
| 14 |    | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 |
| 15 |    | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 |
| 16 |    | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 |
| 17 |    |    | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 |
| 18 |    |    | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 |
| 19 |    |    | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 |
| 20 |    |    | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 |
| 21 |    |    |    | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 |
| 22 |    |    |    | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 |
| 23 |    |    |    | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 |
| 24 |    |    |    | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 |
| 25 |    |    |    |    | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 |
| 26 |    |    |    |    | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 |
| 27 |    |    |    |    | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 |
| 28 |    |    |    |    | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 |
| 29 |    |    |    |    |    | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 | 💯 |

#### `.single_pixel` property

Boolean, optional, defaults to `false`. If `true`, the screen portion of the terminal includes a pixel plotter. This is not compatible with some size configurations.

#### `.grvt_cover` property

Boolean, optional, defaults to `false`. If `true`, some very noticeably and distractingly flickering parts of the screen portion are covered with inert GRVT. Purely cosmetic.

#### `.unibody` property

Boolean, optional, defaults to `false`. If `true`, the screen and keyboard portions share a body.

#### Example configuration

```lua
{
	type          = "terminal",
	name          = "terminal0",
	left          = 330,
	screen_bottom = 233,
	keyboard_top  = 250,
	chars_nh      = 12,
	chars_nv      = 8,
	base_address  = 0x9F80,
	single_pixel  = true,
	unibody       = false,
	grvt_cover    = false,
	bus = {
		cpu       = "cpu0",
		bus_index = 9,
	},
}
```

## R216 peripheral adapter

This peripheral exposes R216 peripheral ports, much like the I/O breakout boxes of that architecture. It consists of a number of port components and a termination component, in this order, from left to right. Each port component exposes an R216 peripheral port.

### I/O range

The adapter's I/O range is accessible at an address that depends on configuration. There are two sets of registers:

| register set | access |
|-|-|
| `bump` | read-write |
| `data[...]` | read-write |

#### `bump` register: get leftmost bumped port or set bumped port

Writing the address of a `data[...]` register to this register causes the corresponding port to be bumped for some future frame, always a constant offset in terms of frames from the current frame.

Reading this register returns the address of the `data[...]` corresponding to the port that was bumped in some past frame, always a constant offset in terms of frames from the current frame, with the 16 MSB of the value read being `0x2000`. If there are multiple such ports, the leftmost one wins. If there are no such ports, the 16 MSB of the value read are `0x0000` and the 16 LSB are `0xFFFF`.

The constant input frame offsets are identical to those explained in relation to the `data[...]` register in the corresponding (i.e. input or output) direction.

#### `data[...]` register: send and receive data

Writing a value to this register causes the 16 LSB of the data to be sent on the port in some future frame, always a constant offset in terms of frames from the current frame.

Reading a value from this register returns the 16 LSB of the data that was received on the port in some past frame, always a constant offset in terms of frames from the current frame, with the 16 MSB of the value read being `0x0002`. If there was no data received, the 16 MSB of the value read are `0x0000` and the 16 LSB are `0xFFFF`.

The constant input frame offsets are identical to those explained in relation to the `bump` register in the corresponding (i.e. input or output) direction.

### Configuration

Feel free to ignore this section if to do not plan on making your own custom R316-based saves.

The adapter connects to a bus. The address of its I/O range can be configured.

This component is available under the type `"r2_adapter"`.

#### `.bus` property

A bus, required, to which the terminal connects. This determines the vertical placement of the bus interfaces the screen and/or the keyboard use.

#### `.bump_address` property

Integer, required, in the inclusive range `0x0000` to `0xFFFF`. This determines the address of the `bump` register.

#### `.term_left` or `.term_right` properties

Integer, at most one of the two allowed. This determines the horizontal placement of the given border (left or right) of the termination component.

#### `.ports` property

An array of port configuration nodes.

#### `.ports[...].data_address` property

Integer, required, in the inclusive range `0x0000` to `0xFFFF`. This determines the address of the `data[...]` register. This must be distinct from the addresses of all the other `data[...]` registers and also of the `bump` register.

#### `.ports[...].left` or `.ports[...].right` properties

Integer, at most one of the two allowed. This determines the horizontal placement of the given border (left or right) of a port component.

#### Example configuration

```lua
{
	type         = "r2_adapter",
	name         = "r2_adapter0",
	term_left    = 341,
	bump_address = 0x80FF,
	ports = {
		{
			left         = 300,
			data_address = 0x8000
		},
	},
	bus = {
		cpu       = "cpu0",
		bus_index = 3,
	},
}
```

## FILT breakout box

This peripheral exposes a FILT input and output. It is possible to read and write any value that is not *physically zero*.

### I/O range

The breakout box's I/O range is accessible at an address that depends on configuration. There is only one register:

| register | access |
|-|-|
| `value` | read-write |

#### `value` register: read input or write output

Writing a value to this register causes the value to appear on the output in some future frame, always a constant offset in terms of frames from the current frame.

Reading a value from this register returns the value that appeared on the input in some past frame, always a constant offset in terms of frames from the current frame. 

### Configuration

Feel free to ignore this section if to do not plan on making your own custom R316-based saves.

The breakout box connects to a bus. The facing of its input and output, the behaviour of its output, and the address of its I/O range can be configured.

This component is available under the type `"filt_breakout"`.

#### `.bus`

A bus, required, to which the terminal connects. This determines the vertical placement of the bus interfaces the screen and/or the keyboard use.

#### `.base_address`

Integer, required, in the inclusive range `0x0000` to `0xFFFF`. This determines the address of the `value` register.

#### `.left` or `.right`

Integer, at most one of the two allowed. This determines the horizontal placement of the given border (left or right) of the breakout box.

#### `.normally_low`

Integer, optional, defaults to `0`. The bits set in this integer are reset in the output value to `0` every frame in which the `value` register is not written. Thus, the states of these bits are not remembered.

Must not overlap, i.e. have common bits set, with `.normally_high`.

#### `.normally_high`

Integer, optional, defaults to `0`. The bits set in this integer are reset in the output value to `1` every frame in which the `value` register is not written. Thus, the states of these bits are not remembered.

Must not overlap, i.e. have common bits set, with `.normally_low`.

#### `.facing`

String, required, one of `"top"`, `"bottom"`. This determines which way the input and output face.

#### Example configuration

```lua
{
	type          = "filt_breakout",
	name          = "filt_breakout0",
	left          = 320,
	base_address  = 0xA000,
	facing        = "top",
	normally_high = 0xDEAD,
	bus = {
		cpu       = "cpu0",
		bus_index = 0,
	},
}
```

## INST breakout box

This peripheral exposes some INST inputs and outputs.

### I/O range

The breakout box's I/O range is accessible at an address that depends on configuration. There is only one register:

| register | access |
|-|-|
| `value` | read-write |

#### `value` register: read input or write output

Writing a value to this register causes the value to appear on all outputs in some future frame, always a constant offset in terms of frames from the current frame. See below for an explanation on how bits are assigned to outputs. Bits not assigned to any output are ignored. The convention is to set bit 29 to `1`, though this is not required.

Reading a value from this register returns the value that appeared on all inputs in some past frame, always a constant offset in terms of frames from the current frame. See below for an explanation on how bits are assigned to inputs. Bits not assigned to any input are read as `0`. Bit 29 is always read as `1`.

### Configuration

Feel free to ignore this section if to do not plan on making your own custom R316-based saves.

The breakout box connects to a bus. Its set of inputs and outputs, the behaviour of its outputs, and the address of its I/O range can be configured.

This component is available under the type `"inst_breakout"`.

#### `.bus` property

A bus, required, to which the terminal connects. This determines the vertical placement of the bus interfaces the screen and/or the keyboard use.

#### `.base_address` property

Integer, required, in the inclusive range `0x0000` to `0xFFFF`. This determines the address of the `value` register.

#### `.left` or `.right` properties

Integer, at most one of the two allowed. This determines the horizontal placement of the given border (left or right) of the breakout box.

#### `.pins` property

String, required. Each character is one of `"i"`, `"o"`, `"l"`, `"h"`, referring to input, output, normally low output, and normally high output, respectively. Must be at least a single character. Inputs and outputs appear physically from left to right, the first character corresponding to the leftmost input or output, the second to the next, and so on. There can be at most 29 inputs, and at most 29 outputs.

Inputs and outputs are assigned bits also from left to right, starting from bit 0 and increasing. The same bit can be assigned to both an input and an output; the two kinds of ports are assigned bits in two separate sequences.

Changing the value of an output in a frame causes it to be detectably updated in some later frame. A normally low output is reset to `0` every frame in which it is not being thus updated, i.e. the state of this output is not remembered. A normally high output is the same, except it is reset to `1`. An output that is neither normally low nor normally high is sticky, i.e. its state is remembered across updates.

#### Example configuration

```lua
{
	type          = "inst_breakout",
	name          = "inst_breakout0",
	pins          = "oiiioililiiioohhhiioii",
	left          = 350,
	base_address  = 0xB000,
	bus = {
		cpu       = "cpu0",
		bus_index = 0,
	},
}
```
