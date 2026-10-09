import A64.Lower

/-!
# A64.Emit

GNU assembler text (AArch64, as accepted by `clang --target=aarch64-linux-gnu`) for a lowered
program, plus the small runtime.

The program text is produced from exactly the instruction list `lowerProg` builds, one
`.L<index>:` label per model instruction, so the text and the verified model cannot diverge.
A model instruction is one AArch64 instruction, except the fixed sequences documented in
`A64.Isa` (`movImm`, `call`, `ret`). An immediate or displacement outside what the AArch64
encoding accepts is printed as an `.error` directive, so the assembler rejects the program
instead of emitting something else.

The runtime (`prologue`, `epilogue`) is the only hand-written assembly. It
* sets `x19 … x24` to the conventions in `A64.Lower`, with the return stack in the `.rstack`
  section,
* implements `exitHalt` as: write `depth`, the data stack, IR memory and the virtual register
  file to stdout (raw little-endian 64-bit words), then `exit(0)`,
* implements `exitTrap t` as `exit(code t)` and `exitOvf` (stack overflow) as `exit(6)`.
-/

namespace WordDialect
namespace A64
namespace Emit

open Reg

def trapCode : Trap → Nat
  | .stackUnderflow => 1
  | .badAddress => 2
  | .divideByZero => 3
  | .badPc => 4
  | .returnUnderflow => 5

def regName : Reg → String
  | .x9 => "x9" | .x10 => "x10" | .x11 => "x11" | .x12 => "x12" | .x19 => "x19"
  | .x20 => "x20" | .x21 => "x21" | .x22 => "x22" | .x23 => "x23" | .x24 => "x24"
  | .x30 => "x30"

/-- The AArch64 condition with the meaning of `c` after `cmp`. -/
def ccName : Cc → String
  | .e => "eq" | .ne => "ne" | .b => "lo" | .be => "ls" | .a => "hi" | .ae => "hs"
  | .l => "lt" | .le => "le" | .g => "gt" | .ge => "ge"

def hex (n : Nat) : String := "0x" ++ String.ofList (Nat.toDigits 16 n)

def lbl (t : Nat) : String := s!".L{t}"

def err (msg : String) : String := s!".error \"{msg}\""

/-- `movz` and three `movk`: the four 16-bit pieces of `v`. -/
def movImm (d : Reg) (v : W) : String :=
  let n := v.toNat
  let piece (k : Nat) : Nat := n / 2 ^ (16 * k) % 2 ^ 16
  s!"movz {regName d}, #{hex (piece 0)}\n\tmovk {regName d}, #{hex (piece 1)}, lsl #16\n" ++
  s!"\tmovk {regName d}, #{hex (piece 2)}, lsl #32\n\tmovk {regName d}, #{hex (piece 3)}, lsl #48"

/-- A load or store with a displacement: the scaled form for `0 ≤ disp ≤ 32760` and a multiple
of 8, the unscaled form for `-256 ≤ disp < 256`. -/
def ldst (op : String) (r b : Reg) (disp : Int) : String :=
  if 0 ≤ disp ∧ disp ≤ 32760 ∧ disp % 8 = 0 then s!"{op} {regName r}, [{regName b}, #{disp}]"
  else if -256 ≤ disp ∧ disp < 256 then s!"{op}ur {regName r}, [{regName b}, #{disp}]"
  else err s!"displacement {disp} out of range"

def addImm (d : Reg) (v : Int) : String :=
  if 0 ≤ v ∧ v < 4096 then s!"add {regName d}, {regName d}, #{v}"
  else if -4096 < v ∧ v < 0 then s!"sub {regName d}, {regName d}, #{-v}"
  else err s!"immediate {v} out of range"

def cmpImm (a : Reg) (v : Int) : String :=
  if 0 ≤ v ∧ v < 4096 then s!"cmp {regName a}, #{v}"
  else if -4096 < v ∧ v < 0 then s!"cmn {regName a}, #{-v}"
  else err s!"immediate {v} out of range"

def bin (op : String) (d s : Reg) : String := s!"{op} {regName d}, {regName d}, {regName s}"

/-- The text of model instruction `k`. -/
def instr (k : Nat) : Instr Nat → String
  | .movImm d v => movImm d v
  | .movRR d s => s!"mov {regName d}, {regName s}"
  | .load d b disp => ldst "ldr" d b disp
  | .store b disp s => ldst "str" s b disp
  | .loadIdx d b i => s!"ldr {regName d}, [{regName b}, {regName i}, lsl #3]"
  | .storeIdx b i s => s!"str {regName s}, [{regName b}, {regName i}, lsl #3]"
  | .add d s => bin "add" d s
  | .sub d s => bin "sub" d s
  | .mul d s => bin "mul" d s
  | .and d s => bin "and" d s
  | .or d s => bin "orr" d s
  | .xor d s => bin "eor" d s
  | .addImm d v => addImm d v
  | .not d => s!"mvn {regName d}, {regName d}"
  | .neg d => s!"neg {regName d}, {regName d}"
  | .cmp a b => s!"cmp {regName a}, {regName b}"
  | .cmpImm a v => cmpImm a v
  | .test a b => s!"tst {regName a}, {regName b}"
  | .shlCl d => s!"lsl {regName d}, {regName d}, x10"
  | .shrCl d => s!"lsr {regName d}, {regName d}, x10"
  | .rorCl d => s!"ror {regName d}, {regName d}, x10"
  | .cmov c d s => s!"csel {regName d}, {regName s}, {regName d}, {ccName c}"
  | .udiv d a b => s!"udiv {regName d}, {regName a}, {regName b}"
  | .sdiv d a b => s!"sdiv {regName d}, {regName a}, {regName b}"
  | .jmp t => s!"b {lbl t}"
  | .jcc c t => s!"b.{ccName c} {lbl t}"
  | .call t => s!"adr x30, {lbl (k + 1)}\n\tstr x30, [x23, #-8]!\n\tb {lbl t}"
  | .ret => "ldr x30, [x23], #8\n\tbr x30"
  | .exitHalt => "b .Lhalt"
  | .exitTrap t => s!"b .Ltrap{trapCode t}"
  | .exitOvf => "b .Ltrap6"

