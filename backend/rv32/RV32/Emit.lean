import RV32.Lower

/-!
# RV32.Emit

Assembly text (RISC-V, as accepted by `clang --target=riscv32-unknown-elf -march=rv32im`) for a
lowered program, plus the small bare-metal runtime.

The program text is produced from exactly the instruction list `lowerProg` builds, one
`.L<index>:` label per model instruction, so the text and the verified model cannot diverge.
A model instruction is one RISC-V instruction, except the fixed sequences documented in
`RV32.Isa` (`movImm` as `li`, conditional branches as the opposite branch over a `j`, `call`,
`ret`). An immediate or displacement outside what the encoding accepts is printed as an
`.error` directive, so the assembler rejects the program instead of emitting something else.

The runtime (`prologue`, `epilogue`) is the only hand-written assembly. There is no operating
system: the program is linked to run from RAM at `_start` and talks to two memory-mapped devices.
It
* sets `s1 … s6` to the conventions in `RV32.Lower`, with the return stack in the `.rstack`
  section,
* implements `exitHalt` as: write `depth`, the data stack, IR memory and the virtual register
  file to the UART (a 16550 at `uartBase`, polling the transmit-ready bit), one word per line as
  eight hexadecimal digits, then report success to the test device,
* implements `exitTrap t` as reporting failure code `code t` to the test device and `exitOvf`
  (stack overflow) as code 6.

The devices are those of the QEMU `virt` board, which `rv32c` runs the program on: the UART at
`0x10000000` and the SiFive test device at `0x100000` (writing `0x5555` stops the machine with
status 0, `(k << 16) | 0x3333` stops it with status `k`). On a microcontroller board these two
addresses (`Runtime.uartBase`, `Runtime.exitBase`) are the board's UART and whatever signals the
end of a run; the lowered code itself uses no device.
-/

namespace WordDialect
namespace RV32
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
  | .a0 => "a0" | .a1 => "a1" | .a2 => "a2" | .a3 => "a3" | .a4 => "a4" | .a5 => "a5"
  | .a6 => "a6" | .a7 => "a7" | .s7 => "s7" | .s8 => "s8" | .s9 => "s9" | .s10 => "s10"

def aluName : Alu → String
  | .add => "add" | .sub => "sub" | .mul => "mul" | .and => "and" | .or => "or"
  | .xor => "xor" | .sll => "sll" | .srl => "srl" | .sra => "sra"

def shiftName : Shift → String
  | .sll => "slli" | .srl => "srli" | .sra => "srai"

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
  | .load d b disp => ldst "lw" d b disp
  | .store b disp s => ldst "sw" s b disp
  | .add d s => bin "add" d s
  | .sub d s => bin "sub" d s
  | .mul d s => bin "mul" d s
  | .and d s => bin "and" d s
  | .or d s => bin "or" d s
  | .xor d s => bin "xor" d s
  | .addImm d v =>
    if imm12 v then s!"addi {regName d}, {regName d}, {v}" else err s!"immediate {v} out of range"
  | .shlImm d k => if k < 32 then s!"slli {regName d}, {regName d}, {k}" else err s!"shift {k}"
  | .sltiu d s k =>
    if k < 2048 then s!"sltiu {regName d}, {regName s}, {k}" else err s!"immediate {k} out of range"
  | .not d => s!"not {regName d}, {regName d}"
  | .neg d => s!"neg {regName d}, {regName d}"
  | .sll d s => bin "sll" d s
  | .srl d s => bin "srl" d s
  | .divu d a b => s!"divu {regName d}, {regName a}, {regName b}"
  | .div d a b => s!"div {regName d}, {regName a}, {regName b}"
  | .alu op d a b => s!"{aluName op} {regName d}, {regName a}, {regName b}"
  | .shiftImm sh d a n =>
    if n < 32 then s!"{shiftName sh} {regName d}, {regName a}, {n}" else err s!"shift {n}"
  | .bcc c a b t => farBranch k c (regName a) (regName b) t
  | .beqz a t => s!"bnez {regName a}, .Ls{k}\n\tj {lbl t}\n.Ls{k}:"
  | .bnez a t => s!"beqz {regName a}, .Ls{k}\n\tj {lbl t}\n.Ls{k}:"
  | .jmp t => s!"j {lbl t}"
  | .call t => s!"lla ra, {lbl (k + 1)}\n\taddi s5, s5, -4\n\tsw ra, 0(s5)\n\tj {lbl t}"
  | .ret => "lw ra, 0(s5)\n\taddi s5, s5, 4\n\tjr ra"
  | .exitHalt => "j .Lhalt"
  | .exitTrap t => s!"j .Ltrap{trapCode t}"
  | .exitOvf => "j .Ltrap6"

def body (code : List (Instr Nat)) : String :=
  String.intercalate "\n" (code.zipIdx.map fun (i, k) => s!"{lbl k}:\n\t{instr k i}") ++ "\n"

