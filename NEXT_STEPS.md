# Next steps

Suggested development order. Each item names the gap it closes in the current code.

## 1. Make the axiom audit cover everything and fail loudly

[`formal/Audit.lean`](formal/Audit.lean) imports every library except `Wasm`, and
it only logs theorems that use non-standard axioms (`logInfo`), so the command
exits successfully either way.

- Add `import Wasm` so the WebAssembly proofs are audited too.
- Report offending theorems with `logError`, so `lake env lean formal/Audit.lean`
  (and CI) fails when any theorem depends on an axiom beyond `propext`,
  `Quot.sound` and `Classical.choice`.

## 2. Discharge the stack-capacity hypothesis

Both whole-program theorems (`X86.lowerProg_correct`, `Wasm.lowerProg_correct`)
assume the IR run never exceeds the data-stack or return-stack capacity
(`Fits`), because the generated code does not check for overflow. Options:

- Emit an overflow guard before every push and every `call`, add an overflow
  trap code, and prove the guard so `Fits` is no longer a hypothesis; or
- Prove a static bound on stack depth for programs produced by the frontends,
  and derive `Fits` from it.

## 3. Prove the runtime establishes the entry relation

`Wasm.init_rel` (and `X86.init_rel`) take the initial machine state as
hypotheses: empty operand stack, `pc = 0`, `sp = dEnd`, `rp = rEnd`, and the
register file and IR memory regions holding the IR state's contents. The
prologue that sets this up is emitted as text in `Wasm/Emit.lean` and is not
modelled. Modelling the prologue (globals initialisation and data segments)
would let the end-to-end theorem start from the module's actual entry state.

## 4. Remove the unused WebAssembly `Rel`

`Rel` in [`backend/wasm/Wasm/Rel.lean`](backend/wasm/Wasm/Rel.lean) relates the
`pc` global to the unclamped IR `pc` and is not used by any proof. The
dispatch-loop invariant actually used is `RelD` in
[`Wasm/Correct.lean`](backend/wasm/Wasm/Correct.lean), which clamps the `pc` to
the program length. Delete `Rel` or replace it with `RelD`.

## 5. Forth: word definitions and a text frontend

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
