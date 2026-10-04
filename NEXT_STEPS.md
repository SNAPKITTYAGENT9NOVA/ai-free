# Next steps

Suggested development order. Each item names the gap it closes in the current code.

## 1. Forth: parser fuel and a grammar specification

Colon definitions (lowered to IR `call`/`ret`), `RECURSE`, `EXIT`, `VARIABLE`,
`CONSTANT`, `0=`, `MOD`, the return-data stack words `>R R> R@` and
`DO … LOOP` with `I` and `J` are covered by `Forth.Program.compile_correct`.
The return-data stack is the IR's auxiliary stack (`tor`/`fromr`/`rfetch`),
which `call`/`ret` never touch, so loop parameters and `>R` values survive
calls and recursion, and unbalanced use across `EXIT` or a call is defined
behaviour. A text parser (`Forth.parse`) and a printer (`Forth.print`) exist,
with the round trip `parse (print P) = .ok P` proved for well-formed programs
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
- Not implemented: `+LOOP`, `?DO`, `LEAVE` and `UNLOOP`. `LOOP` uses only the
  equal case of ANS Forth's crossing rule (it ends when `index + 1 = limit`),
  which is exact for a step of one; `+LOOP` would need the full rule.

## Ongoing

The formal results cover the Lean machine models. Their agreement with real
assemblers and runtimes is checked by execution, not proved: keep running
`wordc check` and `wasmw check` (CI uses Wasmtime v30.0.2) after every change to
a model, lowering or emitter.
