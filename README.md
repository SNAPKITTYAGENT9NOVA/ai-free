# UniversalWord (`ai-free`)

A Lean 4 formalization of a word-based intermediate language, with frontend
translations and executable x86-64 and WebAssembly backends. The Lake package is
named `UniversalWord`; the GitHub repository is named `ai-free`.

The project defines machine semantics, proves properties of translations, and
compares generated programs against the Lean reference interpreter. Frontend
programs are currently constructed as Lean values. The two command-line tools
run or emit built-in samples; they do not parse arbitrary source files.

## Project structure

| Directory | Purpose |
| --- | --- |
| `formal/` | Word arithmetic, memory, instruction semantics, execution relations, invariants, and axiom audit |
| `word-ir/` | IR fragments, expressions, straight-line programs, and loop reasoning |
| `forth/` | A Forth subset, reference semantics, compilation, and correctness proofs |
| `bcpl/` | A BCPL subset, reference semantics, compilation, and correctness proofs |
| `wolfram/` | Wolfram-style integer scalar expressions and matrix dot products |
| `backend/common/` | Shared samples and differential-testing harness |
| `backend/x86_64/` | x86-64 model, lowering, assembly emission, simulation proofs, and `wordc` |
| `backend/wasm/` | WebAssembly model, lowering, WAT emission, simulation and whole-program preservation proofs, and `wasmw` |

For a file-by-file tour of every Lean module, with diagrams of the pipeline, the proof
structure of each backend and the trust boundaries, see [`docs/README.md`](docs/README.md).

The authoritative IR semantics are in
[`formal/WordDialect/Machine.lean`](formal/WordDialect/Machine.lean).
Words are parameterized by bit width; both executable backends use 64-bit words.
Memory is word-addressed, the data-stack head is its top, and code addresses are
instruction indices.

## Setup

