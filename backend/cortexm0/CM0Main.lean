import Harness32
import CM0

/-!
# cm0c

Execution harness for the Cortex-M0 profile: ARMv6-M, 32-bit words, no operating system, no
divide instruction. For each program it
1. lowers the 32-bit IR to ARMv6-M Thumb and emits assembly with the bare-metal runtime
   (`CM0.Emit`),
2. assembles it with `clang --target=thumbv6m-none-eabi -mcpu=cortex-m0` and links it with
   `ld.lld` and the linker script `linkerScript`: vector table and code in flash from address 0,
   `.data` in SRAM from `0x20000000` with its load address in flash, the three stacks in SRAM,
3. runs the image on the emulated BBC micro:bit, an nRF51822 (Cortex-M0, 256 KiB of flash,
   16 KiB of SRAM; `qemu-system-arm -M microbit`). It takes the initial stack pointer and reset
   vector from the vector table, copies `.data` from flash to SRAM, prints through the nRF51
   UART and stops through semihosting,
4. runs the same IR program under the Lean semantics at width 32 (`WordDialect.run`), and
5. compares the exit status and the dumped data stack, IR memory and virtual registers.

The programs and the comparison are those of `Harness32`, shared with `rv32c` and `cmc`: the
shared samples and generated programs narrowed to 32-bit words, 32-bit edge cases (including
`INT_MIN / -1`, which the division loop must wrap), the auxiliary-stack and overflow programs,
and Forth source files compiled at width 32.

Usage: `cm0c check [fuzzCount]`, `cm0c emit <sample>`, `cm0c forth <file.fs> [memWords]`,
`cm0c emit-forth <file.fs> [memWords]`.
-/

open WordDialect

/-! ## Building and running on the micro:bit -/

/-- SRAM (16 KiB from `0x20000000`): `.data` in the first 1 KiB, then the three stacks of 1024
words (4 KiB) each; the return stack, which `sp` points into, is the last. -/
def dBase : Nat := 0x20000400
def capacity : Nat := 1024
def dEnd : Nat := dBase + 4 * capacity
def aBase : Nat := 0x20001400
def acap : Nat := 1024
def aEnd : Nat := aBase + 4 * acap
def rBase : Nat := 0x20002400
def rcap : Nat := 1024
def rEnd : Nat := rBase + 4 * rcap

def runtimeFor (s : Sample32) : CM0.Emit.Runtime :=
  { dEnd := dEnd, capacity := capacity, rEnd := rEnd, rcap := rcap, memImage := s.mem,
    nregs := s.nregs, aEnd := aEnd, acap := acap }

def asmFor (s : Sample32) : String :=
  CM0.Emit.program (runtimeFor s) (CM0.lowerProg (runtimeFor s).layout s.prog)

/-- The vector table and code in flash from address 0 (where a Cortex-M reads its initial stack
pointer and reset vector); `.data` in the first 1 KiB of SRAM, loaded into flash after the code
(`__data_load`); the stacks are uninitialised sections at fixed addresses. -/
def linkerScript : String :=
  "ENTRY(_start)\nMEMORY {\n  FLASH (rx) : ORIGIN = 0x0, LENGTH = 256K\n" ++
  "  DATA (rw) : ORIGIN = 0x20000000, LENGTH = 1K\n  STACKS (rw) : ORIGIN = 0x20000400, LENGTH = 12K\n}\nSECTIONS {\n" ++
  "  .vectors : { *(.vectors) } > FLASH\n  .text : { *(.text*) } > FLASH\n" ++
  "  .data : { *(.data*) } > DATA AT > FLASH\n  __data_load = LOADADDR(.data);\n" ++
  s!"  .dstack {CM0.Emit.hex dBase} (NOLOAD) : \{ *(.dstack) } > STACKS\n" ++
  s!"  .astack {CM0.Emit.hex aBase} (NOLOAD) : \{ *(.astack) } > STACKS\n" ++
  s!"  .rstack {CM0.Emit.hex rBase} (NOLOAD) : \{ *(.rstack) } > STACKS\n}\n"

def workDir : String := "/tmp/cm0c"

/-- Assemble, link and run one assembly file; the UART output and the exit status. -/
def runAsm (name asm : String) : IO (Except String (String × UInt32)) := do
  IO.FS.createDirAll workDir
  let base := s!"{workDir}/{name}"
  IO.FS.writeFile (base ++ ".s") asm
  IO.FS.writeFile (workDir ++ "/link.ld") linkerScript
  let asArgs := #["--target=thumbv6m-none-eabi", "-mcpu=cortex-m0", "-c", "-o", base ++ ".o",
    base ++ ".s"]
  let a ← IO.Process.output { cmd := "clang", args := asArgs }
  if a.exitCode != 0 then return .error s!"clang failed: {a.stderr}"
  let l ← IO.Process.output
    { cmd := "ld.lld", args := #["-T", workDir ++ "/link.ld", "-o", base, base ++ ".o"] }
  if l.exitCode != 0 then return .error s!"ld.lld failed: {l.stderr}"
  let child ← IO.Process.spawn
    { cmd := "qemu-system-arm",
      args := #["-machine", "microbit", "-kernel", base, "-display", "none", "-serial", "stdio",
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
    | none => IO.eprintln "usage: cm0c forth <file.fs> [memWords]"; return 2
    | some m => return (if ← check32 runNative (← forthFileSample32 path m) then 0 else 1)
  | "emit-forth" :: path :: rest =>
    match parseMem rest with
    | none => IO.eprintln "usage: cm0c emit-forth <file.fs> [memWords]"; return 2
    | some m =>
      let s ← forthFileSample32 path m
      match s.buildError with
      | some e => IO.eprintln e; return 1
      | none => IO.println (asmFor s); return 0
  | "check" :: rest =>
    let count := match rest with | [n] => n.toNat! | _ => 200
    let ok ← checkAll32 runNative count
    return (if ok then 0 else 1)
  | _ => IO.eprintln "usage: cm0c check [fuzzCount] | cm0c emit <sample> | cm0c forth <file.fs> [memWords] | cm0c emit-forth <file.fs> [memWords]"; return 2
