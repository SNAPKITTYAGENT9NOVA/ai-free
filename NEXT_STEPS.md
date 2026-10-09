# Next steps

Suggested development order. Each item names the gap it closes in the current code.

## Done: Forth control structures, parser fuel and grammar

Colon definitions (lowered to IR `call`/`ret`), `RECURSE`, `EXIT`, `VARIABLE`,
`CONSTANT`, `CREATE`, `ALLOT`, `,`, `0=`, `MOD`, `/MOD`, `NEGATE`, `ABS`, `MIN`, `MAX`,
`?DUP`, `2DUP 2DROP 2SWAP`, `CASE … OF … ENDOF … ENDCASE`, the double-cell words
`UM* UM/MOD M* SM/REM */MOD */`, the return-data stack words
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

## 1. Forth: floored division

`FM/MOD` (floored division of a double-cell number) is not implemented. It can be
built like `SM/REM`, adjusting quotient and remainder when the signs differ and
the remainder is nonzero. The double-cell storage words (`2@ 2! 2VARIABLE`) and
double-cell arithmetic (`D+ D- DNEGATE`) are not implemented either.

## 2. Lexer specification

Give `tokenize` an independent specification (a token is a maximal run of
non-whitespace characters, outside comments) and prove `tokenize` meets it, so
that `parse_iff` composes into a statement about characters.

## Ongoing

The formal results cover the Lean machine models. Their agreement with real
assemblers and runtimes is checked by execution, not proved: keep running
`wordc check` and `wasmw check` (CI uses Wasmtime v30.0.2) after every change to
a model, lowering or emitter.
