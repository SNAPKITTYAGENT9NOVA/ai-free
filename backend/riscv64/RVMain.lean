import Harness
import RV

/-!
# rv64c

Execution harness for the RISC-V backend. For each program it
1. lowers the IR to RV64IM and emits assembly (`RV.Emit`),
2. assembles it with `clang --target=riscv64-linux-gnu -march=rv64im` and links it with `ld.lld`,
3. runs the binary under `qemu-riscv64` (user-mode emulation; on a RISC-V Linux host the binary
   also runs directly),
4. runs the same IR program under the Lean semantics (`WordDialect.run`), and
5. compares exit status and the dumped data stack, IR memory and virtual registers
   (the shared `Harness`).

`check` also runs the auxiliary-stack programs (`tor`/`fromr`/`rfetch`) in `auxSamples`.

Usage: `rv64c check [fuzzCount]`, `rv64c emit <sample>`, `rv64c forth <file.fs> [memWords]` (run a
Forth source file and compare with the Lean semantics), `rv64c emit-forth <file.fs>`.
-/

open WordDialect

def dBase : Nat := 0x10000000
def capacity : Nat := 65536
def dEnd : Nat := dBase + 8 * capacity
/-- Return-stack placement: `rcap` entries in `.rstack`, linked at `rBase`. -/
def rBase : Nat := 0x10200000
def rcap : Nat := 65536
def rEnd : Nat := rBase + 8 * rcap
/-- Auxiliary-stack placement: `acap` words in `.astack`, linked at `aBase` (disjoint from
`.dstack`, which ends at `dEnd = 0x10080000`). -/
def aBase : Nat := 0x10100000
def acap : Nat := 65536
def aEnd : Nat := aBase + 8 * acap

def runtimeFor (s : Sample) : RV.Emit.Runtime :=
  { dEnd := dEnd, capacity := capacity, rEnd := rEnd, rcap := rcap, memImage := s.mem,
    nregs := s.nregs,
    aEnd := aEnd, acap := acap }

def layoutFor (s : Sample) : RV.Layout := (runtimeFor s).layout

def asmFor (s : Sample) : String :=
  RV.Emit.program (runtimeFor s) (RV.lowerProg (layoutFor s) s.prog)

def workDir : String := "/tmp/rv64c"

def runNative (s : Sample) : IO (Except String Result) := do
  IO.FS.createDirAll workDir
  let base := s!"{workDir}/{s.name}"
  IO.FS.writeFile (base ++ ".s") (asmFor s)
  let asArgs := #["--target=riscv64-linux-gnu", "-march=rv64im", "-c", "-o", base ++ ".o", base ++ ".s"]
  let a ← IO.Process.output { cmd := "clang", args := asArgs }
  if a.exitCode != 0 then return .error s!"clang failed: {a.stderr}"
  let l ← IO.Process.output { cmd := "ld.lld", args := #[s!"--section-start=.dstack={RV.Emit.hex dBase}",
    s!"--section-start=.astack={RV.Emit.hex aBase}", s!"--section-start=.rstack={RV.Emit.hex rBase}",
    "-o", base, base ++ ".o"] }
  if l.exitCode != 0 then return .error s!"ld.lld failed: {l.stderr}"
  let child ← IO.Process.spawn
    { cmd := "qemu-riscv64", args := #[base], stdout := .piped, stderr := .null, stdin := .null }
  let bytes ← readAll child.stdout ByteArray.empty
  let code ← child.wait
  if code == 0 then
    match parseDump s bytes with
    | some r => return .ok r
    | none => return .error s!"malformed dump ({bytes.size} bytes)"
  else
    return .ok (.trap code.toNat)


/-- Programs whose IR run never terminates and grows a stack without bound: the emitted code must
stop them with the overflow exit (code 6) instead of running off the end of a stack. -/
def overflowSamples : List Sample :=
  [ { name := "ovf_word_loop", prog := [.word 1#64, .jmp 0], mem := [] },
    { name := "ovf_dup_loop", prog := [.word 1#64, .dup, .jmp 1], mem := [] },
    { name := "ovf_call_loop", prog := [.call 0], mem := [] },
    { name := "ovf_tor_loop", prog := [.word 1#64, .tor, .jmp 0], mem := [] } ]

/-- Raw IR programs for the auxiliary stack, checked against the Lean semantics. -/
def auxSamples : List Sample :=
  [ -- park 7, copy it (R@), add, take it back, multiply: (3 + 7) * 7 = 70
    { name := "aux_basic", mem := [], nregs := 1,
      prog := [.word 7, .tor, .word 3, .rfetch, .add, .fromr, .mul, .halt] }
    -- a value parked across a `call` whose body uses the aux stack itself: 5*5 + 100 = 125
  , { name := "aux_across_call", mem := [], nregs := 1,
      prog := [.word 100, .tor, .word 5, .call 7, .fromr, .add, .halt,
               .tor, .rfetch, .fromr, .mul, .ret] }
    -- recursive factorial keeping `n` on the aux stack across the recursive call: 5! = 120
  , { name := "aux_fact_rec", mem := [], nregs := 1,
      prog := [.word 5, .call 3, .halt,
               .dup, .branch 8, .drop, .word 1, .ret,
               .dup, .tor, .word 1, .sub, .call 3, .fromr, .mul, .ret] }
    -- `fromr` / `rfetch` on an empty aux stack trap returnUnderflow (5)
  , { name := "aux_fromr_empty", mem := [], nregs := 1, prog := [.word 1, .fromr, .halt] }
  , { name := "aux_rfetch_empty", mem := [], nregs := 1, prog := [.rfetch, .halt] }
    -- `ret` does not see aux-stack values: still returnUnderflow (5)
  , { name := "aux_ret_not_aux", mem := [], nregs := 1, prog := [.word 1, .tor, .ret] }
    -- `tor` on an empty data stack traps stackUnderflow (1)
  , { name := "aux_tor_underflow", mem := [], nregs := 1, prog := [.tor, .halt] }
  ]

def checkAux : IO Bool := do
  let mut ok := true
  for s in auxSamples do
    if !(← check runNative s) then ok := false
  return ok

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
    match (allSamples ++ auxSamples).find? (·.name == name) with
    | some s => IO.println (asmFor s); return 0
    | none => IO.eprintln "unknown sample"; return 1
  | "forth" :: path :: rest =>
    match parseMem rest with
    | none => IO.eprintln "usage: rv64c forth <file.fs> [memWords]"; return 2
    | some m =>
      let s ← forthFileSample path m
      return (if ← check runNative s then 0 else 1)
  | "emit-forth" :: path :: rest =>
    match parseMem rest with
    | none => IO.eprintln "usage: rv64c emit-forth <file.fs> [memWords]"; return 2
    | some m =>
      let s ← forthFileSample path m
      match s.buildError with
      | some e => IO.eprintln e; return 1
      | none => IO.println (asmFor s); return 0
  | "check" :: rest =>
    let count := match rest with | [n] => n.toNat! | _ => 200
    let agree ← checkAll runNative count
    let aux ← checkAux
    let ovf ← checkOverflow
    return (if agree && aux && ovf then 0 else 1)
  | _ => IO.eprintln "usage: rv64c check [fuzzCount] | rv64c emit <sample> | rv64c forth <file.fs> [memWords] | rv64c emit-forth <file.fs> [memWords]"; return 2
