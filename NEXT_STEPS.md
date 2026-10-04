# Next steps

Suggested development order. Each item names the gap it closes in the current code.

## 1. Forth: the converse parser direction, and return-stack words

Colon definitions (lowered to IR `call`/`ret`), `RECURSE`, `EXIT`, `VARIABLE`,
`CONSTANT`, `0=` and `MOD` are covered by `Forth.Program.compile_correct`; a
text parser (`Forth.parse`) and a printer (`Forth.print`) exist, with the round
trip `parse (print P) = .ok P` proved for well-formed programs
(`Forth.parse_print`). The converse direction is proved in
`Forth/ParseProps.lean`: every successful parse is well formed (`parse_wf`), so
`print` is a canonical form (`parse_print_of_parse`), and the handling of case,
comments, `CONSTANT` and `RECURSE` is characterised by lemmas. `wordc forth` /
`wasmw forth` run a Forth source file on either backend. Remaining:

- The parser lemmas have side conditions where the text-level statement would
  otherwise be false (a `( … )` comment body without `)`, `\` or newline, after
  text not ending inside a `(` comment; case-insensitivity up to the spelling in
  error messages). Not proved: that the fuel bounds of `parseSeq`/`parseTop`
  are never exhausted (the "too deeply nested" / "too long" errors are
  unreachable), and a full specification of `parse` as a grammar.
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
