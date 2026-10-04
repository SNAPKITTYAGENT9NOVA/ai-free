# Next steps

Suggested development order. Each item names the gap it closes in the current code.

## 1. Prove the x86-64 runtime establishes the entry relation

The WebAssembly side is done: `Wasm.Emit.module_correct` starts from the state instantiation
produces for the emitted module. `X86.init_rel` still takes the initial machine state as
hypotheses: `r12 = rsp = sp0`, `r13 r14 r15` at the conventions, the register file zeroed and the
IR memory region holding the image, and the data-stack, register-file, IR-memory and native-stack
regions addressable. Unlike WebAssembly these depend on the operating system (the entry `rsp`,
zero-filled `.bss`, the `.data` and `.dstack` placement), so the step is to model the prologue in
`X86/Emit.lean` and state, as explicit assumptions about the loader, exactly what the ELF image
guarantees at `_start`.

## 2. Forth: source files on the command line, and a wider subset

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
