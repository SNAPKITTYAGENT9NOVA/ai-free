import WordDialect

/-!
# RV32.Isa

A Lean model of the RISC-V (RV32IM) instruction subset the microcontroller profile emits: the
same instructions as `RV.Isa` (RV64IM), on 32-bit registers and 32-bit words.

Scope and trust boundary:
* 32-bit integer registers only; the registers the lowering uses.
* Memory is the shared `Memory 32` model, indexed by byte address. The lowering only performs
  4-byte-aligned accesses (`lw`/`sw`); no unaligned or sub-word access is modelled.
* RISC-V has no condition flags. A conditional branch compares two registers; `bcc c a b t`
  branches when `c.eval a b` holds, for the IR's own comparison predicates `Cond` (`Emit` prints
  `beq bne bltu bgeu blt bge`, swapping the operands for `ule ugt sle sgt`). `beqz`/`bnez`
  compare with zero.
* `divu` and `div` never fault: division by zero gives all ones, and `div` of the most negative
  number by `-1` wraps (RISC-V unprivileged spec, M extension). They are modelled exactly so; the
  lowering guards the zero divisor itself.
* `sll`/`srl` use the shift amount modulo 32, as the hardware does.
* Faults (invalid memory access, jumping outside the code) are a distinct outcome, never a silent
  state.
* Some model instructions are fixed instruction sequences in the emitted text (`RV32.Emit`); the
  model gives each the combined effect of its sequence:
  - `movImm d v` is the assembler's `li d, v` expansion, which writes only `d`;
  - a conditional branch is the opposite branch over a `j` (so its range is that of `j`);
  - `call t` is `lla ra, <next>; addi s5, s5, -4; sw ra, 0(s5); j t`: it pushes the return
    address on the return stack (`s5`, growing downward) and writes `ra`;
  - `ret` is `lw ra, 0(s5); addi s5, s5, 4; jr ra`: it pops the return address into `ra` and jumps.
  Code addresses are instruction indices, as for jumps (the code-address abstraction of every
  backend model here).
* `exitHalt` / `exitTrap t` stand for the runtime stubs that dump state and stop the machine;
  they are terminal here. `exitOvf` is the stub for a stack-overflow guard (status 6); it has no
  IR counterpart, since IR stacks are unbounded. There is no operating system: the stubs talk to
  memory-mapped devices (`RV32.Emit`).

That the model matches the hardware is the stated assumption of this backend; `rv32c` tests it by
running the emitted code on the QEMU `virt` board (`qemu-system-riscv32`, no firmware).
-/

namespace WordDialect
namespace RV32

abbrev W := BitVec 32

/-- Registers. Roles (see `RV32.Lower`): `t0 t1 t2 t3` scratch, `s1` data-stack pointer, `s2`
register file, `s3` IR memory, `s4` empty return stack, `s5` return-stack pointer, `s6`
auxiliary-stack pointer, `ra` return address (written by `call` and `ret`). The lowering uses
no others; `a0 … a7` and `s7 … s10` are for hand-written programs (`RV32.DataOps`). -/
inductive Reg where
  | t0 | t1 | t2 | t3 | s5 | s6 | s4 | s3 | s2 | s1 | ra
  | a0 | a1 | a2 | a3 | a4 | a5 | a6 | a7 | s7 | s8 | s9 | s10
  deriving DecidableEq, Repr

/-- The register-register operations of the three-register form `op d, a, b`. The shifts use
`b` modulo 32, as the hardware does. -/
inductive Alu where
  | add | sub | mul | and | or | xor | sll | srl | sra
  deriving DecidableEq, Repr

def Alu.eval : Alu → W → W → W
  | .add, a, b => a + b
  | .sub, a, b => a - b
  | .mul, a, b => a * b
  | .and, a, b => a &&& b
  | .or, a, b => a ||| b
  | .xor, a, b => a ^^^ b
  | .sll, a, b => a <<< (b.toNat % 32)
  | .srl, a, b => a >>> (b.toNat % 32)
  | .sra, a, b => a.sshiftRight (b.toNat % 32)

/-- Shifts by a constant: `slli`, `srli`, `srai`. -/
inductive Shift where
  | sll | srl | sra
  deriving DecidableEq, Repr

def Shift.eval : Shift → W → Nat → W
  | .sll, a, n => a <<< n
  | .srl, a, n => a >>> n
  | .sra, a, n => a.sshiftRight n

/-- Instructions, generic in the type of jump targets (`Nat` code indices for the model,
`String` labels for assembly text). Two-operand forms `op d s` mean `d := d op s`. -/
inductive Instr (L : Type) where
  | movImm (d : Reg) (v : W)
  | movRR (d s : Reg)
  /-- `lw d, disp(b)`. -/
  | load (d b : Reg) (disp : Int)
  /-- `sw s, disp(b)`. -/
  | store (b : Reg) (disp : Int) (s : Reg)
  | add (d s : Reg)
  | sub (d s : Reg)
  | mul (d s : Reg)
  | and (d s : Reg)
  | or (d s : Reg)
  | xor (d s : Reg)
  | addImm (d : Reg) (v : Int)
  /-- `slli d, d, k`. -/
  | shlImm (d : Reg) (k : Nat)
  | not (d : Reg)
  | neg (d : Reg)
  /-- `sltiu d, s, k`: `1` if `s <u k`, else `0`. -/
  | sltiu (d s : Reg) (k : Nat)
  /-- `sll d, d, s` (shift amount modulo 32). -/
  | sll (d s : Reg)
  /-- `srl d, d, s`. -/
  | srl (d s : Reg)
  | divu (d a b : Reg)
  | div (d a b : Reg)
  /-- Three-register form `op d, a, b` (`d := a op b`), for hand-written programs. -/
  | alu (op : Alu) (d a b : Reg)
  /-- `slli`/`srli`/`srai d, a, n` (`d := a shifted by n`); `Emit` requires `n < 32`. -/
  | shiftImm (k : Shift) (d a : Reg) (n : Nat)
  | bcc (c : Cond) (a b : Reg) (t : L)
  | beqz (a : Reg) (t : L)
  | bnez (a : Reg) (t : L)
  | jmp (t : L)
  | call (t : L)
  | ret
  | exitHalt
  | exitTrap (t : Trap)
  | exitOvf

