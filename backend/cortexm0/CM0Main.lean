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
   UART and ends the run there (an `EXIT` line and the status, then `wfi`; the harness reads up
   to that line and stops the emulator),
4. runs the same IR program under the Lean semantics at width 32 (`WordDialect.run`), and
5. compares the exit status and the dumped data stack, IR memory and virtual registers.

The programs and the comparison are those of `Harness32`, shared with `rv32c` and `cmc`: the
shared samples and generated programs narrowed to 32-bit words, 32-bit edge cases (including
`INT_MIN / -1`, which the division loop must wrap), the auxiliary-stack and overflow programs,
and Forth source files compiled at width 32.

For a real board, `cm0c image` writes the ELF, an Intel HEX file (copy it onto the micro:bit's
`MICROBIT` drive) and the UART transcript a correct run prints, for the micro:bit V1 or, with
`--board microbit-v2`, the V2; `cm0c verify` checks a serial log captured from the board
(`docs/HARDWARE.md`).

Usage: `cm0c check [fuzzCount]`, `cm0c image <file.fs> [memWords] [--board …]`,
`cm0c verify <file.fs> <serial.log> [memWords]`, `cm0c emit <sample>`, `cm0c forth <file.fs> [memWords]`,
`cm0c emit-forth <file.fs> [memWords]`; `--no-opt` with any of them lowers without the
stack-depth certificate and bound, keeping every guard; `cm0c stats <file.fs>` prints how many
guards the two leave out.
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

/-- A board's UART pins. -/
structure Board where
  name : String
  txPin : Nat
  rxPsel : Nat

/-- The BBC micro:bit V1 (nRF51822, a Cortex-M0): TX P0.24, RX P0.25. The emulator models it. -/
def microbitV1 : Board := { name := "microbit-v1", txPin := 24, rxPsel := 25 }

/-- The BBC micro:bit V2 (nRF52833, a Cortex-M4F, which runs ARMv6-M code): TX P0.06, RX P1.08
(`PSEL` 40 = port 1, pin 8). Not modelled by the emulator; for real boards. -/
def microbitV2 : Board := { name := "microbit-v2", txPin := 6, rxPsel := 40 }

/-- The runtime for one program. With `opt` the lowering uses the stack-depth certificate
`safeCert` (`WordDialect.Depth`): the analysis result if `certOk` accepts it, else the empty
certificate. Either way `certOk` holds (`certTable_ok`), which is all the correctness theorem
needs, so the analysis itself is not trusted. The table is computed once per runtime. Likewise
the upper bounds `upperTable` (the least of the checked context-insensitive bound and the checked
per-word frame bound; `upperTable_sound`) decide which overflow guards are left out. -/
def runtimeFor (s : Sample32) (b : Board := microbitV1) (opt : Bool := true) : CM0.Emit.Runtime :=
  let tbl := if opt then certTable s.prog else #[]
  let r : CM0.Emit.Runtime :=
    { dEnd := dEnd, capacity := capacity, rEnd := rEnd, rcap := rcap, memImage := s.mem,
      nregs := s.nregs, aEnd := aEnd, acap := acap, txPin := b.txPin, rxPsel := b.rxPsel,
      cert := fun k => tbl.getD k 0 }
  if opt then
    let up := upperTable s.prog r.dCap
    { r with ub := fun k => upperAt up r.dCap k }
  else r

def asmFor (s : Sample32) (b : Board := microbitV1) (opt : Bool := true) : String :=
  let r := runtimeFor s b opt
  CM0.Emit.program r (CM0.lowerProg r.layout s.prog)

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

/-- Assemble and link one assembly file; the ELF's path. -/
def buildElf (name asm : String) : IO (Except String String) := do
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
  return .ok base

/-- Build, run on the emulated micro:bit, and read its UART up to the end of the run (the `EXIT`
line and the status). The emulator is then stopped: the board itself sleeps for good. -/
def runAsm (name asm : String) : IO (Except String String) := do
  match ← buildElf name asm with
  | .error e => return .error e
  | .ok elf =>
    let child ← IO.Process.spawn
      { cmd := "qemu-system-arm",
        args := #["-machine", "microbit", "-kernel", elf, "-display", "none", "-serial", "stdio",
          "-monitor", "none"],
        stdout := .piped, stderr := .null, stdin := .null }
    let out ← readUntilExit child.stdout
    child.kill
    let _ ← child.wait
    return .ok out

def runNative (opt : Bool := true) : Runner32 := fun s => do
  match ← runAsm s.name (asmFor s microbitV1 opt) with
  | .error e => return .error e
  | .ok out => return parseTranscript s out

