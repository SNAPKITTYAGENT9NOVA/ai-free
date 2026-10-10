import Harness32
import RV32

/-!
# rv32c

Execution harness for the RV32IM microcontroller profile: 32-bit words, no operating system. For
each program it
1. lowers the 32-bit IR to RV32IM and emits assembly with the bare-metal runtime (`RV32.Emit`),
2. assembles it with `clang --target=riscv32-unknown-elf -march=rv32im` and links it with
   `ld.lld` and the linker script `linkerScript` (code and data in RAM from `0x80000000`, the
   three stacks at fixed addresses),
3. runs the image on the QEMU `virt` board (`qemu-system-riscv32 -bios none`), where it starts at
   `_start` with no firmware or kernel, prints through the UART and stops through the test device,
4. runs the same IR program under the Lean semantics at width 32 (`WordDialect.run`), and
5. compares the exit status and the dumped data stack, IR memory and virtual registers.

The programs and the comparison are those of `Harness32`: the shared samples and generated
programs narrowed to 32-bit words, 32-bit edge cases, the auxiliary-stack and overflow programs,
and Forth source files compiled at width 32. `check` also runs the hand-written data-processing
programs of `RV32.DataOps`.

Usage: `rv32c check [fuzzCount]`, `rv32c emit <sample>`, `rv32c forth <file.fs> [memWords]`,
`rv32c emit-forth <file.fs> [memWords]`.
-/

open WordDialect

/-! ## Building and running on the `virt` board -/

def dBase : Nat := 0x80100000
def capacity : Nat := 4096
def dEnd : Nat := dBase + 4 * capacity
def aBase : Nat := 0x80200000
def acap : Nat := 4096
def aEnd : Nat := aBase + 4 * acap
def rBase : Nat := 0x80300000
def rcap : Nat := 4096
def rEnd : Nat := rBase + 4 * rcap

def runtimeFor (s : Sample32) : RV32.Emit.Runtime :=
  { dEnd := dEnd, capacity := capacity, rEnd := rEnd, rcap := rcap, memImage := s.mem,
    nregs := s.nregs, aEnd := aEnd, acap := acap }

def asmFor (s : Sample32) : String :=
  RV32.Emit.program (runtimeFor s) (RV32.lowerProg (runtimeFor s).layout s.prog)

/-- Code from `0x80000000` (where the `virt` board starts with `-bios none`), then data; the
stacks are uninitialised sections at fixed addresses. -/
def linkerScript : String :=
  "ENTRY(_start)\nSECTIONS {\n  . = 0x80000000;\n  .text : { *(.text.start) *(.text*) }\n" ++
  "  .data : { *(.data*) }\n" ++
  s!"  .dstack {RV32.Emit.hex dBase} (NOLOAD) : \{ *(.dstack) }\n" ++
  s!"  .astack {RV32.Emit.hex aBase} (NOLOAD) : \{ *(.astack) }\n" ++
  s!"  .rstack {RV32.Emit.hex rBase} (NOLOAD) : \{ *(.rstack) }\n}\n"

def workDir : String := "/tmp/rv32c"

