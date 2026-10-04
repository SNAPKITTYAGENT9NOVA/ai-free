import Harness
import X86

/-!
# wordc

Native execution harness for the x86-64 backend. For each program it
1. lowers the IR to x86-64 and emits GNU assembly (`X86.Emit`),
2. assembles and links it with `as` / `ld`,
3. runs the binary on this machine,
4. runs the same IR program under the Lean semantics (`WordDialect.run`), and
5. compares exit status and the dumped data stack, IR memory and virtual registers
   (the shared `Harness`).

Usage: `wordc check [fuzzCount]`, `wordc emit <sample>`, `wordc forth <file.fs> [memWords]` (run a
Forth source file natively and compare with the Lean semantics), `wordc emit-forth <file.fs>`.
-/

open WordDialect

def dBase : Nat := 0x10000000
def capacity : Nat := 65536
def dEnd : Nat := dBase + 8 * capacity
/-- Return-stack capacity in entries: 512 KiB of the native stack below the entry `rsp`. -/
def rcap : Nat := 65536

def runtimeFor (s : Sample) : X86.Emit.Runtime :=
  { dEnd := dEnd, capacity := capacity, rcap := rcap, memImage := s.mem, nregs := s.nregs }

def layoutFor (s : Sample) : X86.Layout := (runtimeFor s).layout

def asmFor (s : Sample) : String :=
  X86.Emit.program (runtimeFor s) (X86.lowerProg (layoutFor s) s.prog)

def workDir : String := "/tmp/wordc"

def runNative (s : Sample) : IO (Except String Result) := do
  IO.FS.createDirAll workDir
  let base := s!"{workDir}/{s.name}"
  IO.FS.writeFile (base ++ ".s") (asmFor s)
  let a ← IO.Process.output { cmd := "as", args := #["-o", base ++ ".o", base ++ ".s"] }
  if a.exitCode != 0 then return .error s!"as failed: {a.stderr}"
  let l ← IO.Process.output { cmd := "ld", args := #[s!"--section-start=.dstack={X86.Emit.hex dBase}", "-o", base, base ++ ".o"] }
  if l.exitCode != 0 then return .error s!"ld failed: {l.stderr}"
  let child ← IO.Process.spawn { cmd := base, stdout := .piped, stderr := .null, stdin := .null }
  let bytes ← readAll child.stdout ByteArray.empty
  let code ← child.wait
  if code == 0 then
    match parseDump s bytes with
    | some r => return .ok r
    | none => return .error s!"malformed dump ({bytes.size} bytes)"
  else
    return .ok (.trap code.toNat)


/-- Programs whose IR run never terminates and grows a stack without bound: the native code must
stop them with the overflow exit (code 6) instead of running off the end of a stack. -/
def overflowSamples : List Sample :=
  [ { name := "ovf_word_loop", prog := [.word 1#64, .jmp 0], mem := [] },
    { name := "ovf_dup_loop", prog := [.word 1#64, .dup, .jmp 1], mem := [] },
    { name := "ovf_call_loop", prog := [.call 0], mem := [] } ]

def checkOverflow : IO Bool := do
  let mut ok := true
  for s in overflowSamples do
    match ← runNative s with
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
    match allSamples.find? (·.name == name) with
    | some s => IO.println (asmFor s); return 0
    | none => IO.eprintln "unknown sample"; return 1
  | "forth" :: path :: rest =>
    match parseMem rest with
    | none => IO.eprintln "usage: wordc forth <file.fs> [memWords]"; return 2
    | some m =>
      let s ← forthFileSample path m
      return (if ← check runNative s then 0 else 1)
  | "emit-forth" :: path :: rest =>
    match parseMem rest with
    | none => IO.eprintln "usage: wordc emit-forth <file.fs> [memWords]"; return 2
    | some m =>
      let s ← forthFileSample path m
      match s.buildError with
      | some e => IO.eprintln e; return 1
      | none => IO.println (asmFor s); return 0
  | "check" :: rest =>
    let count := match rest with | [n] => n.toNat! | _ => 200
    let agree ← checkAll runNative count
    let ovf ← checkOverflow
    return (if agree && ovf then 0 else 1)
  | _ => IO.eprintln "usage: wordc check [fuzzCount] | wordc emit <sample> | wordc forth <file.fs> [memWords] | wordc emit-forth <file.fs> [memWords]"; return 2
