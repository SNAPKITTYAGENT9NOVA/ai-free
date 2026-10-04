import Harness
import Wasm

/-!
# wasmw

Execution harness for the WebAssembly backend. For each program it lowers the IR to WebAssembly,
emits WAT (`Wasm.Emit`), runs it under `wasmtime` (WASI), runs the same IR program under the Lean
semantics, and compares the exit status and the dumped data stack, IR memory and virtual registers
(the shared `Harness`).

`wasmtime` is found through the `WASMTIME` environment variable, else on `PATH`.

`check` also runs `auxSamples`, raw IR programs for the auxiliary stack (`tor`/`fromr`/`rfetch`),
against the Lean semantics, and the overflow programs, which must exit 6.

Usage: `wasmw check [fuzzCount]`, `wasmw emit <sample>`, `wasmw forth <file.fs> [memWords]` (run a
Forth source file under wasmtime and compare with the Lean semantics), `wasmw emit-forth <file.fs>`.
-/

open WordDialect

def runtimeFor (s : Sample) : Wasm.Emit.Runtime := { memImage := s.mem, nregs := s.nregs }

def watFor (s : Sample) : String :=
  let r := runtimeFor s
  Wasm.Emit.program r s.prog

def workDir : String := "/tmp/wasmw"

def runWasm (s : Sample) : IO (Except String Result) := do
  IO.FS.createDirAll workDir
  let path := s!"{workDir}/{s.name}.wat"
  IO.FS.writeFile path (watFor s)
  let cmd := (← IO.getEnv "WASMTIME").getD "wasmtime"
  let child ← IO.Process.spawn { cmd, args := #["run", path], stdout := .piped, stderr := .piped, stdin := .null }
  let bytes ← readAll child.stdout ByteArray.empty
  let err ← child.stderr.readToEnd
  let code ← child.wait
  if code == 0 then
    match parseDump s bytes with
    | some r => return .ok r
    | none => return .error s!"malformed dump ({bytes.size} bytes): {err}"
  else if code.toNat ≥ 1 && code.toNat ≤ 6 then
    return .ok (.trap code.toNat)
  else
    return .error s!"wasmtime exit {code}: {err}"

/-- Raw IR programs exercising the auxiliary stack: values parked across `call`/`ret` and
recursion, `R@` copies, a counted loop, and the traps (empty auxiliary stack → 5, `tor` on an empty
data stack → 1). Each is checked against the Lean semantics. -/
def auxSamples : List Sample :=
  [ { name := "aux_basic",
      prog := [.word 5#64, .tor, .word 7#64, .rfetch, .add, .fromr, .mul, .halt], mem := [] },
    { name := "aux_across_call",
      prog := [.word 3#64, .tor, .call 6, .fromr, .add, .halt,
               .word 10#64, .rfetch, .add, .ret], mem := [] },
    { name := "aux_recursion_fact",
      prog := [.word 5#64, .call 3, .halt,
               .dup, .word 0#64, .cmp .eq, .branch 15,
               .dup, .tor, .word 1#64, .sub, .call 3, .fromr, .mul, .ret,
               .drop, .word 1#64, .ret], mem := [] },
    { name := "aux_counted_loop",
      prog := [.word 0#64, .word 10#64, .tor,
               .rfetch, .add, .fromr, .word 1#64, .sub, .dup, .tor, .word 0#64, .cmp .ne, .branch 3,
               .fromr, .drop, .halt], mem := [] },
    { name := "aux_fromr_empty", prog := [.word 1#64, .fromr, .halt], mem := [] },
    { name := "aux_rfetch_empty", prog := [.rfetch, .halt], mem := [] },
    { name := "aux_unbalanced", prog := [.word 1#64, .tor, .fromr, .fromr, .halt], mem := [] },
    { name := "aux_tor_underflow", prog := [.tor, .halt], mem := [] },
    { name := "aux_ret_keeps_aux",
      prog := [.call 3, .fromr, .halt, .word 42#64, .tor, .ret], mem := [] } ]

def checkAux : IO Bool := do
  let mut ok := true
  for s in auxSamples do
    if !(← check runWasm s) then ok := false
  return ok

/-- Programs whose IR run never terminates and grows a stack without bound: the target must stop
them with the overflow exit (code 6) instead of corrupting memory. -/
def overflowSamples : List Sample :=
  [ { name := "ovf_word_loop", prog := [.word 1#64, .jmp 0], mem := [] },
    { name := "ovf_dup_loop", prog := [.word 1#64, .dup, .jmp 1], mem := [] },
    { name := "ovf_call_loop", prog := [.call 0], mem := [] },
    { name := "ovf_tor_loop", prog := [.word 1#64, .tor, .jmp 0], mem := [] } ]

def checkOverflow : IO Bool := do
  let mut ok := true
  for s in overflowSamples do
    match ← runWasm s with
    | .ok (.trap 6) => IO.println s!"PASS  {s.name}  overflow exit 6"
    | .ok got => IO.println s!"FAIL  {s.name}  expected overflow exit 6, got {repr got}"; ok := false
    | .error e => IO.println s!"ERROR {s.name}: {e}"; ok := false
  return ok

/-- A Forth source file as a sample: named after the file, `memWords` zero words of IR memory. -/
def forthFileSample (path : String) (memWords : Nat) : IO Sample := do
  let src ← IO.FS.readFile path
  let name := (System.FilePath.mk path).fileStem.getD "forth"
  return forthTextSample name src (List.replicate memWords 0)

def parseMem (rest : List String) : Option Nat :=
  match rest with
  | [] => some 16
  | [m] => m.toNat?
  | _ => none

def main (args : List String) : IO UInt32 := do
  match args with
  | ["emit", name] =>
    match (allSamples ++ auxSamples).find? (·.name == name) with
    | some s => IO.println (watFor s); return 0
    | none => IO.eprintln "unknown sample"; return 1
  | "forth" :: path :: rest =>
    match parseMem rest with
    | none => IO.eprintln "usage: wasmw forth <file.fs> [memWords]"; return 2
    | some m =>
      let s ← forthFileSample path m
      return (if ← check runWasm s then 0 else 1)
  | "emit-forth" :: path :: rest =>
    match parseMem rest with
    | none => IO.eprintln "usage: wasmw emit-forth <file.fs> [memWords]"; return 2
    | some m =>
      let s ← forthFileSample path m
      match s.buildError with
      | some e => IO.eprintln e; return 1
      | none => IO.println (watFor s); return 0
  | "check" :: rest =>
    let count := match rest with | [n] => n.toNat! | _ => 200
    let agree ← checkAll runWasm count
    let aux ← checkAux
    let ovf ← checkOverflow
    return (if agree && aux && ovf then 0 else 1)
  | _ => IO.eprintln "usage: wasmw check [fuzzCount] | wasmw emit <sample> | wasmw forth <file.fs> [memWords] | wasmw emit-forth <file.fs> [memWords]"; return 2
