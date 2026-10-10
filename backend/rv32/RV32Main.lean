import Harness
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

The programs are the shared samples and generated programs of `Harness`, narrowed to 32-bit
words (`narrow`), so the same programs run here at width 32 as on the 64-bit targets. Forth
source files are compiled directly at width 32. `check` also runs the auxiliary-stack and
overflow programs, and the hand-written data-processing programs of `RV32.DataOps`.

Usage: `rv32c check [fuzzCount]`, `rv32c emit <sample>`, `rv32c forth <file.fs> [memWords]`,
`rv32c emit-forth <file.fs> [memWords]`.
-/

open WordDialect

/-! ## Samples at width 32 -/

structure Sample32 where
  name : String
  prog : Prog 32
  mem : List Nat
  nregs : Nat := 4
  buildError : Option String := none

/-- A 64-bit word as a 32-bit one: the edge values of the generator (`Harness.edge`) near
`2^63` and `2^64` become the same edges near `2^31` and `2^32`; other values keep their low
32 bits. -/
def narrowWord (w : Word 64) : Word 32 :=
  let v := w.toNat
  if v = 2 ^ 63 - 1 then BitVec.ofNat 32 (2 ^ 31 - 1)
  else if v = 2 ^ 63 then BitVec.ofNat 32 (2 ^ 31)
  else if v = 2 ^ 63 + 1 then BitVec.ofNat 32 (2 ^ 31 + 1)
  else BitVec.ofNat 32 v

def narrowInstr : Instr 64 → Instr 32
  | .word w => .word (narrowWord w)
  | .ptr q => .ptr ⟨narrowWord q.addr⟩
  | .load => .load | .store => .store
  | .add => .add | .sub => .sub | .mul => .mul | .div => .div | .sdiv => .sdiv
  | .and => .and | .or => .or | .xor => .xor | .not => .not
  | .shl => .shl | .shr => .shr | .rotl => .rotl | .rotr => .rotr
  | .cmp c => .cmp c
  | .select => .select
  | .jmp t => .jmp t | .branch t => .branch t | .call t => .call t | .ret => .ret
  | .push r => .push r | .pop r => .pop r
  | .dup => .dup | .drop => .drop | .swap => .swap | .over => .over | .rot => .rot
  | .tor => .tor | .fromr => .fromr | .rfetch => .rfetch
  | .halt => .halt

def narrowMem (v : Nat) : Nat := (narrowWord (BitVec.ofNat 64 v)).toNat

def narrow (s : Sample) : Sample32 :=
  { name := s.name, prog := s.prog.map narrowInstr, mem := s.mem.map narrowMem, nregs := s.nregs,
    buildError := s.buildError }

def expected32 (s : Sample32) : Result :=
  match run s.prog 200000 (State.init (Memory.ofImage s.mem : Memory 32)) with
  | none => .timeout
  | some (.trapped t) => .trap (trapCode t)
  | some (.next _) => .timeout
  | some (.halted st) =>
    .halted (st.dstack.map (·.toNat))
      ((List.range s.mem.length).map fun a => (st.mem.cell (BitVec.ofNat 32 a)).toNat)
      ((List.range s.nregs).map fun r => (st.regs r).toNat)

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

/-- The UART dump: one word per line, eight hexadecimal digits. -/
def hexWords (t : String) : Option (List Nat) :=
  ((t.splitOn "\n").filter (· ≠ "")).mapM fun l =>
    if l.length = 8 then
      l.foldl (fun acc ch => acc.bind fun v =>
        if '0' ≤ ch ∧ ch ≤ '9' then some (16 * v + (ch.toNat - '0'.toNat))
        else if 'a' ≤ ch ∧ ch ≤ 'f' then some (16 * v + (ch.toNat - 'a'.toNat + 10))
        else none) (some 0)
    else none

