import Harness32
import CM

/-!
# cmc

Execution harness for the Cortex-M profile: Thumb-2 (ARMv7-M), 32-bit words, no operating system.
For each program it
1. lowers the 32-bit IR to Thumb-2 and emits assembly with the bare-metal runtime (`CM.Emit`),
2. assembles it with `clang --target=thumbv7m-none-eabi -mcpu=cortex-m3` and links it with
   `ld.lld` and the linker script `linkerScript` (vector table and code from address 0, data in
   SRAM from `0x20000000`, the three stacks at fixed addresses),
3. runs the image on the emulated ARM MPS2 board with a Cortex-M3 (`qemu-system-arm -M
   mps2-an385`), which takes the initial stack pointer and reset vector from the vector table,
   prints through the CMSDK UART and stops through semihosting,
4. runs the same IR program under the Lean semantics at width 32 (`WordDialect.run`), and
5. compares the exit status and the dumped data stack, IR memory and virtual registers.

The programs and the comparison are those of `Harness32`, shared with `rv32c`: the shared
samples and generated programs narrowed to 32-bit words, 32-bit edge cases, the auxiliary-stack
and overflow programs, and Forth source files compiled at width 32. `check` also runs the
hand-written data-processing programs of `CM.DataOps`.

Usage: `cmc check [fuzzCount]`, `cmc emit <sample>`, `cmc forth <file.fs> [memWords]`,
`cmc emit-forth <file.fs> [memWords]`.
-/

open WordDialect

/-! ## Building and running on the MPS2 board -/

def dBase : Nat := 0x20100000
def capacity : Nat := 4096
def dEnd : Nat := dBase + 4 * capacity
def aBase : Nat := 0x20200000
def acap : Nat := 4096
def aEnd : Nat := aBase + 4 * acap
def rBase : Nat := 0x20300000
def rcap : Nat := 4096
def rEnd : Nat := rBase + 4 * rcap

def runtimeFor (s : Sample32) : CM.Emit.Runtime :=
  { dEnd := dEnd, capacity := capacity, rEnd := rEnd, rcap := rcap, memImage := s.mem,
    nregs := s.nregs, aEnd := aEnd, acap := acap }

def asmFor (s : Sample32) : String :=
  CM.Emit.program (runtimeFor s) (CM.lowerProg (runtimeFor s).layout s.prog)

/-- The vector table and code from address 0 (where a Cortex-M reads its initial stack pointer
and reset vector), data in SRAM; the stacks are uninitialised sections at fixed addresses. -/
def linkerScript : String :=
  "ENTRY(_start)\nSECTIONS {\n  . = 0x0;\n  .vectors : { *(.vectors) }\n  .text : { *(.text*) }\n" ++
  "  .data 0x20000000 : { *(.data*) }\n" ++
  s!"  .dstack {CM.Emit.hex dBase} (NOLOAD) : \{ *(.dstack) }\n" ++
  s!"  .astack {CM.Emit.hex aBase} (NOLOAD) : \{ *(.astack) }\n" ++
  s!"  .rstack {CM.Emit.hex rBase} (NOLOAD) : \{ *(.rstack) }\n}\n"

def workDir : String := "/tmp/cmc"

/-- Assemble, link and run one assembly file; the UART output and the exit status. -/
def runAsm (name asm : String) : IO (Except String (String × UInt32)) := do
  IO.FS.createDirAll workDir
  let base := s!"{workDir}/{name}"
  IO.FS.writeFile (base ++ ".s") asm
  IO.FS.writeFile (workDir ++ "/link.ld") linkerScript
  let asArgs := #["--target=thumbv7m-none-eabi", "-mcpu=cortex-m3", "-c", "-o", base ++ ".o",
    base ++ ".s"]
  let a ← IO.Process.output { cmd := "clang", args := asArgs }
  if a.exitCode != 0 then return .error s!"clang failed: {a.stderr}"
  let l ← IO.Process.output
    { cmd := "ld.lld", args := #["-T", workDir ++ "/link.ld", "-o", base, base ++ ".o"] }
  if l.exitCode != 0 then return .error s!"ld.lld failed: {l.stderr}"
  let child ← IO.Process.spawn
    { cmd := "qemu-system-arm",
      args := #["-machine", "mps2-an385", "-kernel", base, "-display", "none", "-serial", "stdio",
        "-monitor", "none", "-semihosting-config", "enable=on,target=native"],
      stdout := .piped, stderr := .null, stdin := .null }
  let out ← readAll child.stdout ByteArray.empty
  let code ← child.wait
  match String.fromUTF8? out with
  | some t => return .ok (t, code)
  | none => return .error "UART output is not text"

def runNative : Runner32 := fun s => do
  match ← runAsm s.name (asmFor s) with
  | .error e => return .error e
  | .ok (out, code) => return (if code != 0 then .ok (.trap code.toNat) else parseHexDump s out)

/-! ## Hand-written Cortex-M programs (`CM.DataOps`) -/

def isaRegs : List CM.Reg := CM.dataRegs

