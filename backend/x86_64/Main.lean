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

Usage: `wordc check [fuzzCount]`, `wordc emit <sample>`.
-/

open WordDialect

def dBase : Nat := 0x10000000
def capacity : Nat := 65536
def dEnd : Nat := dBase + 8 * capacity

def layoutFor (s : Sample) : X86.Layout :=
  { dEnd := BitVec.ofNat 64 dEnd, memSize := s.mem.length }

def runtimeFor (s : Sample) : X86.Emit.Runtime :=
  { dEnd := dEnd, capacity := capacity, memImage := s.mem, nregs := s.nregs }

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


def main (args : List String) : IO UInt32 := do
  match args with
  | ["emit", name] =>
    match allSamples.find? (·.name == name) with
    | some s => IO.println (asmFor s); return 0
    | none => IO.eprintln "unknown sample"; return 1
  | "check" :: rest =>
    let count := match rest with | [n] => n.toNat! | _ => 200
    return (if ← checkAll runNative count then 0 else 1)
  | _ => IO.eprintln "usage: wordc check [fuzzCount] | wordc emit <sample>"; return 2