def runNative (s : Sample32) : IO (Except String Result) := do
  match ← runAsm s.name (asmFor s) with
  | .error e => return .error e
  | .ok (out, code) =>
    if code != 0 then return .ok (.trap code.toNat)
    match hexWords out with
    | some (depth :: rest) =>
      let m := s.mem.length
      if rest.length != depth + m + s.nregs then return .error s!"malformed dump: {out}"
      return .ok (.halted (rest.take depth) ((rest.drop depth).take m) (rest.drop (depth + m)))
    | _ => return .error s!"malformed dump: {out}"

def check32 (s : Sample32) : IO Bool := do
  if let some e := s.buildError then
    IO.println s!"ERROR {s.name}: {e}"; return false
  let exp := expected32 s
  if exp == .timeout then
    IO.println s!"SKIP  {s.name} (IR did not terminate within fuel)"; return true
  match ← runNative s with
  | .error e => IO.println s!"ERROR {s.name}: {e}"; return false
  | .ok got =>
    if got == exp then IO.println s!"PASS  {s.name}  {repr exp}"; return true
    else IO.println s!"FAIL  {s.name}\n  lean:   {repr exp}\n  target: {repr got}"; return false

/-! ## Samples specific to 32-bit words -/

def samples32 : List Sample32 :=
  [ { name := "w32_wrap", mem := [], nregs := 1,
      prog := [.word 0xffffffff, .word 1, .add, .word 0x7fffffff, .word 1, .add, .word 0x10000,
               .word 0x10000, .mul, .halt] }
  , { name := "w32_sdiv_intmin", mem := [], nregs := 1,
      prog := [.word 0x80000000, .word 0xffffffff, .sdiv, .word 0xfffffff9, .word 2, .sdiv, .halt] }
  , { name := "w32_shifts", mem := [], nregs := 1,
      prog := [.word 1, .word 31, .shl, .word 1, .word 32, .shl, .word 0x80000000, .word 31, .shr,
               .word 0x80000001, .word 1, .rotl, .word 0x80000001, .word 33, .rotr, .halt] }
  , { name := "w32_compare_signed", mem := [], nregs := 1,
      prog := [.word 0x80000000, .word 0x7fffffff, .cmp .slt, .word 0x80000000, .word 0x7fffffff,
               .cmp .ult, .halt] }
  , { name := "w32_memory", mem := [7, 0xffffffff, 3], nregs := 2,
      prog := [.word 1, .load, .word 2, .load, .add, .word 0, .store, .word 3, .load, .halt] } ]

/-- Programs that grow a stack without bound: the emitted code must stop with exit 6. -/
def overflowSamples : List Sample32 :=
  [ { name := "ovf_word_loop", prog := [.word 1, .jmp 0], mem := [] },
    { name := "ovf_dup_loop", prog := [.word 1, .dup, .jmp 1], mem := [] },
    { name := "ovf_call_loop", prog := [.call 0], mem := [] },
    { name := "ovf_tor_loop", prog := [.word 1, .tor, .jmp 0], mem := [] } ]

def auxSamples : List Sample32 :=
  [ { name := "aux_basic", mem := [], nregs := 1,
      prog := [.word 7, .tor, .word 3, .rfetch, .add, .fromr, .mul, .halt] }
  , { name := "aux_across_call", mem := [], nregs := 1,
      prog := [.word 100, .tor, .word 5, .call 7, .fromr, .add, .halt,
               .tor, .rfetch, .fromr, .mul, .ret] }
  , { name := "aux_fact_rec", mem := [], nregs := 1,
      prog := [.word 5, .call 3, .halt,
               .dup, .branch 8, .drop, .word 1, .ret,
               .dup, .tor, .word 1, .sub, .call 3, .fromr, .mul, .ret] }
  , { name := "aux_fromr_empty", mem := [], nregs := 1, prog := [.word 1, .fromr, .halt] }
  , { name := "aux_rfetch_empty", mem := [], nregs := 1, prog := [.rfetch, .halt] }
  , { name := "aux_ret_not_aux", mem := [], nregs := 1, prog := [.word 1, .tor, .ret] }
  , { name := "aux_tor_underflow", mem := [], nregs := 1, prog := [.tor, .halt] } ]

