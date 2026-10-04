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

## Proof and validation status

- Forth has a compilation correctness proof for its modeled subset, including
  colon definitions (`: name ... ;`, recursion allowed) lowered to IR
  `call`/`ret`: `WordDialect.Forth.Program.compile_correct` in
  [`Forth/Correct.lean`](forth/Forth/Correct.lean). Forth source text is parsed
  by `Forth.parse` ([`Forth/Parse.lean`](forth/Forth/Parse.lean)); the parser
  is not verified, only checked on concrete inputs
  ([`Forth/TextExample.lean`](forth/Forth/TextExample.lean)) and by the
  harness samples written as source text.
  BCPL has a compilation correctness proof for its modeled subset.
  Wolfram-style scalar arithmetic is interpreted modulo the word width, and
  matrix dot products have dedicated correctness results and a worked example.
- The x86-64 model has whole-program preservation theorems in
  [`X86/Correct.lean`](backend/x86_64/X86/Correct.lean). The generated code
  checks for room before every instruction that grows the data stack and before
  every `call` (the return stack is the native stack, capped at 65536 entries
  below the entry `rsp`), and exits with code 6 when the stack is full.
  `WordDialect.X86.lowerProg_correct_or_overflow` has no stack-capacity
  assumption: the code reaches the IR outcome or exits 6.
  `WordDialect.X86.lowerProg_correct` adds the assumption that the run stays
  within capacity, and then the outcome is exactly the IR's. Both assume valid
  memory geometry, bounded code addresses, and valid register indices.
  `wordc check` also runs three unbounded programs and requires exit 6.
  `WordDialect.X86.Emit.binary_correct` starts from the binary's entry point:
  the runtime prologue's effect is proved, and what the loader provides at
  `_start` (entry `rsp`, the `.data` image, the zero-filled `.bss` register
  file, addressable regions, disjoint placement) is one explicit assumption,
  `Loader.Holds`. From there the code reaches the IR outcome from `State.init`,
  or exits 6. Its program hypotheses are `17 * length < 2^64` and valid
  register indices. See [`X86/Init.lean`](backend/x86_64/X86/Init.lean).
- The WebAssembly model has whole-program preservation theorems in
  [`Wasm/Correct.lean`](backend/wasm/Wasm/Correct.lean). Running the dispatch
  loop from a related state halts in a related state when the IR halts, and
  exits with the matching trap code (1 underflow, 2 bad address, 3 divide by
  zero, 4 bad pc, 5 return underflow) when the IR traps. The generated code
  checks for room before every instruction that grows the data or return
  stack, and exits with code 6 when the stack is full (IR stacks are
  unbounded, so code 6 has no IR counterpart).
  `WordDialect.Wasm.lowerProg_correct_or_overflow` has no stack-capacity
  assumption: the module reaches the IR outcome or exits 6.
  `WordDialect.Wasm.lowerProg_correct` adds the assumption that the run stays
  within capacity, and then the outcome is exactly the IR's. Both assume valid
  memory geometry within 32-bit linear memory, fewer than `2^32` instructions,
  and valid register indices. `wasmw check` also runs three unbounded programs
  and requires exit 6.
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