structure M where
  regs  : Reg → W
  mem   : Memory 32
  pc    : Nat

inductive Out where
  | next    (m : M)
  | halted  (m : M)
  | trapped (t : Trap)
  | overflow
  | fault

def M.setReg (m : M) (r : Reg) (v : W) : M :=
  { m with regs := fun x => if x = r then v else m.regs x }

def M.adv (m : M) : M := { m with pc := m.pc + 1 }

/-- Write a register and advance. -/
def M.mov (m : M) (r : Reg) (v : W) : M := (m.setReg r v).adv

/-- Write a register and advance (the result of an arithmetic instruction). -/
def M.arith (m : M) (r : Reg) (v : W) : M := { (m.setReg r v) with pc := m.pc + 1 }

def M.ea (m : M) (b : Reg) (disp : Int) : W := m.regs b + BitVec.ofInt 32 disp

/-- `divu`: all ones on a zero divisor. -/
def divu (a b : W) : W := if b = 0#32 then BitVec.allOnes 32 else a.udiv b

/-- `div`: all ones (`-1`) on a zero divisor; otherwise `BitVec.sdiv` (which wraps on overflow). -/
def divs (a b : W) : W := if b = 0#32 then BitVec.allOnes 32 else a.sdiv b

/-- Semantics of one instruction. -/
def exec (i : Instr Nat) (m : M) : Out :=
  match i with
  | .movImm d v => .next (m.mov d v)
  | .movRR d s => .next (m.mov d (m.regs s))
  | .load d b disp =>
      match m.mem.read? (m.ea b disp) with
      | some v => .next (m.mov d v)
      | none => .fault
  | .store b disp s =>
      match m.mem.write? (m.ea b disp) (m.regs s) with
      | some mem' => .next { m.adv with mem := mem' }
      | none => .fault
  | .add d s => .next (m.arith d (m.regs d + m.regs s))
  | .sub d s => .next (m.arith d (m.regs d - m.regs s))
  | .mul d s => .next (m.arith d (m.regs d * m.regs s))
  | .and d s => .next (m.arith d (m.regs d &&& m.regs s))
  | .or d s => .next (m.arith d (m.regs d ||| m.regs s))
  | .xor d s => .next (m.arith d (m.regs d ^^^ m.regs s))
  | .addImm d v => .next (m.arith d (m.regs d + BitVec.ofInt 32 v))
  | .shlImm d k => .next (m.arith d (m.regs d <<< (k % 32)))
  | .not d => .next (m.arith d (~~~m.regs d))
  | .neg d => .next (m.arith d (0#32 - m.regs d))
  | .sltiu d s k => .next (m.arith d (Word.ofBool ((m.regs s).ult (BitVec.ofNat 32 k))))
  | .sll d s => .next (m.arith d (m.regs d <<< ((m.regs s).toNat % 32)))
  | .srl d s => .next (m.arith d (m.regs d >>> ((m.regs s).toNat % 32)))
  | .divu d a b => .next (m.arith d (divu (m.regs a) (m.regs b)))
  | .div d a b => .next (m.arith d (divs (m.regs a) (m.regs b)))
  | .alu op d a b => .next (m.arith d (op.eval (m.regs a) (m.regs b)))
  | .shiftImm k d a n => .next (m.arith d (k.eval (m.regs a) n))
  | .bcc c a b t => .next (if c.eval (m.regs a) (m.regs b) then { m with pc := t } else m.adv)
  | .beqz a t => .next (if m.regs a = 0#32 then { m with pc := t } else m.adv)
  | .bnez a t => .next (if m.regs a = 0#32 then m.adv else { m with pc := t })
  | .jmp t => .next { m with pc := t }
  | .call t =>
      let sp := m.regs .s5 - 4#32
      let ra := BitVec.ofNat 32 (m.pc + 1)
      match m.mem.write? sp ra with
      | some mem' => .next { ((m.setReg .ra ra).setReg .s5 sp) with mem := mem', pc := t }
      | none => .fault
  | .ret =>
      match m.mem.read? (m.regs .s5) with
      | some v => .next { ((m.setReg .ra v).setReg .s5 (m.regs .s5 + 4#32)) with pc := v.toNat }
      | none => .fault
  | .exitHalt => .halted m
  | .exitTrap t => .trapped t
  | .exitOvf => .overflow

/-- One machine step over a code array; leaving the code is a fault. -/
def step (code : List (Instr Nat)) (m : M) : Out :=
  match code[m.pc]? with
  | none => .fault
  | some i => exec i m

/-- Fuel-bounded run. `none`: out of fuel. -/
def run (code : List (Instr Nat)) : Nat → M → Option Out
  | 0, _ => none
  | fuel + 1, m =>
    match step code m with
    | .next m' => run code fuel m'
    | o => some o

end RV32
end WordDialect