/-- The data stack filled exactly to capacity by straight-line code, where the upper bound removes
every overflow guard, and one word more, where the bound must keep the last guard (exit 6). -/
def checkCapacity (opt : Bool) : IO Bool := do
  let fill : Sample32 :=
    { name := "cap_fill", prog := List.replicate capacity (.word 1) ++ [.halt], mem := [] }
  let ok1 ← check32 (runNative opt) fill
  -- After a call to a word with net effect -1 (it pushes two words and drops three), the frame
  -- certificate knows the depth exactly: filling to capacity removes every guard, one more keeps
  -- the last.
  let afterCall (extra : Nat) : List (WordDialect.Instr 32) :=
    let w := 2 + (capacity + extra) + 1
    [.word 7, .call w] ++ List.replicate (capacity + extra) (.word 1) ++ [.halt] ++
      [.word 1, .word 2, .drop, .drop, .drop, .ret]
  let ok2 ← check32 (runNative opt)
    { name := "cap_fill_after_call", prog := afterCall 0, mem := [] }
  let mut ok := ok1 && ok2
  for (name, prog) in [("cap_over_word", List.replicate capacity (.word 1) ++ [.word 1, .halt]),
                       ("cap_over_dup", List.replicate capacity (.word 1) ++ [.dup, .halt]),
                       ("cap_over_after_call", afterCall 1),
                       -- recursion that grows the data stack by two words a level
                       ("ovf_recursive_push2", [.call 2, .halt, .word 1, .word 2, .call 2, .ret])] do
    let s : Sample32 := { name, prog, mem := [] }
    match ← runNative opt s with
    | .ok (.trap 6) => IO.println s!"PASS  {name}  overflow exit 6"
    | .ok got => IO.println s!"FAIL  {name}  expected overflow exit 6, got {repr got}"; ok := false
    | .error e => IO.println s!"ERROR {name}: {e}"; ok := false
  return ok

/-! ## Driver -/

/-- `--board microbit-v1|microbit-v2` anywhere in the arguments, and the rest. -/
def takeBoard : List String → Option Board × List String
  | "--board" :: "microbit-v1" :: rest => (some microbitV1, rest)
  | "--board" :: "microbit-v2" :: rest => (some microbitV2, rest)
  | "--board" :: _ :: rest => (none, "--board?" :: rest)
  | a :: rest => let (b, r) := takeBoard rest; (b, a :: r)
  | [] => (none, [])

def parseMem (rest : List String) : Option Nat :=
  match rest with
  | [] => some 16
  | [m] => m.toNat?
  | _ => none

def main (args0 : List String) : IO UInt32 := do
  -- `--no-opt` keeps every guard (the lowering without depth certificates).
  let opt := !args0.contains "--no-opt"
  let args := args0.filter (· != "--no-opt")
  match args with
  | ["emit", name] =>
    match allSamples32.find? (·.name == name) with
    | some s => IO.println (asmFor s microbitV1 opt); return 0
    | none => IO.eprintln "unknown sample"; return 1
  | "forth" :: path :: rest =>
    match parseMem rest with
    | none => IO.eprintln "usage: cm0c forth <file.fs> [memWords]"; return 2
    | some m => return (if ← check32 (runNative opt) (← forthFileSample32 path m) then 0 else 1)
  | "emit-forth" :: path :: rest =>
    match parseMem rest with
    | none => IO.eprintln "usage: cm0c emit-forth <file.fs> [memWords]"; return 2
    | some m =>
      let s ← forthFileSample32 path m
      match s.buildError with
      | some e => IO.eprintln e; return 1
      | none => IO.println (asmFor s microbitV1 opt); return 0
  | "image" :: path :: rest =>
    let (b, rest) := takeBoard rest
    match parseMem rest with
    | none => IO.eprintln "usage: cm0c image <file.fs> [memWords] [--board microbit-v1|microbit-v2]"; return 2
    | some m =>
      let board := b.getD microbitV1
      let s ← forthFileSample32 path m
      if let some e := s.buildError then IO.eprintln e; return 1
      match ← buildElf s!"{s.name}-{board.name}" (asmFor s board opt) with
      | .error e => IO.eprintln e; return 1
      | .ok elf => writeImage s elf s!"{s.name}-{board.name}"
  | "verify" :: path :: log :: rest =>
    match parseMem rest with
    | none => IO.eprintln "usage: cm0c verify <file.fs> <serial.log> [memWords]"; return 2
    | some m => verifyLog (← forthFileSample32 path m) log
  | "stats" :: path :: rest =>
    match parseMem rest with
    | none => IO.eprintln "usage: cm0c stats <file.fs> [memWords]"; return 2
    | some m =>
      let s ← forthFileSample32 path m
      if let some e := s.buildError then IO.eprintln e; return 1
      let p := s.prog
      let r := runtimeFor s
      let lo := r.cert
      let hi := r.ub
      let grows : WordDialect.Instr 32 → Bool
        | .word _ | .ptr _ | .push _ | .dup | .over | .fromr | .rfetch => true
        | _ => false
      let idx := p.zipIdx
      let uf := idx.filter fun (i, _) => 0 < i.pops
      let ufKept := uf.filter fun (i, k) => lo k < i.pops
      let ov := idx.filter fun (i, _) => grows i
      let ovKept := ov.filter fun (_, k) => !(hi k + 1 ≤ r.dCap)
      let frames := if frameOk p r.dCap (analyseFrames p r.dCap) then "accepted" else "rejected"
      IO.println s!"{s.name}: {p.length} instructions; underflow guards {uf.length} → {ufKept.length}; data-stack overflow guards {ov.length} → {ovKept.length} (frame certificate {frames})"
      return 0
  | "check" :: rest =>
    let count := match rest with | [n] => n.toNat! | _ => 200
    let ok ← checkAll32 (runNative opt) count
    let okc ← checkCapacity opt
    return (if ok && okc then 0 else 1)
  | _ => IO.eprintln "usage: cm0c check [fuzzCount] | cm0c emit <sample> | cm0c forth <file.fs> [memWords] | cm0c emit-forth <file.fs> [memWords] | cm0c image <file.fs> [memWords] [--board microbit-v1|microbit-v2] | cm0c verify <file.fs> <serial.log> [memWords] | cm0c stats <file.fs> [memWords]  (any command: --no-opt keeps every guard)"; return 2
