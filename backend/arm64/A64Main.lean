import Harness
import A64

/-!
# a64c

Execution harness for the AArch64 backend. For each program it
1. lowers the IR to AArch64 and emits assembly (`A64.Emit`),
2. assembles it with `clang --target=aarch64-linux-gnu` and links it with `ld.lld`,
3. runs the binary under `qemu-aarch64` (user-mode emulation; on an AArch64 Linux host the
   binary also runs directly),
4. runs the same IR program under the Lean semantics (`WordDialect.run`), and
5. compares exit status and the dumped data stack, IR memory and virtual registers
   (the shared `Harness`).

`check` also runs the auxiliary-stack programs (`tor`/`fromr`/`rfetch`) in `auxSamples`.

Usage: `a64c check [fuzzCount]`, `a64c emit <sample>`, `a64c forth <file.fs> [memWords]` (run a
Forth source file and compare with the Lean semantics), `a64c emit-forth <file.fs>`.
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

def runtimeFor (s : Sample) : A64.Emit.Runtime :=
  { dEnd := dEnd, capacity := capacity, rEnd := rEnd, rcap := rcap, memImage := s.mem,
    nregs := s.nregs,
    aEnd := aEnd, acap := acap }

def layoutFor (s : Sample) : A64.Layout := (runtimeFor s).layout

def asmFor (s : Sample) : String :=
  A64.Emit.program (runtimeFor s) (A64.lowerProg (layoutFor s) s.prog)

def workDir : String := "/tmp/a64c"