/-- The program; at `exitHalt` the twelve registers are stored to `rbuf` and printed. -/
def isaAsm (code : List (CM.Instr Nat)) : String :=
  let r : CM.Emit.Runtime :=
    { dEnd := 0, capacity := 0, rEnd := 0, rcap := 0, memImage := [], nregs := 0, aEnd := 0,
      acap := 0 }
  CM.Emit.vectors r ++ "\t.text\n\t.globl _start\n\t.thumb_func\n_start:\n" ++
  CM.Emit.body code ++ s!".Lhalt:\n\t{CM.Emit.la "r12" "rbuf"}\n" ++
  String.join (isaRegs.zipIdx.map fun (x, k) => s!"\tstr {CM.Emit.regName x}, [r12, #{4 * k}]\n") ++
  CM.Emit.uartOn r ++ s!"\t{CM.Emit.la "r7" "rbuf"}\n\tmovs r9, #12\n\tbl putws\n" ++
  "\tmovs r1, #0\n\tb .Lexit\n" ++ CM.Emit.devices r ++
  "\t.data\n\t.balign 4\nrbuf:\n\t.zero 48\nexitblk:\n\t.word 0, 0\n"

def checkIsaProg (name : String) (code : List (CM.Instr Nat)) : IO Bool := do
  let model := (CM.haltRegs code 1000 (fun _ => 0#32) (Memory.ofImage []) isaRegs).map
    (·.map BitVec.toNat)
  let got ← runAsm name (isaAsm code)
  match model, got with
  | some exp, .ok (out, 0) =>
    match hexWords out with
    | some g =>
      if exp == g then IO.println s!"PASS  {name}  {g}"; return true
      else IO.println s!"FAIL  {name}\n  lean:   {exp}\n  target: {g}"; return false
    | none => IO.println s!"ERROR {name}: malformed output {out}"; return false
  | none, _ => IO.println s!"ERROR {name}: the model did not halt"; return false
  | _, .ok (_, c) => IO.println s!"ERROR {name}: exit {c}"; return false
  | _, .error e => IO.println s!"ERROR {name}: {e}"; return false

/-- A pseudo-random program over `r0 … r11`: initialise all twelve (some to small values, so
register shifts by 32 … 255 and by 256 or more, and zero divisors, occur), then `len`
data-processing instructions. `seed` drives a linear congruential generator. -/
def randomIsa (seed len : Nat) : List (CM.Instr Nat) := Id.run do
  let regs := isaRegs.toArray
  let mut st := seed
  let next (st : Nat) : Nat := (st * 6364136223846793005 + 1442695040888963407) % 2 ^ 64
  let mut code : Array (CM.Instr Nat) := #[]
  for r in isaRegs do
    st := next st
    let v := if st % 4 == 0 then (st / 2 ^ 32) % 300 else st / 2 ^ 32
    code := code.push (.movImm r (BitVec.ofNat 32 v))
  for _ in List.range len do
    st := next st
    let pick (k : Nat) : CM.Reg := regs.getD ((st / 2 ^ (8 * k)) % 12) .r0
    let d := pick 1; let a := pick 2; let b := pick 3
    let n := (st / 2 ^ 40) % 32
    let i : CM.Instr Nat := match (st / 2 ^ 56) % 14 with
      | 0 => .alu .add d a b | 1 => .alu .sub d a b | 2 => .alu .mul d a b
      | 3 => .alu .and d a b | 4 => .alu .orr d a b | 5 => .alu .eor d a b
      | 6 => .alu .lsl d a b | 7 => .alu .lsr d a b | 8 => .alu .asr d a b
      | 9 => .shiftImm .lsl d a n | 10 => .shiftImm .lsr d a n | 11 => .shiftImm .asr d a n
      | 12 => .divu d a b
      | _ => .div d a b
    code := code.push i
  return (code.push .exitHalt).toList

def checkIsa (count : Nat) : IO Bool := do
  let mut ok ← checkIsaProg "isa_data_processing" CM.dataProcessing
  let mut agree := 0
  for k in List.range count do
    if ← checkIsaProg s!"isa_random_{k}" (randomIsa (k + 1) 40) then agree := agree + 1 else ok := false
  IO.println s!"isa: {agree}/{count} random data-processing programs agree"
  return ok

/-! ## Driver -/

def parseMem (rest : List String) : Option Nat :=
  match rest with
  | [] => some 16
  | [m] => m.toNat?
  | _ => none

def main (args : List String) : IO UInt32 := do
  match args with
  | ["emit", name] =>
    match allSamples32.find? (·.name == name) with
    | some s => IO.println (asmFor s); return 0
    | none => IO.eprintln "unknown sample"; return 1
  | "forth" :: path :: rest =>
    match parseMem rest with
    | none => IO.eprintln "usage: cmc forth <file.fs> [memWords]"; return 2
    | some m => return (if ← check32 runNative (← forthFileSample32 path m) then 0 else 1)
  | "emit-forth" :: path :: rest =>
    match parseMem rest with
    | none => IO.eprintln "usage: cmc emit-forth <file.fs> [memWords]"; return 2
    | some m =>
      let s ← forthFileSample32 path m
      match s.buildError with
      | some e => IO.eprintln e; return 1
      | none => IO.println (asmFor s); return 0
  | "check" :: rest =>
    let count := match rest with | [n] => n.toNat! | _ => 200
    let ok ← checkAll32 runNative count
    let isa ← checkIsa 100
    return (if ok && isa then 0 else 1)
  | _ => IO.eprintln "usage: cmc check [fuzzCount] | cmc emit <sample> | cmc forth <file.fs> [memWords] | cmc emit-forth <file.fs> [memWords]"; return 2