/-- Data-stack placement (`capacity` words ending at `dEnd`), return-stack placement (`rcap`
entries ending at `rEnd`), IR memory image, register-file size, auxiliary-stack placement
(`acap` words ending at `aEnd`), and the two device addresses. The three stacks are sections the
linker places at fixed addresses (`rv32c` uses a linker script). -/
structure Runtime where
  dEnd : Nat
  capacity : Nat
  rEnd : Nat
  rcap : Nat
  memImage : List Nat
  nregs : Nat
  aEnd : Nat
  acap : Nat
  uartBase : Nat := 0x10000000
  exitBase : Nat := 0x100000

def Runtime.dBase (r : Runtime) : Nat := r.dEnd - 4 * r.capacity

def Runtime.rBase (r : Runtime) : Nat := r.rEnd - 4 * r.rcap

def Runtime.aBase (r : Runtime) : Nat := r.aEnd - 4 * r.acap

/-- The lowering's view of the runtime: the constants the guards and bounds checks use. -/
def Runtime.layout (r : Runtime) : Layout :=
  { dEnd := BitVec.ofNat 32 r.dEnd, memSize := r.memImage.length,
    dLim := BitVec.ofNat 32 (r.dBase + 4), rGap := BitVec.ofNat 32 (4 * r.rcap - 8),
    aEnd := BitVec.ofNat 32 r.aEnd, aLim := BitVec.ofNat 32 (r.aBase + 4) }

/-- The runtime prologue. Its model is `RV32.Emit.prologueCode` (`RV32/Init.lean`), where each
`lla` is the `movImm` of the address the linker resolves the symbol to; keep the two in step. -/
def prologue (r : Runtime) : String :=
  "\t.option norelax\n\t.section .text.start, \"ax\", @progbits\n\t.globl _start\n\t.p2align 2\n_start:\n" ++
  s!"\t{li "s4" r.rEnd}\n\tmv s5, s4\n\tlla s3, irmem\n\tlla s2, regfile\n" ++
  s!"\t{li "s1" r.dEnd}\n\t{li "s6" r.aEnd}\n"

/-- Output and exit routines, entered only from `exitHalt`, `exitTrap` and `exitOvf`, so they
may use any register. `putw` writes `a0` as eight hexadecimal digits and a newline to the UART;
`putws` writes the `a2` words at address `a1`. -/
def devices (r : Runtime) : String :=
  "putc:\n" ++
  s!"\t{li "t5" r.uartBase}\n" ++
  "1:\tlbu t6, 5(t5)\n\tandi t6, t6, 0x20\n\tbeqz t6, 1b\n\tsb a5, 0(t5)\n\tret\n" ++
  "putw:\n\tmv s7, ra\n\tli a3, 28\n" ++
  "2:\tsrl a4, a0, a3\n\tandi a4, a4, 15\n\tli a5, 10\n\tblt a4, a5, 3f\n" ++
  "\taddi a5, a4, 87\n\tj 4f\n3:\taddi a5, a4, 48\n4:\tjal putc\n" ++
  "\taddi a3, a3, -4\n\tbgez a3, 2b\n\tli a5, 10\n\tjal putc\n\tmv ra, s7\n\tret\n" ++
  "putws:\n\tmv s8, ra\n" ++
  "5:\tbeqz a2, 6f\n\tlw a0, 0(a1)\n\tjal putw\n\taddi a1, a1, 4\n\taddi a2, a2, -1\n\tj 5b\n" ++
  "6:\tmv ra, s8\n\tret\n"

def epilogue (r : Runtime) : String :=
  let m := r.memImage.length
  ".Lhalt:\n" ++
  s!"\t{li "a0" r.dEnd}\n\tsub a0, a0, s1\n\tsrli a0, a0, 2\n\tmv s9, a0\n\tjal putw\n" ++
  "\tmv a1, s1\n\tmv a2, s9\n\tjal putws\n" ++
  s!"\tlla a1, irmem\n\t{li "a2" m}\n\tjal putws\n" ++
  s!"\tlla a1, regfile\n\t{li "a2" r.nregs}\n\tjal putws\n" ++
  s!"\t{li "a0" 0x5555}\n\tj .Lexit\n" ++
  String.join ((List.range 6).map fun k =>
    s!".Ltrap{k + 1}:\n\t{li "a0" ((k + 1) * 65536 + 0x3333)}\n\tj .Lexit\n") ++
  s!".Lexit:\n\t{li "t0" r.exitBase}\n\tsw a0, 0(t0)\n7:\tj 7b\n" ++
  devices r ++
  "\t.data\n\t.balign 4\nirmem:\n" ++
  String.join (r.memImage.map fun v => s!"\t.word {v % 2 ^ 32}\n") ++
  "regfile:\n" ++ s!"\t.zero {4 * (r.nregs + 1)}\n" ++
  "\t.section .dstack, \"aw\", @nobits\n\t.balign 4\n" ++
  s!"\t.skip {4 * r.capacity}\n" ++
  "\t.section .rstack, \"aw\", @nobits\n\t.balign 4\n" ++
  s!"\t.skip {4 * r.rcap}\n" ++
  "\t.section .astack, \"aw\", @nobits\n\t.balign 4\n" ++
  s!"\t.skip {4 * r.acap}\n"

/-- Full assembly text for a lowered program. -/
def program (r : Runtime) (code : List (Instr Nat)) : String :=
  prologue r ++ body code ++ epilogue r

end Emit
end RV32
end WordDialect
