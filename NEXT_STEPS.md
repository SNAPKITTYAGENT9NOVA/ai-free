# Next steps

Suggested development order. Each item names the gap it closes in the current code.

## 1. Forth: source files on the command line, and a wider subset

Colon definitions (lowered to IR `call`/`ret`, proved in
`Forth.Program.compile_correct`) and a text parser (`Forth.parse`) exist, and
harness samples can be written as Forth source. Remaining:

- Let `wordc` and `wasmw` compile a Forth source file given on the command
  line (today the text frontend is reached only through harness samples).
- The parser is tested, not proved; a printer from `Program` back to text with
  a proved round trip (`parse (print P) = .ok P`) would close that gap.
- Common words outside the subset: `EXIT`, `RECURSE`, `>R R>`, `DO … LOOP`,
  `VARIABLE`/`CONSTANT`, `0=`, `MOD`.

## Ongoing

The formal results cover the Lean machine models. Their agreement with real
assemblers and runtimes is checked by execution, not proved: keep running
`wordc check` and `wasmw check` (CI uses Wasmtime v30.0.2) after every change to
a model, lowering or emitter.
