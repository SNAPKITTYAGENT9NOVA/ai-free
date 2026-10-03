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
| `backend/wasm/` | WebAssembly model, lowering, WAT emission, partial simulation proofs, and `wasmw` |

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

- Forth and BCPL have compilation correctness proofs for their modeled subsets.
  Wolfram-style scalar arithmetic is interpreted modulo the word width, and
  matrix dot products have dedicated correctness results and a worked example.
- The x86-64 model has a whole-program preservation theorem,
  `WordDialect.X86.lowerProg_correct`, in
  [`X86/Correct.lean`](backend/x86_64/X86/Correct.lean). Its assumptions include
  valid memory geometry, bounded code addresses, valid register indices, and
  sufficient stack capacity throughout execution.
- WebAssembly has arithmetic and stack simulation proofs. Whole-program
  preservation is a remaining milestone; it is not currently exported by
  `Wasm.lean`.
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

The current audit reports dependencies of theorems in the `WordDialect`
namespace, allowing Lean's standard `propext`, `Quot.sound`, and
`Classical.choice` axioms. It imports the x86-64 library but does not import
`Wasm`, and it reports unexpected axioms without explicitly failing the command.
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