def body (code : List (Instr Nat)) : String :=
  String.intercalate "\n" (code.zipIdx.map fun (i, k) => s!"{lbl k}:\n\t{instr k i}") ++ "\n"

/-- Data-stack placement (`capacity` words ending at `dEnd`), return-stack placement (`rcap`
entries ending at `rEnd`), IR memory image, register-file size, and auxiliary-stack placement
(`acap` words ending at `aEnd`). The three stacks are sections the linker places at fixed
addresses (`a64c` passes `--section-start`). -/
structure Runtime where
  dEnd : Nat
  capacity : Nat
  rEnd : Nat
  rcap : Nat
  memImage : List Nat
  nregs : Nat
  aEnd : Nat
  acap : Nat

def Runtime.dBase (r : Runtime) : Nat := r.dEnd - 8 * r.capacity

def Runtime.rBase (r : Runtime) : Nat := r.rEnd - 8 * r.rcap

def Runtime.aBase (r : Runtime) : Nat := r.aEnd - 8 * r.acap

/-- The lowering's view of the runtime: the constants the guards and bounds checks use. -/
def Runtime.layout (r : Runtime) : Layout :=
  { dEnd := BitVec.ofNat 64 r.dEnd, memSize := r.memImage.length,
    dLim := BitVec.ofNat 64 (r.dBase + 8), rGap := BitVec.ofNat 64 (8 * r.rcap - 16),
    aEnd := BitVec.ofNat 64 r.aEnd, aLim := BitVec.ofNat 64 (r.aBase + 8) }

def adrOf (d : String) (sym : String) : String :=
  s!"\tadrp {d}, {sym}\n\tadd {d}, {d}, :lo12:{sym}\n"

/-- The runtime prologue. Its model is `A64.Emit.prologueCode` (`A64/Init.lean`), where each
`adrp`/`add` pair is the `movImm` of the address the linker resolves the symbol to; keep the
two in step. -/
def prologue (r : Runtime) : String :=
  "\t.text\n\t.globl _start\n\t.p2align 2\n_start:\n" ++
  s!"\t{movImm .x22 (BitVec.ofNat 64 r.rEnd)}\n\tmov x23, x22\n" ++
  adrOf "x21" "irmem" ++ adrOf "x20" "regfile" ++
  s!"\t{movImm .x19 (BitVec.ofNat 64 r.dEnd)}\n\t{movImm .x24 (BitVec.ofNat 64 r.aEnd)}\n"

/-- `write(1, x1, x2)`. -/
def sysWrite : String := "\tmov x0, #1\n\tmov x8, #64\n\tsvc #0\n"

def epilogue (r : Runtime) : String :=
  let m := r.memImage.length
  ".Lhalt:\n" ++
  s!"\t{movImm .x9 (BitVec.ofNat 64 r.dEnd)}\n\tsub x9, x9, x19\n\tlsr x9, x9, #3\n" ++
  adrOf "x1" "hdr" ++ "\tstr x9, [x1]\n\tmov x2, #8\n" ++ sysWrite ++
  "\tmov x1, x19\n\tlsl x2, x9, #3\n" ++ sysWrite ++
  adrOf "x1" "irmem" ++ s!"\t{movImm .x9 (BitVec.ofNat 64 (8 * m))}\n\tmov x2, x9\n" ++ sysWrite ++
  adrOf "x1" "regfile" ++ s!"\t{movImm .x9 (BitVec.ofNat 64 (8 * r.nregs))}\n\tmov x2, x9\n" ++
    sysWrite ++
  "\tmov x0, #0\n\tb .Lexit\n" ++
  String.join ((List.range 6).map fun k => s!".Ltrap{k + 1}:\n\tmov x0, #{k + 1}\n\tb .Lexit\n") ++
  ".Lexit:\n\tmov x8, #93\n\tsvc #0\n" ++
  "\t.data\n\t.balign 8\nirmem:\n" ++
  String.join (r.memImage.map fun v => s!"\t.quad {v}\n") ++
  "\t.section .dstack, \"aw\", @nobits\n\t.balign 8\n" ++
  s!"\t.skip {8 * r.capacity}\n" ++
  "\t.section .rstack, \"aw\", @nobits\n\t.balign 8\n" ++
  s!"\t.skip {8 * r.rcap}\n" ++
  "\t.section .astack, \"aw\", @nobits\n\t.balign 8\n" ++
  s!"\t.skip {8 * r.acap}\n" ++
  "\t.bss\n\t.balign 8\nhdr:\n\t.skip 8\nregfile:\n" ++ s!"\t.skip {8 * (r.nregs + 1)}\n"

/-- Full assembly text for a lowered program. -/
def program (r : Runtime) (code : List (Instr Nat)) : String :=
  prologue r ++ body code ++ epilogue r

end Emit
end A64
end WordDialect
