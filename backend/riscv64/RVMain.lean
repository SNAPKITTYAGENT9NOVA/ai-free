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

`check` also runs the auxiliary-stack programs (`tor`/`fromr`/`rfetch`) in `auxSamples`, and the
hand-written data-processing programs of `RV.DataOps` plus 100 random ones, comparing registers.

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

/-! ## Hand-written RISC-V programs (`RV.DataOps`)

A program over `a0 … a7, s7 … s10` (three-register `alu`, `shiftImm`, `divu`/`div`, `movImm`),
printed by `RV.Emit` and run under `qemu-riscv64`; at `exitHalt` the runtime writes the twelve
registers to stdout. They must equal the model's (`RV.haltRegs`). -/

def isaRegs : List RV.Reg := RV.dataRegs

def isaAsm (code : List (RV.Instr Nat)) : String :=
  "\t.option norelax\n\t.text\n\t.globl _start\n\t.p2align 2\n_start:\n" ++ RV.Emit.body code ++
  ".Lhalt:\n\tlla t0, rbuf\n" ++
  String.join (isaRegs.zipIdx.map fun (r, k) => s!"\tsd {RV.Emit.regName r}, {8 * k}(t0)\n") ++
  "\tli a0, 1\n\tmv a1, t0\n\tli a2, 96\n\tli a7, 64\n\tecall\n" ++
  "\tli a0, 0\n\tli a7, 93\n\tecall\n\t.bss\n\t.balign 8\nrbuf:\n\t.skip 96\n"

def runIsa (name : String) (code : List (RV.Instr Nat)) : IO (Except String (List Nat)) := do
  IO.FS.createDirAll workDir
  let base := s!"{workDir}/{name}"
  IO.FS.writeFile (base ++ ".s") (isaAsm code)
  let asArgs := #["--target=riscv64-linux-gnu", "-march=rv64im", "-c", "-o", base ++ ".o", base ++ ".s"]
  let a ← IO.Process.output { cmd := "clang", args := asArgs }
  if a.exitCode != 0 then return .error s!"clang failed: {a.stderr}"
  let l ← IO.Process.output { cmd := "ld.lld", args := #["-o", base, base ++ ".o"] }
  if l.exitCode != 0 then return .error s!"ld.lld failed: {l.stderr}"
  let child ← IO.Process.spawn
    { cmd := "qemu-riscv64", args := #[base], stdout := .piped, stderr := .null, stdin := .null }
  let bytes ← readAll child.stdout ByteArray.empty
  let code ← child.wait
  if code != 0 then return .error s!"exit {code}"
  if bytes.size != 96 then return .error s!"dump of {bytes.size} bytes"
  return .ok ((List.range 12).map fun k => u64 bytes (8 * k))

def checkIsaProg (name : String) (code : List (RV.Instr Nat)) : IO Bool := do
  let model := (RV.haltRegs code 1000 (fun _ => 0#64) (Memory.ofImage []) isaRegs).map
    (·.map BitVec.toNat)
  match model, ← runIsa name code with
  | some exp, .ok got =>
    if exp == got then IO.println s!"PASS  {name}  {got}"; return true
    else IO.println s!"FAIL  {name}\n  lean:   {exp}\n  target: {got}"; return false
  | none, _ => IO.println s!"ERROR {name}: the model did not halt"; return false
  | _, .error e => IO.println s!"ERROR {name}: {e}"; return false

/-- A pseudo-random program over the twelve registers: initialise all of them, then `len`
data-processing instructions (including register shifts by amounts of 64 or more, and divisions
by zero). `seed` drives a linear congruential generator. -/
def randomIsa (seed len : Nat) : List (RV.Instr Nat) := Id.run do
  let regs := isaRegs.toArray
  let mut st := seed
  let next (st : Nat) : Nat := (st * 6364136223846793005 + 1442695040888963407) % 2 ^ 64
  let mut code : Array (RV.Instr Nat) := #[]
  for r in isaRegs do
    st := next st
    -- every fourth register starts small, so shifts by large amounts and zero divisors occur
    let v := if st % 4 == 0 then (st / 2 ^ 32) % 80 else st
    code := code.push (.movImm r (BitVec.ofNat 64 v))
  for _ in List.range len do
    st := next st
    let pick (k : Nat) : RV.Reg := regs.getD ((st / 2 ^ (8 * k)) % 12) .a0
    let d := pick 1; let a := pick 2; let b := pick 3
    let n := (st / 2 ^ 40) % 64
    let i : RV.Instr Nat := match (st / 2 ^ 56) % 14 with
      | 0 => .alu .add d a b | 1 => .alu .sub d a b | 2 => .alu .mul d a b
      | 3 => .alu .and d a b | 4 => .alu .or d a b | 5 => .alu .xor d a b
      | 6 => .alu .sll d a b | 7 => .alu .srl d a b | 8 => .alu .sra d a b
      | 9 => .shiftImm .sll d a n | 10 => .shiftImm .srl d a n | 11 => .shiftImm .sra d a n
      | 12 => .divu d a b
      | _ => .div d a b
    code := code.push i
  return (code.push .exitHalt).toList

def checkIsa (count : Nat) : IO Bool := do
  let mut ok ← checkIsaProg "isa_data_processing" RV.dataProcessing
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
    let isa ← checkIsa 100
    return (if agree && aux && ovf && isa then 0 else 1)
  | _ => IO.eprintln "usage: rv64c check [fuzzCount] | rv64c emit <sample> | rv64c forth <file.fs> [memWords] | rv64c emit-forth <file.fs> [memWords]"; return 2
