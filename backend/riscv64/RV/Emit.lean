import RV.Lower

/-!
# RV.Emit

Assembly text (RISC-V, as accepted by `clang --target=riscv64-linux-gnu -march=rv64im`) for a
lowered program, plus the small runtime.

The program text is produced from exactly the instruction list `lowerProg` builds, one
`.L<index>:` label per model instruction, so the text and the verified model cannot diverge.
A model instruction is one RISC-V instruction, except the fixed sequences documented in
`RV.Isa` (`movImm` as `li`, conditional branches as the opposite branch over a `j`, `call`,
`ret`). An immediate or displacement outside what the encoding accepts is printed as an
`.error` directive, so the assembler rejects the program instead of emitting something else.

The runtime (`prologue`, `epilogue`) is the only hand-written assembly. It
* sets `s1 … s6` to the conventions in `RV.Lower`, with the return stack in the `.rstack`
  section,
* implements `exitHalt` as: write `depth`, the data stack, IR memory and the virtual register
  file to stdout (raw little-endian 64-bit words), then `exit(0)`,
* implements `exitTrap t` as `exit(code t)` and `exitOvf` (stack overflow) as `exit(6)`.
-/

namespace WordDialect
namespace RV
namespace Emit

open Reg

def trapCode : Trap → Nat
  | .stackUnderflow => 1
  | .badAddress => 2
  | .divideByZero => 3
  | .badPc => 4
  | .returnUnderflow => 5

def regName : Reg → String
  | .t0 => "t0" | .t1 => "t1" | .t2 => "t2" | .t3 => "t3" | .s1 => "s1" | .s2 => "s2"
  | .s3 => "s3" | .s4 => "s4" | .s5 => "s5" | .s6 => "s6" | .ra => "ra"

def hex (n : Nat) : String := "0x" ++ String.ofList (Nat.toDigits 16 n)

def lbl (t : Nat) : String := s!".L{t}"

def err (msg : String) : String := s!".error \"{msg}\""

def li (d : String) (v : Nat) : String := s!"li {d}, {hex v}"

def imm12 (v : Int) : Bool := -2048 ≤ v ∧ v < 2048

def ldst (op : String) (r b : Reg) (disp : Int) : String :=
  if imm12 disp then s!"{op} {regName r}, {disp}({regName b})"
  else err s!"displacement {disp} out of range"

def bin (op : String) (d s : Reg) : String := s!"{op} {regName d}, {regName d}, {regName s}"

/-- The RISC-V branch taken when `c.eval a b` holds: mnemonic and operand order. -/
def condBranch (c : Cond) (a b : String) : String × String × String :=
  match c with
  | .eq => ("beq", a, b) | .ne => ("bne", a, b)
  | .ult => ("bltu", a, b) | .uge => ("bgeu", a, b)
  | .ugt => ("bltu", b, a) | .ule => ("bgeu", b, a)
  | .slt => ("blt", a, b) | .sge => ("bge", a, b)
  | .sgt => ("blt", b, a) | .sle => ("bge", b, a)

/-- The negation of `c`, so a far branch can skip over a `j`. -/
def condNot : Cond → Cond
  | .eq => .ne | .ne => .eq | .ult => .uge | .uge => .ult | .ugt => .ule | .ule => .ugt
  | .slt => .sge | .sge => .slt | .sgt => .sle | .sle => .sgt

/-- Branch to `t` when `c.eval a b`: the opposite branch over a `j`, so the range is `j`'s. -/
def farBranch (k : Nat) (c : Cond) (a b : String) (t : Nat) : String :=
  let (op, x, y) := condBranch (condNot c) a b
  s!"{op} {x}, {y}, .Ls{k}\n\tj {lbl t}\n.Ls{k}:"