def checkOverflow : IO Bool := do
  let mut ok := true
  for s in overflowSamples do
    match ← runNative s with
    | .ok (.trap 6) => IO.println s!"PASS  {s.name}  overflow exit 6"
    | .ok got => IO.println s!"FAIL  {s.name}  expected overflow exit 6, got {repr got}"; ok := false
    | .error e => IO.println s!"ERROR {s.name}: {e}"; ok := false
  return ok

/-- The shared generated programs, narrowed to 32 bits. -/
def fuzz32 (count : Nat) : IO Bool := do
  let mut ok := true
  let mut skipped := 0
  let mut halts := 0
  let mut traps : Array Nat := #[0, 0, 0, 0, 0, 0]
  for i in List.range count do
    let len ← IO.rand 4 40
    let prog ← genProg len
    let mem ← (List.range 16).mapM fun _ => randWord
    let s := narrow { name := s!"fuzz_{i}", prog, mem, nregs := 4 }
    let exp := expected32 s
    match exp with
    | .halted .. => halts := halts + 1
    | .trap c => traps := traps.set! c (traps[c]! + 1)
    | .timeout => skipped := skipped + 1
    if exp == .timeout then continue
    match ← runNative s with
    | .error e => IO.println s!"ERROR fuzz_{i}: {e}"; ok := false
    | .ok got =>
      if got != exp then
        IO.println s!"FAIL  fuzz_{i}\n  lean:   {repr exp}\n  target: {repr got}"; ok := false
  IO.println s!"fuzz: {count} programs, {skipped} skipped; halted {halts}; traps by code (1 underflow, 2 badaddr, 3 div0, 4 badpc, 5 ret) {traps.toList.drop 1}; {if ok then "all agree" else "MISMATCH"}"
  return ok

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

/-- A Forth source file compiled at width 32, with `memWords` zero words of IR memory. -/
def forthFileSample (path : String) (memWords : Nat) : IO Sample32 := do
  let src ← IO.FS.readFile path
  let name := (System.FilePath.mk path).fileStem.getD "forth"
  let mem := List.replicate memWords 0
  match Forth.parse src with
  | .ok P => return { name, prog := P.compile, mem := mem ++ List.replicate (P.vars - mem.length) 0,
                      nregs := forthRegs }
  | .error e => return { name, prog := [], mem, buildError := some s!"Forth parse error: {e}" }

def parseMem (rest : List String) : Option Nat :=
  match rest with
  | [] => some 16
  | [m] => m.toNat?
  | _ => none

def allSamples32 : List Sample32 := allSamples.map narrow ++ samples32 ++ auxSamples

def main (args : List String) : IO UInt32 := do
  match args with
  | ["emit", name] =>
    match allSamples32.find? (·.name == name) with
    | some s => IO.println (asmFor s); return 0
    | none => IO.eprintln "unknown sample"; return 1
  | "forth" :: path :: rest =>
    match parseMem rest with
    | none => IO.eprintln "usage: rv32c forth <file.fs> [memWords]"; return 2
    | some m => return (if ← check32 (← forthFileSample path m) then 0 else 1)
  | "emit-forth" :: path :: rest =>
    match parseMem rest with
    | none => IO.eprintln "usage: rv32c emit-forth <file.fs> [memWords]"; return 2
    | some m =>
      let s ← forthFileSample path m
      match s.buildError with
      | some e => IO.eprintln e; return 1
      | none => IO.println (asmFor s); return 0
  | "check" :: rest =>
    let count := match rest with | [n] => n.toNat! | _ => 200
    IO.setRandSeed 20260610
    let mut ok := true
    for s in allSamples32 do
      if !(← check32 s) then ok := false
    let fz ← fuzz32 count
    let ovf ← checkOverflow
    let isa ← checkIsa 100
    return (if ok && fz && ovf && isa then 0 else 1)
  | _ => IO.eprintln "usage: rv32c check [fuzzCount] | rv32c emit <sample> | rv32c forth <file.fs> [memWords] | rv32c emit-forth <file.fs> [memWords]"; return 2
