# Next steps

Suggested development order. Each item names the gap it closes in the current code.

## Done: Forth control structures, parser fuel and grammar

Colon definitions (lowered to IR `call`/`ret`), `RECURSE`, `EXIT`, `VARIABLE`,
`CONSTANT`, `0=`, `MOD`, the return-data stack words `>R R> R@`, `BEGIN … WHILE … REPEAT`,
`DO … LOOP` and `DO … +LOOP` with `I`, `J`, `LEAVE` and `UNLOOP`, and `?DO` are covered by
`Forth.Program.compile_correct`. `+LOOP` uses ANS Forth's crossing rule,
proved in `Forth/LoopProps.lean` (`loopCrossed_eq_saddOverflow`; with step one
it is the `LOOP` rule, `loopCrossed_one`). The parser implements an inductive
grammar exactly (`Forth/Grammar.lean`: `parse_iff`, unambiguous by
`Prog.unique`), its fuel is irrelevant (`parseSeq_fuel`), and the fuel errors
are unreachable (`parse_ne_fuel`).

Choices made there, which a later change may want to revisit:

- `?DO` is not a separate construct: it parses to
  `OVER OVER = IF DROP DROP ELSE DO … LOOP THEN`, so `print` writes that form.
- `LEAVE` is rejected by the parser outside a loop of its own block, but its
  semantics is still total: outside a loop it removes two return-data items and
  ends the word (or the main block).
- The grammar is stated over tokens and the token classification `classify`.
  The lexer (`tokenize`) is characterised by lemmas (comments, case) rather than
  by its own grammar.

## 1. Forth: more of the core word set

Not implemented: `?DUP`, `2DUP`, `2DROP`, `2SWAP`, `*/`, `/MOD`, `NEGATE`,
`ABS`, `MIN`, `MAX`, `CREATE`/`ALLOT`/`,`, and `CASE … OF … ENDOF … ENDCASE`.
Most are straight-line and need only `Op.sem`, `compileOp` and a parser
entry (`compileOp_ok` / `compileOp_err` are proved by one tactic for every
operation).

## 2. Lexer specification

Give `tokenize` an independent specification (a token is a maximal run of
non-whitespace characters, outside comments) and prove `tokenize` meets it, so
that `parse_iff` composes into a statement about characters.

## Ongoing

The formal results cover the Lean machine models. Their agreement with real
assemblers and runtimes is checked by execution, not proved: keep running
`wordc check` and `wasmw check` (CI uses Wasmtime v30.0.2) after every change to
a model, lowering or emitter.