def runNative (s : Sample) : IO (Except String Result) := do
  IO.FS.createDirAll workDir
  let base := s!"{workDir}/{s.name}"
  IO.FS.writeFile (base ++ ".s") (asmFor s)
  let asArgs := #["--target=aarch64-linux-gnu", "-c", "-o", base ++ ".o", base ++ ".s"]
  let a ← IO.Process.output { cmd := "clang", args := asArgs }
  if a.exitCode != 0 then return .error s!"clang failed: {a.stderr}"
  let l ← IO.Process.output { cmd := "ld.lld", args := #[s!"--section-start=.dstack={A64.Emit.hex dBase}",
    s!"--section-start=.astack={A64.Emit.hex aBase}", s!"--section-start=.rstack={A64.Emit.hex rBase}",
    "-o", base, base ++ ".o"] }
  if l.exitCode != 0 then return .error s!"ld.lld failed: {l.stderr}"
  let child ← IO.Process.spawn
    { cmd := "qemu-aarch64", args := #[base], stdout := .piped, stderr := .null, stdin := .null }
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

/-! ## Hand-written AArch64 programs (`A64.DataOps`)

A program over `x0 … x11` (three-register `alu`, `shiftImm`, `udiv`, `movImm`), printed by
`A64.Emit` and run under `qemu-aarch64`; at `exitHalt` the runtime writes `x0 … x11` to stdout.
The registers must equal the model's (`A64.haltRegs`). -/

def isaRegs : List A64.Reg := [.x0, .x1, .x2, .x3, .x4, .x5, .x6, .x7, .x8, .x9, .x10, .x11]

def isaAsm (code : List (A64.Instr Nat)) : String :=
  "\t.text\n\t.globl _start\n\t.p2align 2\n_start:\n" ++ A64.Emit.body code ++
  ".Lhalt:\n\tadrp x29, rbuf\n\tadd x29, x29, :lo12:rbuf\n" ++
  String.join ((List.range 12).map fun k => s!"\tstr x{k}, [x29, #{8 * k}]\n") ++
  "\tmov x0, #1\n\tmov x1, x29\n\tmov x2, #96\n\tmov x8, #64\n\tsvc #0\n" ++
  "\tmov x0, #0\n\tmov x8, #93\n\tsvc #0\n\t.bss\n\t.balign 8\nrbuf:\n\t.skip 96\n"

def runIsa (name : String) (code : List (A64.Instr Nat)) : IO (Except String (List Nat)) := do
  IO.FS.createDirAll workDir
  let base := s!"{workDir}/{name}"
  IO.FS.writeFile (base ++ ".s") (isaAsm code)
  let asArgs := #["--target=aarch64-linux-gnu", "-c", "-o", base ++ ".o", base ++ ".s"]
  let a ← IO.Process.output { cmd := "clang", args := asArgs }
  if a.exitCode != 0 then return .error s!"clang failed: {a.stderr}"
  let l ← IO.Process.output { cmd := "ld.lld", args := #["-o", base, base ++ ".o"] }
  if l.exitCode != 0 then return .error s!"ld.lld failed: {l.stderr}"
  let child ← IO.Process.spawn
    { cmd := "qemu-aarch64", args := #[base], stdout := .piped, stderr := .null, stdin := .null }
  let bytes ← readAll child.stdout ByteArray.empty
  let code ← child.wait
  if code != 0 then return .error s!"exit {code}"
  if bytes.size != 96 then return .error s!"dump of {bytes.size} bytes"
  return .ok ((List.range 12).map fun k => u64 bytes (8 * k))

def checkIsaProg (name : String) (code : List (A64.Instr Nat)) : IO Bool := do
  let model := (A64.haltRegs code 1000 (fun _ => 0#64) (Memory.ofImage []) isaRegs).map
    (·.map BitVec.toNat)
  match model, ← runIsa name code with
  | some exp, .ok got =>
    if exp == got then IO.println s!"PASS  {name}  {got}"; return true
    else IO.println s!"FAIL  {name}\n  lean:   {exp}\n  target: {got}"; return false
  | none, _ => IO.println s!"ERROR {name}: the model did not halt"; return false
  | _, .error e => IO.println s!"ERROR {name}: {e}"; return false

/-- A pseudo-random program over `x0 … x11`: initialise all twelve, then `len` data-processing
instructions. `seed` drives a linear congruential generator. -/
def randomIsa (seed len : Nat) : List (A64.Instr Nat) := Id.run do
  let regs := isaRegs.toArray
  let mut st := seed
  let next (st : Nat) : Nat := (st * 6364136223846793005 + 1442695040888963407) % 2 ^ 64
  let mut code : Array (A64.Instr Nat) := #[]
  for r in isaRegs do
    st := next st
    code := code.push (.movImm r (BitVec.ofNat 64 st))
  for _ in List.range len do
    st := next st
    let pick (k : Nat) : A64.Reg := regs.getD ((st / 2 ^ (8 * k)) % 12) .x0
    let d := pick 1; let a := pick 2; let b := pick 3
    let n := (st / 2 ^ 40) % 64
    let i : A64.Instr Nat := match (st / 2 ^ 56) % 10 with
      | 0 => .alu .add d a b | 1 => .alu .sub d a b | 2 => .alu .mul d a b
      | 3 => .alu .and d a b | 4 => .alu .orr d a b | 5 => .alu .eor d a b
      | 6 => .shiftImm .lsl d a n | 7 => .shiftImm .lsr d a n | 8 => .shiftImm .asr d a n
      | _ => .udiv d a b
    code := code.push i
  return (code.push .exitHalt).toList

def checkIsa (count : Nat) : IO Bool := do
  let mut ok ← checkIsaProg "isa_data_processing" A64.dataProcessing
  let mut agree := 0
  for k in List.range count do
    if ← checkIsaProg s!"isa_random_{k}" (randomIsa (k + 1) 40) then agree := agree + 1 else ok := false
  IO.println s!"isa: {agree}/{count} random data-processing programs agree"
  return ok

def main (args : List String) : IO UInt32 := do
  match args with
  | ["emit", name] =>
    match (allSamples ++ auxSamples).find? (·.name == name) with
    | some s => IO.println (asmFor s); return 0
    | none => IO.eprintln "unknown sample"; return 1
  | "forth" :: path :: rest =>
    match parseMem rest with
    | none => IO.eprintln "usage: a64c forth <file.fs> [memWords]"; return 2
    | some m =>
      let s ← forthFileSample path m
      return (if ← check runNative s then 0 else 1)
  | "emit-forth" :: path :: rest =>
    match parseMem rest with
    | none => IO.eprintln "usage: a64c emit-forth <file.fs> [memWords]"; return 2
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
    let isa ← checkIsa 100
    return (if agree && aux && ovf && isa then 0 else 1)
  | _ => IO.eprintln "usage: a64c check [fuzzCount] | a64c emit <sample> | a64c forth <file.fs> [memWords] | a64c emit-forth <file.fs> [memWords]"; return 2