Install Git and [elan](https://github.com/leanprover/elan), the Lean toolchain
manager, and make sure `lean` and `lake` are on your `PATH`. The repository pins
`leanprover/lean4:v4.34.1` in `lean-toolchain`; elan selects it automatically.
The Lake manifest currently lists no external packages.

```sh
git clone https://github.com/SNAPKITTYWEST/ai-free.git
cd ai-free
lake build
```

`lake build` builds the libraries and both executable harnesses.

For native execution checks, use **x86-64 Linux** with GNU `as` and `ld`
(typically supplied by the `binutils` package). For WebAssembly execution
checks, install [Wasmtime](https://github.com/bytecodealliance/wasmtime/releases).
CI uses Wasmtime **v30.0.2**. Put `wasmtime` on your `PATH`, or set `WASMTIME` to
the executable's path. Building and emitting samples do not require Wasmtime.

## Run the examples

After building, run the fixed sample suite and 300 generated programs for each
backend:

```sh
.lake/build/bin/wordc check 300
.lake/build/bin/wasmw check 300
```

Omitting the count defaults to 200 generated programs. `check 0` runs just the
fixed samples. The harness uses a fixed random seed and compares trap codes or
the final data stack, memory, and virtual registers with Lean execution.
Programs that exceed the reference interpreter's fuel are reported as skipped.

Emit GNU assembly or WebAssembly text for a built-in sample:

```sh
.lake/build/bin/wordc emit forth_five_dup_plus > /tmp/forth_five_dup_plus.s
.lake/build/bin/wasmw emit forth_five_dup_plus > /tmp/forth_five_dup_plus.wat
```

Other sample names include `bcpl_sum_1_to_10`, `wolfram_dot_2x2`, and
`raw_call_ret`. See `allSamples` and its component lists in
[`backend/common/Harness.lean`](backend/common/Harness.lean) for the full list.
Execution checks write temporary artifacts under `/tmp/wordc` and `/tmp/wasmw`.

Run a Forth source file on either backend. The file is parsed by `Forth.parse`,
compiled, run on the target, and compared with the Lean semantics; the optional
last argument is the number of IR memory words (default 16):

```sh
.lake/build/bin/wordc forth examples/forth/fib.fs
.lake/build/bin/wasmw forth examples/forth/memory.fs 16
.lake/build/bin/wordc emit-forth examples/forth/sum.fs > /tmp/sum.s
```

[`examples/forth/`](examples/forth) has sample programs, including a recursive
word, a trap two calls deep, `DO … LOOP` / `>R R>` (`loops.fs`), and `+LOOP`, `?DO`,
`LEAVE` and `UNLOOP` (`leave.fs`).

## Proof and validation status

- Forth has a compilation correctness proof for its modeled subset, including
  colon definitions (`: name ... ;`, recursion and `RECURSE` allowed) lowered
  to IR `call`/`ret`, `EXIT` (lowered to `ret`), `VARIABLE` (memory cells
  `0 … k-1`), `CONSTANT`, `0=`, `MOD`, the return-data stack words
  `>R R> R@` (lowered to the IR auxiliary stack `tor`/`fromr`/`rfetch`, which
  `call`/`ret` never touch), `DO … LOOP` and `DO … +LOOP` with `I`, `J`,
  `LEAVE` and `UNLOOP` (loop parameters on that stack, so they survive calls
  and recursion; `+LOOP` uses ANS Forth's crossing rule, proved in
  [`Forth/LoopProps.lean`](forth/Forth/LoopProps.lean)), and `?DO`:
  `WordDialect.Forth.Program.compile_correct` in
  [`Forth/Correct.lean`](forth/Forth/Correct.lean). Because the return-data
  stack is separate from call frames, unbalanced `>R`/`R>` across `EXIT` or a
  call is defined behaviour (see `Forth/Semantics.lean`). Forth source text is parsed by `Forth.parse`
  ([`Forth/Parse.lean`](forth/Forth/Parse.lean)); `Forth.print` prints a
  program back, and `WordDialect.Forth.parse_print` proves
  `parse (print P) = .ok P` for every well-formed program
  ([`Forth/Print.lean`](forth/Forth/Print.lean)). Conversely,
  `WordDialect.Forth.parse_wf` proves that every successful parse yields a
  well-formed program, so `print` is a canonical form
  (`parse_print_of_parse`), and lemmas characterise the text `print` never
  emits: `parse_toUpper` (upper-casing the source does not change the result,
  up to the spelling in error messages), `tokenize_paren_comment` /
  `tokenize_line_comment` (comments tokenize like whitespace, with stated side
  conditions), `parseTop_constant` / `classify_constant` (`n CONSTANT X` makes
  `X` the literal `n`) and `classify_recurse` / `parseSeq_recurse_name`
  (`RECURSE` is a call of the word being defined)
  ([`Forth/ParseProps.lean`](forth/Forth/ParseProps.lean)). The parser
  implements an inductive grammar exactly (`WordDialect.Forth.Grammar.parse_iff`)
  and never runs out of fuel (`Grammar.parse_ne_fuel`)
  ([`Forth/Grammar.lean`](forth/Forth/Grammar.lean)); examples in
  [`Forth/TextExample.lean`](forth/Forth/TextExample.lean).
  BCPL has a compilation correctness proof for its modeled subset.
  Wolfram-style scalar arithmetic is interpreted modulo the word width, and
  matrix dot products have dedicated correctness results and a worked example.
- The x86-64 model has whole-program preservation theorems in
  [`X86/Correct.lean`](backend/x86_64/X86/Correct.lean). The generated code
  checks for room before every instruction that grows the data stack, before
  every `call` (the return stack is the native stack, capped at 65536 entries
  below the entry `rsp`), and before every `tor` (the auxiliary stack is its
  own `.astack` region with pointer `rbp`, so native `call`/`ret` never touch
  it), and exits with code 6 when the stack is full. `fromr`/`rfetch` on an
  empty auxiliary stack trap with code 5, as in the IR.
  `WordDialect.X86.lowerProg_correct_or_overflow` has no stack-capacity
  assumption: the code reaches the IR outcome or exits 6.
  `WordDialect.X86.lowerProg_correct` adds the assumption that the run stays
  within capacity, and then the outcome is exactly the IR's. Both assume valid
  memory geometry, bounded code addresses, and valid register indices.
  `wordc check` also runs raw auxiliary-stack programs (balanced use across
  calls and recursion, `R@`, both traps) against the Lean semantics, and four
  unbounded programs (one of them a `tor` loop) that must exit 6.
  `WordDialect.X86.Emit.binary_correct` starts from the binary's entry point:
  the runtime prologue's effect is proved, and what the loader provides at
  `_start` (entry `rsp`, the `.data` image, the zero-filled `.bss` register
  file, addressable regions including `.dstack` and `.astack`, disjoint
  placement) is one explicit assumption,
  `Loader.Holds`. From there the code reaches the IR outcome from `State.init`,
  or exits 6. Its program hypotheses are `17 * length < 2^64` and valid
  register indices. See [`X86/Init.lean`](backend/x86_64/X86/Init.lean).
- The WebAssembly model has whole-program preservation theorems in
  [`Wasm/Correct.lean`](backend/wasm/Wasm/Correct.lean). Running the dispatch
  loop from a related state halts in a related state when the IR halts, and
  exits with the matching trap code (1 underflow, 2 bad address, 3 divide by
  zero, 4 bad pc, 5 return underflow, also for `fromr`/`rfetch` on an empty
  auxiliary stack) when the IR traps. The auxiliary stack (`tor`/`fromr`/
  `rfetch`) lives in its own linear-memory region with pointer global `$ap`,
  disjoint from the data stack, return stack, register file and IR memory. The
  generated code checks for room before every instruction that grows the data,
  return or auxiliary stack, and exits with code 6 when the stack is full (IR
  stacks are unbounded, so code 6 has no IR counterpart).
  `WordDialect.Wasm.lowerProg_correct_or_overflow` has no stack-capacity
  assumption: the module reaches the IR outcome or exits 6.
  `WordDialect.Wasm.lowerProg_correct` adds the assumption that the run stays
  within capacity, and then the outcome is exactly the IR's. Both assume valid
  memory geometry within 32-bit linear memory, fewer than `2^32` instructions,
  and valid register indices. `wasmw check` also runs raw IR programs for the
  auxiliary stack against the Lean semantics, and four unbounded programs
  (including an unbounded `tor` loop) that must exit 6.
  `WordDialect.Wasm.Emit.module_correct` closes the loop from the emitted
  module: from the state WebAssembly instantiation produces for its
  declarations (globals, zeroed memory, the IR memory image as a data segment),
  the start function reaches the IR outcome from `State.init`, or exits 6. Its
  only hypotheses are about the program: the register file and memory image fit
  the runtime layout, fewer than `2^32` instructions, and valid register
  indices. The proof modules, all exported by `Wasm.lean`:

  | Module | Contents |
  | --- | --- |
  | `Wasm/Mem.lean`, `Wasm/Rel.lean`, `Wasm/Frame.lean` | Byte-memory read/write lemmas, the IR–WebAssembly state relation, and per-region write framing |
  | `Wasm/Seq.lean`, `Wasm/Guard.lean` | Straight-line execution, sequencing, and the operand-count and overflow guards |
  | `Wasm/SimAlu.lean`, `Wasm/SimAlu2.lean`, `Wasm/SimStack.lean` | Arithmetic, comparison, shift, division, and stack/register instructions |
  | `Wasm/SimMem.lean` | Address bounds check, `load`, `store`, and their bad-address traps |
  | `Wasm/SimCtl.lean` | `jmp`, `branch`, `call`, `ret` (and its underflow trap), `halt`, and the bad-pc stub |
  | `Wasm/SimAux.lean` | Auxiliary stack: `tor`, `fromr`, `rfetch`, their empty-stack traps and overflow exits |
  | `Wasm/SimExec.lean` | One-step simulation for every instruction and outcome (`sim_step`) |
  | `Wasm/Correct.lean` | Dispatch-loop induction (`lowerProg_correct_or_overflow`, `lowerProg_correct`) and entry relation (`init_rel`) |
  | `Wasm/Init.lean` | The instantiated module's state, the runtime layout's geometry, and the end-to-end `module_correct` |
- Proofs concern the defined machine models. The emitted artifacts are also
  tested through real assemblers/runtimes; those execution checks are separate
  evidence from the formal proofs.

The [CI workflow](.github/workflows/lean.yml) builds the project, rejects proof
placeholders and explicit axiom declarations, runs the axiom audit, and checks
both backends with 300 generated programs each.

Run the audit after building:

```sh
lake env lean formal/Audit.lean
```

The audit reports the axiom dependencies of every theorem in the `WordDialect`
namespace across all libraries, including both backends. Lean's standard
`propext`, `Quot.sound`, and `Classical.choice` are allowed; any other axiom is
reported as an error, so the command (and CI) fails.
See [next steps](NEXT_STEPS.md) for proposed improvements.

## Contributing

Start with [`Forth/Example.lean`](forth/Forth/Example.lean),
[`BCPL/Example.lean`](bcpl/BCPL/Example.lean), or
[`Wolfram/MatrixExample.lean`](wolfram/Wolfram/MatrixExample.lean).
For a new operation, define its semantics, add the relevant correctness proof,
and add a fixed execution sample to the shared harness. Run `lake build`, the
audit, and both backend checks before submitting a change. Follow CI's prohibition
on proof placeholders, `native_decide`, and explicit axiom declarations.

See [NEXT_STEPS.md](NEXT_STEPS.md) for a suggested development order.

## License

FSL