/-- Assemble, link and run one assembly file; the UART output and the exit status. -/
def runAsm (name asm : String) : IO (Except String (String × UInt32)) := do
  IO.FS.createDirAll workDir
  let base := s!"{workDir}/{name}"
  IO.FS.writeFile (base ++ ".s") asm
  IO.FS.writeFile (workDir ++ "/link.ld") linkerScript
  let asArgs := #["--target=riscv32-unknown-elf", "-march=rv32im", "-mabi=ilp32", "-c", "-o",
    base ++ ".o", base ++ ".s"]
  let a ← IO.Process.output { cmd := "clang", args := asArgs }
  if a.exitCode != 0 then return .error s!"clang failed: {a.stderr}"
  let l ← IO.Process.output
    { cmd := "ld.lld", args := #["-T", workDir ++ "/link.ld", "-o", base, base ++ ".o"] }
  if l.exitCode != 0 then return .error s!"ld.lld failed: {l.stderr}"
  let child ← IO.Process.spawn
    { cmd := "qemu-system-riscv32",
      args := #["-machine", "virt", "-bios", "none", "-kernel", base, "-display", "none",
        "-serial", "stdio", "-monitor", "none", "-m", "128M"],
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

/-! ## Hand-written RV32 programs (`RV32.DataOps`) -/

def isaRegs : List RV32.Reg := RV32.dataRegs

/-- The program, then at `exitHalt` the twelve registers are stored to `rbuf` and printed. -/
def isaAsm (code : List (RV32.Instr Nat)) : String :=
  let r : RV32.Emit.Runtime :=
    { dEnd := 0, capacity := 0, rEnd := 0, rcap := 0, memImage := [], nregs := 0, aEnd := 0,
      acap := 0 }
  "\t.option norelax\n\t.section .text.start, \"ax\", @progbits\n\t.globl _start\n\t.p2align 2\n_start:\n" ++
  RV32.Emit.body code ++ ".Lhalt:\n\tlla t0, rbuf\n" ++
  String.join (isaRegs.zipIdx.map fun (x, k) => s!"\tsw {RV32.Emit.regName x}, {4 * k}(t0)\n") ++
  "\tmv a1, t0\n\tli a2, 12\n\tjal putws\n" ++
  s!"\tli a0, 0x5555\n\t{RV32.Emit.li "t0" r.exitBase}\n\tsw a0, 0(t0)\n7:\tj 7b\n" ++
  RV32.Emit.devices r ++ "\t.data\n\t.balign 4\nrbuf:\n\t.zero 48\n"

def checkIsaProg (name : String) (code : List (RV32.Instr Nat)) : IO Bool := do
  let model := (RV32.haltRegs code 1000 (fun _ => 0#32) (Memory.ofImage []) isaRegs).map
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

/-- A pseudo-random program over the twelve registers (as in `rv64c`). -/
def randomIsa (seed len : Nat) : List (RV32.Instr Nat) := Id.run do
  let regs := isaRegs.toArray
  let mut st := seed
  let next (st : Nat) : Nat := (st * 6364136223846793005 + 1442695040888963407) % 2 ^ 64
  let mut code : Array (RV32.Instr Nat) := #[]
  for r in isaRegs do
    st := next st
    let v := if st % 4 == 0 then (st / 2 ^ 32) % 48 else st / 2 ^ 32
    code := code.push (.movImm r (BitVec.ofNat 32 v))
  for _ in List.range len do
    st := next st
    let pick (k : Nat) : RV32.Reg := regs.getD ((st / 2 ^ (8 * k)) % 12) .a0
    let d := pick 1; let a := pick 2; let b := pick 3
    let n := (st / 2 ^ 40) % 32
    let i : RV32.Instr Nat := match (st / 2 ^ 56) % 14 with
      | 0 => .alu .add d a b | 1 => .alu .sub d a b | 2 => .alu .mul d a b
      | 3 => .alu .and d a b | 4 => .alu .or d a b | 5 => .alu .xor d a b
      | 6 => .alu .sll d a b | 7 => .alu .srl d a b | 8 => .alu .sra d a b
      | 9 => .shiftImm .sll d a n | 10 => .shiftImm .srl d a n | 11 => .shiftImm .sra d a n
      | 12 => .divu d a b
      | _ => .div d a b
    code := code.push i
  return (code.push .exitHalt).toList

def checkIsa (count : Nat) : IO Bool := do
  let mut ok ← checkIsaProg "isa_data_processing" RV32.dataProcessing
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
    | none => IO.eprintln "usage: rv32c forth <file.fs> [memWords]"; return 2
    | some m => return (if ← check32 runNative (← forthFileSample32 path m) then 0 else 1)
  | "emit-forth" :: path :: rest =>
    match parseMem rest with
    | none => IO.eprintln "usage: rv32c emit-forth <file.fs> [memWords]"; return 2
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
  | _ => IO.eprintln "usage: rv32c check [fuzzCount] | rv32c emit <sample> | rv32c forth <file.fs> [memWords] | rv32c emit-forth <file.fs> [memWords]"; return 2
