# UniversalWord: follow the word

**Three source-language perspectives. One word machine. Two executable destinations. A Lean file for every stage of the journey.**

UniversalWord, hosted here as `ai-free`, brings Forth, a BCPL subset, and Wolfram-style scalar and matrix computations into a shared intermediate language. Its central character is the machine word: a fixed-width value that can carry an integer, a truth flag, or a memory address. Around that value, the project builds reference semantics, translations, reusable proofs, target machine models, emitters, and executable comparison harnesses.

Think of this repository as a railway atlas. The source frontends are departure stations. Universal Word IR is the interchange where their different expressions become a common instruction stream. The x86-64 and WebAssembly backends are two routes onward. The Lean modules describe the track, establish how each connection behaves, and carry the argument from a source computation to a target outcome.

This README is your guided journey through that atlas. Every Lean file receives an individual stop, with a link, a description, and a reason to open it. You can follow the whole route or jump directly to the part that interests you: writing Forth, understanding compiler correctness, exploring matrix multiplication, inspecting native assembly, or studying WebAssembly dispatch.

**Inventory note:** the surveyed `master` snapshot, commit [`93d6d84`](https://github.com/SNAPKITTYWEST/ai-free/tree/93d6d84fe80d3b7f333e31324b35ba27a964b9cc), contained **81 `.lean` files**; `Forth/LoopProps.lean` and `Forth/Grammar.lean` have since been added. The numbered atlas below covers all 83, including library entry files, executable entry points, and the audit. The count follows the actual source tree so every link leads to an existing file. A more technical file-by-file tour, with Mermaid diagrams of the pipeline, each backend's proof structure and the trust boundaries, is in [`docs/README.md`](docs/README.md).

## Choose your route

| Destination | Start here | What you will discover |
| --- | --- | --- |
| A first working example | [Forth.Example](forth/Forth/Example.lean) | How `5 DUP +` becomes a machine computation |
| Forth source text | [Forth.Parse](forth/Forth/Parse.lean) | Definitions, variables, comments, recursion, and loops |
| The common machine | [WordDialect.Machine](formal/WordDialect/Machine.lean) | Instructions, state, outcomes, and authoritative execution |
| Reusable compiler proofs | [WordIR.Frag](word-ir/WordIR/Frag.lean) | How verified control-flow fragments compose |
| Memory-oriented source programs | [BCPL.Semantics](bcpl/BCPL/Semantics.lean) | Word expressions, indirection, assignment, and statements |
| Mathematical computations | [Wolfram.MatrixExample](wolfram/Wolfram/MatrixExample.lean) | A concrete matrix product and its formal ingredients |
| Native execution | [X86.Lower](backend/x86_64/X86/Lower.lean) | Register conventions, assembly sequences, and guards |
| WebAssembly execution | [Wasm.Lower](backend/wasm/Wasm/Lower.lean) | Instruction functions and the dispatch loop |
| Proof dependency inspection | [Audit](formal/Audit.lean) | The project's namespace-wide axiom audit |

The numbered entries are arranged by the computation's journey rather than alphabetical order. Within each region, the order moves from vocabulary and execution toward translation, correctness, examples, and public imports. This makes the map useful both as a reference and as a reading course.

## Before departure: the machine's vocabulary

A `Word n` is a Lean `BitVec n`. Addition, subtraction, and multiplication follow fixed-width modular arithmetic. A pointer interprets the same representation as a word address. Source-level arithmetic therefore has a precise destination: a bit-vector result, with signed and unsigned interpretations used where the operation calls for them.

The IR uses word-addressed memory. Address `a` selects one word; a 64-bit backend places that cell at a corresponding byte address separated by eight bytes. Its data stack is a list with the top at the head. For a binary expression written as `a b op`, `b` is on top and the result is `a op b`. Keeping that convention in mind makes the instruction definitions and compiler output much easier to follow.

Control addresses are instruction indices. The machine has virtual registers, a data stack, a return stack of code addresses, and a separate auxiliary stack of words. Calls and returns use the code-address stack. Forth's return-data operations use the auxiliary stack. That separation lets saved data and loop parameters survive calls and recursion, and it carries through both backends.

Execution can continue, halt, or trap. The executable targets report the shared traps with a common vocabulary:

| Exit code | Meaning |
| --- | --- |
| `0` | Successful halt |
| `1` | Data-stack underflow |
| `2` | Bad memory address |
| `3` | Division by zero |
| `4` | Bad program counter |
| `5` | Return-stack or auxiliary-stack underflow |
| `6` | Target stack capacity exceeded |

The IR describes unbounded stacks. The targets provide finite regions and check capacity before growing them. Their correctness results incorporate that relationship: a target reaches the IR outcome or reports overflow; when the execution stays within capacity, it reaches exactly the IR outcome. These are useful, explicit contracts to keep beside the rest of the tour.

## Station I: the common word machine — files 1–10

Every route passes through this region. Its definitions give the shared instruction stream meaning, and its theorems provide the language used throughout the frontend and backend proofs.

### 1. [Word.lean](formal/WordDialect/Word.lean) — the value carried everywhere

Defines `Word n`, pointer interpretation, comparison conditions, truth conversion, shifts, and rotations. Its lemmas establish pointer round trips and numeric behavior.

### 2. [Memory.lean](formal/WordDialect/Memory.lean) — the address book

Defines word cells, address validity, and optional reads and writes. The accompanying theorems describe reading a written cell, preserving other cells, and commuting independent writes.

### 3. [Machine.lean](formal/WordDialect/Machine.lean) — the interchange

Defines the IR instructions, traps, machine state, outcomes, `exec`, and `step`. Arithmetic, stack manipulation, register access, memory, and control flow meet here. It also defines the separate auxiliary stack.

### 4. [Stack.lean](formal/WordDialect/Stack.lean) — count the passengers

Assigns each instruction its operand and result counts. The underflow theorems establish what happens when operands are missing and show that sufficient operands exclude a data-stack-underflow result.

### 5. [Rules.lean](formal/WordDialect/Rules.lean) — the instruction handbook

Presents explicit execution rules for literals, pointers, arithmetic, memory, stack operations, and registers. Numeric lemmas connect word operations to modular arithmetic and exact results under stated bounds.

### 6. [Invariants.lean](formal/WordDialect/Invariants.lean) — what stays in place

Proves frame conditions for a successful instruction: stack-depth change, stable address validity, memory and register effects, and return- and auxiliary-stack preservation. It also characterizes halting and trap causes.

### 7. [Exec.lean](formal/WordDialect/Exec.lean) — from a step to a journey

Defines finite continuing paths with `Steps`, terminating executions with `Exec`, and the fuel-bounded interpreter `run`. Soundness, completeness, and determinism connect executable interpretation to the relations.

### 8. [Init.lean](formal/WordDialect/Init.lean) — the first platform

Builds memory from an image, defines the initial state, and extracts a final data stack from an outcome. It includes the direct IR version of `5 DUP +` and proves its result.

### 9. [WordDialect.lean](formal/WordDialect.lean) — the public doorway

Collects the word-machine modules into one import. Its role is architectural: users and downstream libraries can open the semantic foundation through `import WordDialect`.

### 10. [Audit.lean](formal/Audit.lean) — the proof ledger

Imports the project libraries and implements `#audit_wd`. It traverses theorem declarations in the `WordDialect` namespace and collects their axiom dependencies. The command allows Lean's standard `propext`, `Quot.sound`, and `Classical.choice`, reporting other dependencies as errors.

## Station II: the compiler's construction kit — files 11–17

The frontends share more than an instruction set. This region packages recurring compiler arguments so expressions, branches, and loops can reuse an established foundation.

### 11. [Straight.lean](word-ir/WordIR/Straight.lean) — an uninterrupted stretch

Defines straight-line instructions, code placement with `At`, and sequence execution with `execSeq`. Its theorems turn sequence calculations into machine paths or trapping executions.

### 12. [Frag.lean](word-ir/WordIR/Frag.lean) — track that fits its position

Defines position-dependent fragments whose emitted addresses adapt to their placement while their size stays fixed. Sequencing, conditionals, until loops, while loops, and repeat loops come with placement and execution rules.

### 13. [Flag.lean](word-ir/WordIR/Flag.lean) — a shared signal convention

Defines source truth flags as all ones for true and zero for false. The IR comparison produces one or zero; `cmpFlagCode` converts that result to the Forth and BCPL convention.

### 14. [RExpr.lean](word-ir/WordIR/RExpr.lean) — expressions with a destination

Defines register-and-memory expressions built from constants, registers, arithmetic, and loads. Each expression has an evaluator and an instruction sequence that leaves its result on the data stack.

### 15. [Loop.lean](word-ir/WordIR/Loop.lean) — repeat with an invariant

Builds a counted loop using a virtual register, initialization, an unsigned bound test, and an increment. `countedLoop_run` carries a supplied invariant through every iteration to the endpoint.

### 16. [Program.lean](word-ir/WordIR/Program.lean) — arrive at a final outcome

Lifts straight-line code into a complete program by appending `halt`. Its theorems connect a successful `execSeq` calculation to a halted execution and a trapping calculation to the same trap.

### 17. [WordIR.lean](word-ir/WordIR.lean) — the workshop entrance

Exports the straight-line, fragment, flag, expression, loop, and whole-program tools through one import. This entry file shows the compiler layer's reusable vocabulary at a glance.

## Station III: Forth, from text to execution — files 18–30

Forth makes the common machine tangible. Its data-stack operations have direct IR counterparts, while definitions, recursion, variables, return-data operations, and structured loops reveal how the translation grows into a complete source pipeline.

### 18. [Semantics.lean](forth/Forth/Semantics.lean) — Forth's own account

Defines operations, blocks, programs, source state, and the `Run` relation. It specifies signed division, remainder, truth flags, memory access, calls, early exit, `DO … LOOP`, `DO … +LOOP`, `LEAVE` and `UNLOOP`. The source return-data stack is separate from call frames.

### 19. [Compile.lean](forth/Forth/Compile.lean) — words become instructions

Lowers primitives and blocks into IR fragments. It places the main block before `halt`, then lays out definition bodies followed by `ret`. Definition addresses come from fixed code sizes. Each block is compiled with a leave target, the end of its innermost loop, where `LEAVE` jumps.

### 20. [OpCorrect.lean](forth/Forth/OpCorrect.lean) — each primitive keeps its meaning

Proves that lowering a Forth operation produces straight-line code with the behavior specified by `Op.sem`. Success transfers the resulting source state to the machine; failure preserves the trap.

### 21. [Correct.lean](forth/Forth/Correct.lean) — the complete translation argument

Connects source `Run` derivations to compiled machine paths, early returns, and matching traps. `DefsAt` describes dictionary-body placement, including recursive calls. `Program.compile_correct` lifts the argument to an initialized whole program.

### 22. [LoopProps.lean](forth/Forth/LoopProps.lean) — where a counted loop stops

Proves that the `+LOOP` exit test is ANS Forth's crossing rule, the signed overflow of `index - limit - 2^(n-1) + step` (`loopCrossed_eq_saddOverflow`), and that with step one it is the `LOOP` test `index + 1 = limit` (`loopCrossed_one`).

### 23. [Eval.lean](forth/Forth/Eval.lean) — a reference you can evaluate

Implements a fuel-bounded source interpreter and proves `eval_sound` against `Run`. Concrete evaluation can therefore supply a source-semantics derivation, including for recursive words.

### 24. [Example.lean](forth/Forth/Example.lean) — five becomes ten

Takes `5 DUP +` through source semantics, compilation, and machine execution. The tiny example makes the entire frontend argument visible without a large program.

### 25. [Parse.lean](forth/Forth/Parse.lean) — the text ticket office

Turns source text into a dictionary, main block, and variable count. It handles case-insensitive words, comments, literals, colon definitions, recursion, early exit, variables, constants, conditionals, and loops, including `+LOOP`, `?DO` and `LEAVE` (rejected outside a loop).

### 26. [Print.lean](forth/Forth/Print.lean) — a return ticket to text

Prints programs using canonical variable and definition names, then proves `parse_print` for well-formed programs. The argument covers both token generation and parsing.

### 27. [ParseProps.lean](forth/Forth/ParseProps.lean) — the parser's promises

Proves that successful parsing yields a well-formed program and that printing such a result gives canonical source. Further results cover case behavior, comments, constants, dictionary definitions, and `RECURSE`.

### 28. [Grammar.lean](forth/Forth/Grammar.lean) — the parser's timetable without fuel

Gives the parser an inductive grammar, `Seq` for blocks, `Top` for definitions, variables and constants, and `Prog` for whole programs, and proves the parser accepts exactly its derivations (`parse_iff`), which are unambiguous. The fuel is irrelevant (`parseSeq_fuel`), and `parse` never reports running out of it (`parse_ne_fuel`).

### 29. [TextExample.lean](forth/Forth/TextExample.lean) — the journey in source spelling

Provides concrete examples spanning parsing, reference evaluation, compilation, and machine results. Its subjects include recursive sums, variables, constants, remainder, early exits, nested loops, `+LOOP` up and down, `?DO`, `LEAVE`, `UNLOOP`, and return-data operations. It also records parser outcomes for selected malformed inputs.

### 30. [Forth.lean](forth/Forth.lean) — the frontend entrance

Exports the Forth library through one import, bringing its semantics, compiler, proofs, evaluator, text tools, and examples together. For an application, this is the convenient access point.

## Station IV: BCPL and the memory-centered route — files 31–36

BCPL reaches the same machine from a different source perspective. Variables are memory cells, values are words, and expression and statement semantics supply the reference for compilation.

### 31. [Semantics.lean](bcpl/BCPL/Semantics.lean) — expressions and statements in words

Defines the supported syntax, operator meanings, expression evaluation, assignment, and statement execution. It includes indirection, address-of, conditionals, and loops. Evaluation order and signed division are explicit, and comparisons use all-ones truth flags.

### 32. [Compile.lean](bcpl/BCPL/Compile.lean) — memory programs enter the interchange

Lowers expressions to stack-producing instruction sequences and statements to fragments. Variables use a supplied address mapping, and statements restore the data stack on completion. Arithmetic and assignments use straight-line code; structured control uses the common fragment toolkit.

### 33. [ExprCorrect.lean](bcpl/BCPL/ExprCorrect.lean) — expression results travel intact

Proves straight-line properties and correctness for operator and expression lowering, covering successful values and traps. These results establish the evaluator-to-instruction connection needed by statement compilation.

### 34. [Correct.lean](bcpl/BCPL/Correct.lean) — statements reach their promised memory

Proves assignment and statement translation correctness. Successful compiled execution reaches the statement endpoint with the source result's memory and an unchanged data stack; trapping source execution leads to the matching machine trap.

### 35. [Example.lean](bcpl/BCPL/Example.lean) — put five in a cell

Uses the assignment `x := 2 + 3` to demonstrate the complete BCPL route. Given an addressable variable cell, the reference statement produces the expected memory and the compiled machine program stores five there.

### 36. [BCPL.lean](bcpl/BCPL.lean) — the BCPL doorway

Collects the BCPL semantics, translation, correctness results, and example under one import. The entry file marks a clean frontend boundary: the source language has its own account of execution, then connects through compiler proofs to the shared machine.

## Station V: mathematical expressions and matrix cargo — files 37–41

The Wolfram-style route connects mathematical integer expressions to fixed-width computation. Matrix multiplication then turns that connection into nested loops over a concrete memory layout.

### 37. [Scalar.lean](wolfram/Wolfram/Scalar.lean) — integers meet fixed-width words

Defines scalar expressions for integer literals, symbols, addition, multiplication, subtraction, and negation. Integer evaluation connects to `RExpr` lowering modulo the word width. Compilation and assignment theorems cover successful results and errors.

### 38. [MatrixLayout.lean](wolfram/Wolfram/MatrixLayout.lean) — pack the rows

Defines partial dot sums, row-major matrix representation with `MatAt`, and destination-prefix updates with `CWritten`. Its lemmas describe extending the written output while preserving source cells outside that region.

### 39. [MatrixDot.lean](wolfram/Wolfram/MatrixDot.lean) — three loops carry the product

Lowers matrix multiplication into row, column, and accumulation loops using four virtual registers. Geometry conditions specify address bounds and separation. Proofs progress from index expressions and accumulation to cells, rows, the full fragment, and `dotProgram_correct`.

### 40. [MatrixExample.lean](wolfram/Wolfram/MatrixExample.lean) — a product you can recognize

Instantiates the matrix geometry and memory representation for `[[1,2],[3,4]]` multiplied by `[[5,6],[7,8]]`, whose product is `[[19,22],[43,50]]`. It stores the inputs at word addresses zero and four and the output at eight.

### 41. [Wolfram.lean](wolfram/Wolfram.lean) — the mathematical entrance

Exports the scalar and matrix modules, connecting expression lowering, layout vocabulary, multiplication proofs, and the worked example. Start through this import when constructing a mathematical sample.

## Station VI: the shared observation platform — file 42

### 42. [Harness.lean](backend/common/Harness.lean) — compare the arrivals

Defines samples, expected Lean outcomes, target result decoding, the backend `Runner` interface, fixed examples, and generated programs. The harness compares trap codes or final data stack, memory, and virtual registers.

## Station VII: the x86-64 express — files 43–64

The native route implements the IR with concrete registers, guarded stack regions, and GNU assembly. Its proof structure proceeds from machine semantics through local simulation to whole-program and entry-point results.

### 43. [Isa.lean](backend/x86_64/X86/Isa.lean) — the native vehicle

Models the emitted x86-64 instruction subset, registers, condition flags, memory access, and target outcomes. Faults and runtime exits are explicit.

### 44. [Lower.lean](backend/x86_64/X86/Lower.lean) — choose the native track

Defines runtime register roles, operand and capacity guards, instruction sizes, offsets, and lowering. The data stack uses `r15`, virtual registers use `r14`, IR memory uses `r13`, entry stack position uses `r12`, and auxiliary data uses `rbp`.

### 45. [Emit.lean](backend/x86_64/X86/Emit.lean) — print the assembly journey

Prints lowered instructions in GNU assembler Intel syntax and supplies the runtime prologue and output/exit helpers. Runtime declarations establish memory and stack regions. Successful execution writes a binary state dump; traps and overflow use their exit codes.

### 46. [Rel.lean](backend/x86_64/X86/Rel.lean) — match the two timetables

Defines runtime geometry and the relation between IR and native states. It maps stacks, virtual registers, memory, and return addresses into disjoint target regions. Frame lemmas support updates.

### 47. [Run.lean](backend/x86_64/X86/Run.lean) — locate and follow native code

Defines native continuing and terminating execution relations, code placement, and theorems locating each lowered IR instruction. It connects offset calculations to the emitted instruction list, including the trailing bad-program-counter stub.

### 48. [Seq.lean](backend/x86_64/X86/Seq.lean) — compose short native stretches

Provides straight-line native execution and its connection to native step paths. It also proves the conditional-jump-and-trap guard pattern.

### 49. [Flags.lean](backend/x86_64/X86/Flags.lean) — read the signals correctly

Proves that native condition-code interpretation after subtraction matches all ten IR comparison predicates. The argument accounts for zero, sign, carry, and overflow flags.

### 50. [Micro.lean](backend/x86_64/X86/Micro.lean) — the smallest useful moves

Establishes local effects of target loads, stores, scratch-register updates, stack-pointer adjustment, and pushing a word. Each lemma works with the state relation.

### 51. [Guard.lean](backend/x86_64/X86/Guard.lean) — check room and operands

Proves operand-count guards and data- and return-stack capacity checks. With enough operands or room, the code continues; otherwise it produces the specified underflow or overflow outcome.

### 52. [SimBin.lean](backend/x86_64/X86/SimBin.lean) — one pattern, many operators

Defines `MidSpec` and proves a generic binary-operation simulation. The pattern loads two operands, computes in scratch state, stores the result, and removes one stack slot.

### 53. [SimOps.lean](backend/x86_64/X86/SimOps.lean) — instantiate the arithmetic route

Applies the generic binary pattern to arithmetic, bitwise operations, shifts, rotations, and comparisons. Its middle specifications show the target computation matches the IR operation.

### 54. [SimStack.lean](backend/x86_64/X86/SimStack.lean) — rearrange the carried words

Proves simulations for literals, pointers, complement, duplication, dropping, swapping, copying a lower stack item, and rotation. Local target-step lemmas support the stack updates.

### 55. [SimMem.lean](backend/x86_64/X86/SimMem.lean) — preserve neighboring regions

Develops address and frame lemmas for virtual-register and IR-memory access. It establishes the effects of reading and writing those cells while preserving stack and other-region relations.

### 56. [SimMemOps.lean](backend/x86_64/X86/SimMemOps.lean) — perform the checked access

Proves the address bounds guard and complete simulations for virtual-register push/pop and memory load/store. Both successful access and bad-address traps are covered, with overflow behavior for a growing data stack.

### 57. [SimDiv.lean](backend/x86_64/X86/SimDiv.lean) — handle division's special junctions

Covers unsigned division, signed division, and three-operand selection. The proofs include zero-divisor traps and the signed divisor-minus-one path that avoids native division overflow while preserving modular word semantics.

### 58. [SimCtl.lean](backend/x86_64/X86/SimCtl.lean) — branch, call, and return

Proves simulations for jumps, conditional branches, calls, returns, and halt. The native return stack stores lowered return-code indices corresponding to IR addresses. Return underflow and call overflow receive explicit results.

### 59. [SimAux.lean](backend/x86_64/X86/SimAux.lean) — a separate place for saved data

Proves auxiliary-stack access, push/pop effects, capacity and empty-stack guards, and the `tor`, `fromr`, and `rfetch` simulations. Its dedicated region and `rbp` pointer preserve saved words across native calls.

### 60. [SimStep.lean](backend/x86_64/X86/SimStep.lean) — every instruction gets a connection

Combines the instruction-family results into `sim_exec`, covering each IR instruction and continuing, halted, or trapped outcomes. `Fits` describes required stack headroom, and simulation includes overflow where capacity runs out.

### 61. [Correct.lean](backend/x86_64/X86/Correct.lean) — preserve the complete journey

Lifts instruction simulation to whole-program behavior. `lowerProg_correct_or_overflow` allows a matching IR outcome or overflow; `lowerProg_correct` gives the matching outcome when reachable states fit. Geometry, layout agreement, code-address bounds, and valid register indices make the program's target contract explicit.

### 62. [Init.lean](backend/x86_64/X86/Init.lean) — begin at the binary entrance

Models the prologue and proves its effect, then relates the resulting native state to `State.init`. `Loader.Holds` gathers the loader's memory, placement, and entry-stack facts.

### 63. [X86.lean](backend/x86_64/X86.lean) — the native library entrance

Exports the native model, lowering, emitter, relations, simulation modules, whole-program proofs, and initialization result. This import gives users the complete backend library.

### 64. [Main.lean](backend/x86_64/Main.lean) — take the express for a run

Implements `wordc`: emit assembly, assemble and link with `as` and `ld`, execute, and compare against Lean. It supports fixed/generated checks and Forth files, plus auxiliary-stack and overflow samples.

## Station VIII: the WebAssembly line — files 65–83

WebAssembly offers structured control, typed operands, and byte memory. This route represents each IR instruction as a function returning the next instruction index, then runs those functions through a dispatch loop.

### 65. [Isa.lean](backend/wasm/Wasm/Isa.lean) — the WebAssembly vehicle

Models typed values, globals, byte-addressed linear memory, the emitted instruction subset, function tables, and structured execution. Reads and writes use little-endian bytes; loops and branches obey label discipline. Division and host-exit behavior are explicit.

### 66. [Lower.lean](backend/wasm/Wasm/Lower.lean) — turn jumps into dispatch

Lowers each IR instruction to a function returning an `i32` next index. A dispatch loop calls through the function table. Globals track program counter and three stack pointers; memory regions hold registers, IR cells, and stacks.

### 67. [Emit.lean](backend/wasm/Wasm/Emit.lean) — print the module

Produces WebAssembly text from lowered instructions and supplies memory declarations, data bytes, globals, imports, and the halt helper. Runtime layout constants determine region placement and capacity.

### 68. [Mem.lean](backend/wasm/Wasm/Mem.lean) — eight bytes make a word

Proves that writing eight bytes reconstructs the same 64-bit value on a read at that address. Reads of disjoint cells stay unchanged, and writes preserve memory size.

### 69. [Rel.lean](backend/wasm/Wasm/Rel.lean) — align the two state views

Defines runtime geometry and the relation between IR values and WebAssembly globals and memory. Separate views cover the data stack, registers, IR memory, return addresses, and auxiliary words.

### 70. [Seq.lean](backend/wasm/Wasm/Seq.lean) — join target computations

Defines straight-line execution with `execL` and derives the target `Run` relation from successful calculations. Sequencing lemmas handle normal completion and abrupt outcomes, with useful conditional cases.

### 71. [Frame.lean](backend/wasm/Wasm/Frame.lean) — update one region at a time

Proves how eight-byte writes affect the five state views. Updates to a stack, register, or IR-memory cell preserve the other regions. Further lemmas handle stack-pointer adjustment and pushing or popping return and auxiliary entries.

### 72. [Guard.lean](backend/wasm/Wasm/Guard.lean) — the checked platform edge

Proves sequence append behavior, state-relation conveniences, operand guards, and capacity guards. Passing checks preserve the required relation; failing checks produce the appropriate exit.

### 73. [SimAlu.lean](backend/wasm/Wasm/SimAlu.lean) — the arithmetic carriage

Provides generic binary-operation simulation and instantiates it for arithmetic, bitwise operations, rotations, and comparisons. It connects two stack-cell loads, a target operation, a result store, and stack adjustment.

### 74. [SimAlu2.lean](backend/wasm/Wasm/SimAlu2.lean) — arithmetic's special connections

Handles shifts, division, signed division, and complement. Large shift counts yield zero as required by the IR, while division checks zero explicitly. The signed divisor-minus-one case preserves modular semantics while avoiding WebAssembly's signed-division overflow trap.

### 75. [SimStack.lean](backend/wasm/Wasm/SimStack.lean) — move words through memory

Proves stack manipulation, selection, literals, pointers, and virtual-register transfers. General push and core-sequence lemmas support multiple operations, with guards for operand availability and capacity.

### 76. [SimMem.lean](backend/wasm/Wasm/SimMem.lean) — find the right eight bytes

Proves IR-address checking, conversion to `mb + 8a`, and simulations of load and store. A valid word address reaches the corresponding bytes; an invalid address exits with bad-address code two.

### 77. [SimCtl.lean](backend/wasm/Wasm/SimCtl.lean) — return the next station index

Covers jumps, branches, calls, returns, halt, and the bad-program-counter stub. Continuing instruction functions leave the next IR index for dispatch. Calls and returns update the dedicated return region; empty returns and full call stacks receive defined exits.

### 78. [SimAux.lean](backend/wasm/Wasm/SimAux.lean) — preserve the saved-word connection

Proves `tor`, `fromr`, and `rfetch` over the auxiliary region tracked by `$ap`. It covers successful movement and copying, empty-stack code five, and capacity code six.

### 79. [SimExec.lean](backend/wasm/Wasm/SimExec.lean) — one complete dispatch step

Combines all instruction-family results into `sim_step`. It defines stack headroom, trap-code mapping, and the relation between one emitted function's execution and one IR outcome.

### 80. [Correct.lean](backend/wasm/Wasm/Correct.lean) — carry the result through the loop

Proves dispatch-loop preservation and lifts it to the module's start function. The two main results offer matching IR behavior with overflow allowed, or exact matching behavior under capacity conditions.

### 81. [Init.lean](backend/wasm/Wasm/Init.lean) — start from an instantiated module

Constructs initial globals and zeroed memory with the emitted data image, proves runtime geometry and the initial state relation, and establishes `module_correct`. Program-layout fit and register and instruction bounds remain explicit.

### 82. [Wasm.lean](backend/wasm/Wasm.lean) — the WebAssembly library entrance

Exports the target model, lowering, emitter, memory facts, relations, framing, guards, instruction simulations, whole-program correctness, and initialization. One import provides the full WebAssembly backend.

### 83. [WasmMain.lean](backend/wasm/WasmMain.lean) — ride the line in Wasmtime

Implements `wasmw`: emit WAT, run it through Wasmtime, and compare target output with Lean. It supports sample checks, generated programs, source Forth execution, and source emission.

## Make your first journey

Install Git and [elan](https://github.com/leanprover/elan), then make `lean` and `lake` available on your path. The repository pins `leanprover/lean4:v4.34.1`; elan selects that toolchain. The Lake package is named `UniversalWord`, and its manifest lists no external package dependencies.

```sh
git clone https://github.com/SNAPKITTYWEST/ai-free.git
cd ai-free
lake build
```

The default build includes the semantic and frontend libraries, shared harness, both backend libraries, and the `wordc` and `wasmw` executables. Native execution uses x86-64 Linux with GNU `as` and `ld`. WebAssembly execution uses [Wasmtime](https://github.com/bytecodealliance/wasmtime/releases); the workflow selects version `30.0.2`.

Try a short source file containing `5 DUP +`, or use the repository's [Forth examples](examples/forth). The commands below exercise real source parsing and compilation before comparing target behavior with Lean:

```sh
.lake/build/bin/wordc forth examples/forth/fib.fs
.lake/build/bin/wasmw forth examples/forth/memory.fs 16
.lake/build/bin/wordc emit-forth examples/forth/sum.fs > /tmp/sum.s
.lake/build/bin/wasmw emit-forth examples/forth/sum.fs > /tmp/sum.wat
```

The optional memory-word count defaults to sixteen. Variables occupy cells starting at zero; the executable frontend arranges memory for the parsed program. Forth definitions can call themselves, and `RECURSE` names the current definition. `DO … LOOP`, `I`, `J`, and return-data words provide especially interesting examples because their data survives calls through the auxiliary stack. [`leave.fs`](examples/forth/leave.fs) exercises `+LOOP` counting up and down, `?DO`, `LEAVE` and `UNLOOP`.

For a broader trip, run the fixed samples and three hundred generated programs on each destination:

```sh
.lake/build/bin/wordc check 300
.lake/build/bin/wasmw check 300
```

With no count, the generated-program count defaults to two hundred. `check 0` runs the fixed checks without generated programs. The shared reference interpreter uses bounded fuel; programs that exhaust it are reported as skipped. Generation uses a fixed seed, helping make comparisons reproducible. Backend checks additionally exercise auxiliary-stack behavior and intentional overflow.

You can also inspect a built-in sample's output without running the target:

```sh
.lake/build/bin/wordc emit forth_five_dup_plus > /tmp/five.s
.lake/build/bin/wasmw emit forth_five_dup_plus > /tmp/five.wat
```

Other named samples include `bcpl_sum_1_to_10`, `wolfram_dot_2x2`, and `raw_call_ret`. The shared harness contains the complete sample lists. Native execution artifacts are written under `/tmp/wordc`; WebAssembly artifacts use `/tmp/wasmw`. Successful target output is a binary state dump decoded by the harness, so these commands are most informative when used with the comparison tools or emitter output.

## Read the proofs as a connected story

A source correctness theorem begins with a source execution result. The compiler translates that program into the shared IR, and its theorem establishes the corresponding machine execution. A backend theorem then connects that machine execution to a target model. Initialization results establish the relation at the target's starting state. The examples make these connections concrete with values and memory images you can recognize.

When exploring a theorem, start with its conclusion and then inspect its hypotheses. A matrix theorem's geometry explains where input and output cells live. A backend theorem's register condition explains which virtual-register indices the configured file supports. A capacity condition explains when a bounded target follows the IR outcome exactly. These hypotheses are part of the module's usable interface and often reveal the clearest path to constructing your own example.

For a small complete reading route, follow Forth's example into its compiler and correctness file, then open the shared harness and one executable entry point. For a deeper route, begin with the machine, read straight-line and fragment composition, and follow BCPL statement correctness. For nested-loop reasoning, take the counted-loop module into matrix layout, matrix multiplication, and its concrete example.

The two backend routes offer an illuminating comparison. Native lowering computes target offsets and uses native calls. WebAssembly lowering returns IR instruction indices through a table-driven dispatch loop. Both preserve the same source of meaning, use separate storage for call addresses and auxiliary words, and connect local instruction simulations to complete execution results. Their different implementations make the common semantic layer especially valuable to readers.

A useful exercise is to trace one value across the map. In `5 DUP +`, parsing produces a literal and two operations; reference evaluation duplicates five and adds the pair; compilation emits the corresponding IR sequence; either backend carries that sequence to its target representation. The final stack contains ten. For BCPL, trace the same arithmetic into a variable cell instead. For matrix multiplication, trace one output entry through its accumulator register, the inner loop, and the destination write. These three examples give you stack, memory, and loop perspectives on the same architecture. Once those routes feel familiar, the larger theorem files become easier to navigate: identify the local semantic result, find its compiled fragment, locate the appropriate simulation, and follow the composition to the final outcome. Each step has a named home in this atlas for your next exploration.

## The project's verification practice

The repository includes a namespace-wide axiom audit and a [CI workflow](.github/workflows/lean.yml) that builds the libraries, checks prohibited proof constructs, runs the audit, exercises both executable backends, and runs the Forth example files. The audit command is:

```sh
lake env lean formal/Audit.lean
```

Formal results describe the machine models and their stated interfaces. Differential execution compares emitted artifacts through real assemblers and runtimes with the Lean reference. Together, these give readers a theorem route through the definitions and an execution route through concrete programs. The audit makes theorem dependencies inspectable across the imported libraries.

When adding an operation, a useful path is to define its semantic behavior, connect its translation with an appropriate correctness result, and add a shared sample. An existing example provides a manageable starting point. For source-interface work, parser and printer properties show how text behavior can receive the same attention as machine behavior. For backend work, the instruction-family files indicate where a new local simulation joins the complete step theorem.

After a code change, use the project's build, audit, and backend checks as the repository workflow prescribes. For navigation and documentation, this atlas lets you move directly to the relevant source file and follow its imports. Each numbered stop identifies a real module's contribution, from the first word representation to the two executable destinations.

## License

The project uses the [Parr Source License — No AI Training, Version 1.0](License), copyright © 2026 Ahmad Ali Parr. The license text defines permitted purposes and its conditions, including restrictions concerning competing use and AI training. Refer to that file for the governing terms when using, modifying, or distributing the project.