/-- The text of model instruction `k`. -/
def instr (k : Nat) : Instr Nat → String
  | .movImm d v => li (regName d) v.toNat
  | .movRR d s => s!"mv {regName d}, {regName s}"
  | .load d b disp => ldst "ld" d b disp
  | .store b disp s => ldst "sd" s b disp
  | .add d s => bin "add" d s
  | .sub d s => bin "sub" d s
  | .mul d s => bin "mul" d s
  | .and d s => bin "and" d s
  | .or d s => bin "or" d s
  | .xor d s => bin "xor" d s
  | .addImm d v =>
    if imm12 v then s!"addi {regName d}, {regName d}, {v}" else err s!"immediate {v} out of range"
  | .shlImm d k => if k < 64 then s!"slli {regName d}, {regName d}, {k}" else err s!"shift {k}"
  | .sltiu d s k =>
    if k < 2048 then s!"sltiu {regName d}, {regName s}, {k}" else err s!"immediate {k} out of range"
  | .not d => s!"not {regName d}, {regName d}"
  | .neg d => s!"neg {regName d}, {regName d}"
  | .sll d s => bin "sll" d s
  | .srl d s => bin "srl" d s
  | .divu d a b => s!"divu {regName d}, {regName a}, {regName b}"
  | .div d a b => s!"div {regName d}, {regName a}, {regName b}"
  | .bcc c a b t => farBranch k c (regName a) (regName b) t
  | .beqz a t => s!"bnez {regName a}, .Ls{k}\n\tj {lbl t}\n.Ls{k}:"
  | .bnez a t => s!"beqz {regName a}, .Ls{k}\n\tj {lbl t}\n.Ls{k}:"
  | .jmp t => s!"j {lbl t}"
  | .call t => s!"lla ra, {lbl (k + 1)}\n\taddi s5, s5, -8\n\tsd ra, 0(s5)\n\tj {lbl t}"
  | .ret => "ld ra, 0(s5)\n\taddi s5, s5, 8\n\tjr ra"
  | .exitHalt => "j .Lhalt"
  | .exitTrap t => s!"j .Ltrap{trapCode t}"
  | .exitOvf => "j .Ltrap6"

def body (code : List (Instr Nat)) : String :=
  String.intercalate "\n" (code.zipIdx.map fun (i, k) => s!"{lbl k}:\n\t{instr k i}") ++ "\n"

/-- Data-stack placement (`capacity` words ending at `dEnd`), return-stack placement (`rcap`
entries ending at `rEnd`), IR memory image, register-file size, and auxiliary-stack placement
(`acap` words ending at `aEnd`). The three stacks are sections the linker places at fixed
addresses (`rv64c` passes `--section-start`). -/
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

/-- The runtime prologue. Its model is `RV.Emit.prologueCode` (`RV/Init.lean`), where each `lla`
is the `movImm` of the address the linker resolves the symbol to; keep the two in step. -/
def prologue (r : Runtime) : String :=
  "\t.option norelax\n\t.text\n\t.globl _start\n\t.p2align 2\n_start:\n" ++
  s!"\t{li "s4" r.rEnd}\n\tmv s5, s4\n\tlla s3, irmem\n\tlla s2, regfile\n" ++
  s!"\t{li "s1" r.dEnd}\n\t{li "s6" r.aEnd}\n"

/-- `write(1, a1, a2)`. -/
def sysWrite : String := "\tli a0, 1\n\tli a7, 64\n\tecall\n"

def epilogue (r : Runtime) : String :=
  let m := r.memImage.length
  ".Lhalt:\n" ++
  s!"\t{li "t0" r.dEnd}\n\tsub t0, t0, s1\n\tsrli t0, t0, 3\n" ++
  "\tlla a1, hdr\n\tsd t0, 0(a1)\n\tli a2, 8\n" ++ sysWrite ++
  "\tlla a1, hdr\n\tld a2, 0(a1)\n\tslli a2, a2, 3\n\tmv a1, s1\n" ++ sysWrite ++
  s!"\tlla a1, irmem\n\t{li "a2" (8 * m)}\n" ++ sysWrite ++
  s!"\tlla a1, regfile\n\t{li "a2" (8 * r.nregs)}\n" ++ sysWrite ++
  "\tli a0, 0\n\tj .Lexit\n" ++
  String.join ((List.range 6).map fun k => s!".Ltrap{k + 1}:\n\tli a0, {k + 1}\n\tj .Lexit\n") ++
  ".Lexit:\n\tli a7, 93\n\tecall\n" ++
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
end RV
end WordDialect
