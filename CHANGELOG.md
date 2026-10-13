# Changelog

All notable changes to UniversalWord. The version is the one in `lakefile.toml`.

## 0.1.0 — unreleased

The first release. Everything below is proved in Lean 4 (`leanprover/lean4:v4.34.1`) using only
the standard axioms `propext`, `Quot.sound` and `Classical.choice`, which `formal/Audit.lean`
checks in CI, or, for the agreement of the models with real tools and machines, tested by
execution in CI.

### The Universal Word IR (`formal/`)

- Word-level machine semantics: words, memory, the instruction set, traps, the data, return and
  auxiliary stacks, execution relations and a fuel-bounded interpreter proved sound and complete
  against them (#4, #17).
- Checked stack-depth certificates (`WordDialect/Depth.lean`): lower bounds (`certOk`), upper
  bounds against a capacity (`boundOk`), and per-word frame certificates that track each word's
  net stack effect (`frameOk`), each proved sound; untrusted analyses propose them (#34–#36).

### Frontends

- Forth: colon definitions, recursion, variables and constants, `CREATE`/`ALLOT`/`,`,
  `IF`/`ELSE`/`THEN`, `BEGIN … UNTIL`/`WHILE … REPEAT`, `DO … LOOP`/`+LOOP` with `?DO`, `LEAVE`
  and `UNLOOP`, `CASE … ENDCASE`, `>R R> R@`, and the double-cell words
  `UM* UM/MOD M* SM/REM FM/MOD */MOD */`, compiled to the IR with `compile_correct`; a parser that
  implements an inductive grammar exactly, with a proved print/parse round trip (#15–#23).
- A BCPL subset and Wolfram-style integer expressions and matrix products, compiled to the IR
  with correctness proofs (#4).

### Backends, each proved against its machine model and tested under emulation

- x86-64 (#5, #13, #15), WebAssembly (#6, #9, #10, #12, #14), AArch64 (#24, #27) and RISC-V
  RV64IM (#25, #28), with `wordc`, `wasmw`, `a64c` and `rv64c`.
- Microcontroller profiles at 32-bit words, bare metal: RV32IM on the QEMU `virt` board
  (`rv32c`, #29), Cortex-M3 on a Stellaris LM3S6965 (`cmc`, #30) and Cortex-M0 on a BBC micro:bit
  (`cm0c`, #32, with division by a proved loop).
- Cortex-M images boot from flash, with the start-up copy proved (#31).
- Board runtime: UART set-up for the real boards, the end of a run signalled on the UART,
  flashable `.hex` images, the expected serial transcript and a `verify` command
  (`docs/HARDWARE.md`, #33). Not yet run on physical boards.

### Verified optimisation

- The microcontroller backends leave out the stack guards the depth certificates show cannot
  fire, with the certificates' checks as hypotheses of the end-to-end theorems: code is up to
  72% smaller on the Cortex-M0, 60% on the Cortex-M3 and 56% on RV32 (#34–#37). `--no-opt` keeps
  every guard; `stats` counts the guards left out.

### Known limits

- The machine models (and, for the boards, the device set-up) are trusted; agreement with real
  assemblers, emulators and machines is tested, not proved. Physical boards are untested.
- The Forth lexer has no independent specification yet (`NEXT_STEPS.md`).
- Guard elimination is not yet used by the 64-bit backends or WebAssembly.

### License

Parr Source License — No AI Training, Version 1.0 (`License`).
