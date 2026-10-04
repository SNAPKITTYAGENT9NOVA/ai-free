# Next steps

Suggested development order. Each item names the gap it closes in the current code.

## 1. Forth: the converse parser direction, and return-stack words

Colon definitions (lowered to IR `call`/`ret`), `RECURSE`, `EXIT`, `VARIABLE`,
`CONSTANT`, `0=` and `MOD` are covered by `Forth.Program.compile_correct`; a
text parser (`Forth.parse`) and a printer (`Forth.print`) exist, with the round
trip `parse (print P) = .ok P` proved for well-formed programs
(`Forth.parse_print`). `wordc forth` / `wasmw forth` run a Forth source file
on either backend. Remaining:

- The round trip shows `parse` inverts `print`; the converse direction is not
  proved (that every successful `parse` yields a `Program.WF` program, and what
  `parse` does on text `print` never produces: comments, lower case,
  `CONSTANT`, `RECURSE`). Those are checked on concrete inputs only.
- `>R R>` and `DO … LOOP` (with `I`) are not implemented, because the current
  IR has no faithful place for return-stack data. Its return stack holds code
  addresses only and is touched only by `call`/`ret`. Values left on the data
  stack sit at a depth the loop body or the code between `>R` and `R>` can
  change. The virtual registers are one global file, so a register per nesting
  level is overwritten when a word recurses (or another word uses it) before
  the value is read back. A software stack in IR memory would survive
  recursion, but it shares the address space of `@`/`!` (a program can
  overwrite it) and is bounded by the valid cells, so it would not match Forth's
  separate return stack unless every `@`/`!` were guarded and overflow given a
  trap the Forth semantics also has. The IR feature needed is instructions that
  move a data word to and from a stack preserved by `call`/`ret`, e.g.
  `rpush`/`rpop`/`rpeek` on a return stack of words (or a separate auxiliary
  stack), implemented by the backends on the native stack.

## Ongoing

The formal results cover the Lean machine models. Their agreement with real
assemblers and runtimes is checked by execution, not proved: keep running
`wordc check` and `wasmw check` (CI uses Wasmtime v30.0.2) after every change to
a model, lowering or emitter.
