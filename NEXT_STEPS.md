# Next steps

Suggested development order. Each item names the gap it closes in the current code. The
longer-term direction is in [`docs/GAME_PLAN.md`](docs/GAME_PLAN.md).

## Done: Forth control structures, parser fuel and grammar

Colon definitions (lowered to IR `call`/`ret`), `RECURSE`, `EXIT`, `VARIABLE`,
`CONSTANT`, `CREATE`, `ALLOT`, `,`, `0=`, `MOD`, `/MOD`, `NEGATE`, `ABS`, `MIN`, `MAX`,
`?DUP`, `2DUP 2DROP 2SWAP`, `CASE … OF … ENDOF … ENDCASE`, the double-cell words
`UM* UM/MOD M* SM/REM FM/MOD */MOD */`, the return-data stack words
`>R R> R@`, `BEGIN … WHILE … REPEAT`,
`DO … LOOP` and `DO … +LOOP` with `I`, `J`, `LEAVE` and `UNLOOP`, and `?DO` are covered by
`Forth.Program.compile_correct`. `+LOOP` uses ANS Forth's crossing rule,
proved in `Forth/LoopProps.lean` (`loopCrossed_eq_saddOverflow`; with step one
it is the `LOOP` rule, `loopCrossed_one`). The parser implements an inductive
grammar exactly (`Forth/Grammar.lean`: `parse_iff`, unambiguous by
`Prog.unique`), its fuel is irrelevant (`parseSeq_fuel`), and the fuel errors
are unreachable (`parse_ne_fuel`).

Choices made there, which a later change may want to revisit:

- `?DUP` and `CASE … ENDCASE` are parsed into `IF`s (an `OF` clause pushes a
  placeholder that `ENDCASE` drops, so every path drops exactly one item).
- `CREATE`, `ALLOT` and `,` work at top level, at parse time, like `VARIABLE`;
  `ALLOT` and `,` take a literal just before them, as `CONSTANT` does.
- `?DO` is not a separate construct: it parses to
  `OVER OVER = IF DROP DROP ELSE DO … LOOP THEN`, so `print` writes that form.
- `LEAVE` is rejected by the parser outside a loop of its own block, but its
  semantics is still total: outside a loop it removes two return-data items and
  ends the word (or the main block).
- The double-cell words are loops of single-word instructions in the IR
  (`Forth/Double.lean`), not new IR instructions, so neither backend changed; they
  use virtual registers 0–7. `*/` and `*/MOD` use symmetric division (`SM/REM`),
  like `/` and `MOD`, and trap `divideByZero` when the quotient does not fit.
- The grammar is stated over tokens and the token classification `classify`.
  The lexer (`tokenize`) is characterised by lemmas (comments, case) rather than
  by its own grammar.

## Done: AArch64 backend

`backend/arm64` lowers the IR to AArch64 with the x86-64 backend's register roles and proof
structure, and proves it end to end (`A64.Emit.binary_correct`). `a64c` runs the emitted code
under `qemu-aarch64` and compares with Lean; CI runs it. Choices a later change may revisit:
the return stack is a linked `.rstack` section (not the OS stack), and the model treats the
flags as unknown after arithmetic (AArch64 leaves them unchanged).

## Done: RISC-V backend

`backend/riscv64` lowers the IR to RV64IM and proves it end to end
(`RV.Emit.binary_correct`). RISC-V has no condition flags: guards, `cmp` and `select` are
compare-and-branch sequences, and the model's branch takes the IR's own `Cond`. `rv64c` runs
the emitted code under `qemu-riscv64`; CI runs it.

## Done: microcontroller profile (RV32)

`backend/rv32` lowers the 32-bit IR (`Prog 32`) to RV32IM and proves it end to end
(`RV32.Emit.binary_correct`), with a bare-metal runtime (UART output, test-device exit, no
operating system). `rv32c` runs it on the QEMU `virt` board with no firmware; CI runs it.
Choices a later change may revisit: the image runs from RAM (no flash-to-RAM copy of `.data`),
the device addresses are those of the `virt` board, and the stacks hold 4096 words each.

## Done: Cortex-M profile

`backend/cortexm` lowers the 32-bit IR to Thumb-2 (ARMv7-M) and proves it end to end
(`CM.Emit.binary_correct`), with a bare-metal runtime (vector table, CMSDK UART output,
semihosting exit). `cmc` runs it on an emulated Cortex-M3 (`qemu-system-arm -M mps2-an385`); CI
runs it. Choices a later change may revisit: the image runs from RAM, the stop uses semihosting
(a board without a debugger needs another end-of-run signal), the UART is the MPS2 board's, and
the cell address uses `lsl` and `add` rather than Thumb-2's indexed `ldr`.

## 1. Forth: double-cell storage and arithmetic

The double-cell storage words (`2@ 2! 2VARIABLE`) and double-cell arithmetic
(`D+ D- DNEGATE D<`) are not implemented. They can be built from the same
single-word instructions as the double-cell words, with an explicit carry.

## 2. Lexer specification

Give `tokenize` an independent specification (a token is a maximal run of
non-whitespace characters, outside comments) and prove `tokenize` meets it, so
that `parse_iff` composes into a statement about characters.

## Ongoing

The formal results cover the Lean machine models. Their agreement with real
assemblers and runtimes is checked by execution, not proved: keep running
`wordc check`, `wasmw check`, `a64c check`, `rv64c check`, `rv32c check` and `cmc check`
(CI uses Wasmtime v30.0.2, `qemu-aarch64`, `qemu-riscv64`, `qemu-system-riscv32` and
`qemu-system-arm`) after every change to
a model, lowering or emitter.
