import Harness
import Wasm

/-!
# wasmw

Execution harness for the WebAssembly backend. For each program it lowers the IR to WebAssembly,
emits WAT (`Wasm.Emit`), runs it under `wasmtime` (WASI), runs the same IR program under the Lean
semantics, and compares the exit status and the dumped data stack, IR memory and virtual registers
(the shared `Harness`).

`wasmtime` is found through the `WASMTIME` environment variable, else on `PATH`.

Usage: `wasmw check [fuzzCount]`, `wasmw emit <sample>`.
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
  else if code.toNat ≥ 1 && code.toNat ≤ 5 then
    return .ok (.trap code.toNat)
  else
    return .error s!"wasmtime exit {code}: {err}"

def main (args : List String) : IO UInt32 := do
  match args with
  | ["emit", name] =>
    match allSamples.find? (·.name == name) with
    | some s => IO.println (watFor s); return 0
    | none => IO.eprintln "unknown sample"; return 1
  | "check" :: rest =>
    let count := match rest with | [n] => n.toNat! | _ => 200
    return (if ← checkAll runWasm count then 0 else 1)
  | _ => IO.eprintln "usage: wasmw check [fuzzCount] | wasmw emit <sample>"; return 2
