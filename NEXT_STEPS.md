# Next steps

Suggested development order. Each item names the gap it closes in the current code.

## 1. Forth: word definitions and a text frontend

The Forth subset has no colon definitions, and programs are built as Lean
values; neither command-line tool parses source files.

- Add `: name ... ;` definitions lowered to IR `call`/`ret`, with a correctness
  proof extending the existing Forth compilation theorem.
- Add a tokenizer and parser for Forth source text, so samples can be written
  as text rather than Lean terms.

## Ongoing

The formal results cover the Lean machine models. Their agreement with real
assemblers and runtimes is checked by execution, not proved: keep running
`wordc check` and `wasmw check` (CI uses Wasmtime v30.0.2) after every change to
a model, lowering or emitter.
