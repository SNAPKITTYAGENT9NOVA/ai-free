import WordDialect

/-!
# RV.Isa

A Lean model of the RISC-V (RV64IM) instruction subset the backend emits.

Scope and trust boundary:
* 64-bit integer registers only; the registers the lowering uses.
* Memory is the shared `Memory 64` model, indexed by byte address. The lowering only performs
  8-byte-aligned accesses (`ld`/`sd`); no unaligned or sub-word access is modelled.
* RISC-V has no condition flags. A conditional branch compares two registers; `bcc c a b t`
  branches when `c.eval a b` holds, for the IR's own comparison predicates `Cond` (`Emit` prints
  `beq bne bltu bgeu blt bge`, swapping the operands for `ule ugt sle sgt`). `beqz`/`bnez`
  compare with zero.
* `divu` and `div` never fault: division by zero gives all ones, and `div` of the most negative
  number by `-1` wraps (RISC-V unprivileged spec, M extension). They are modelled exactly so; the
  lowering guards the zero divisor itself.
* `sll`/`srl` use the shift amount modulo 64, as the hardware does.
* Faults (invalid memory access, jumping outside the code) are a distinct outcome, never a silent
  state.
* Some model instructions are fixed instruction sequences in the emitted text (`RV.Emit`); the
  model gives each the combined effect of its sequence:
  - `movImm d v` is the assembler's `li d, v` expansion, which writes only `d`;
  - a conditional branch is the opposite branch over a `j` (so its range is that of `j`);
  - `call t` is `lla ra, <next>; addi s5, s5, -8; sd ra, 0(s5); j t`: it pushes the return
    address on the return stack (`s5`, growing downward) and writes `ra`;
  - `ret` is `ld ra, 0(s5); addi s5, s5, 8; jr ra`: it pops the return address into `ra` and jumps.
  Code addresses are instruction indices, as for jumps (the code-address abstraction of every
  backend model here).
* `exitHalt` / `exitTrap t` stand for the runtime stubs that dump state and `exit`; they are
  terminal here. `exitOvf` is the stub for a stack-overflow guard (`exit(6)`); it has no IR
  counterpart, since IR stacks are unbounded.

That the model matches the hardware is the stated assumption of this backend; `rv64c` tests it by
running the emitted code under `qemu-riscv64`.
-/

namespace WordDialect
namespace RV

abbrev W := BitVec 64

/-- Registers. Roles (see `RV.Lower`): `t0 t1 t2 t3` scratch, `s1` data-stack pointer, `s2`
register file, `s3` IR memory, `s4` empty return stack, `s5` return-stack pointer, `s6`
auxiliary-stack pointer, `ra` return address (written by `call` and `ret`). -/
inductive Reg where
  | t0 | t1 | t2 | t3 | s5 | s6 | s4 | s3 | s2 | s1 | ra
  deriving DecidableEq, Repr

/-- Instructions, generic in the type of jump targets (`Nat` code indices for the model,
`String` labels for assembly text). Two-operand forms `op d s` mean `d := d op s`. -/
inductive Instr (L : Type) where
  | movImm (d : Reg) (v : W)
  | movRR (d s : Reg)
  /-- `ld d, disp(b)`. -/
  | load (d b : Reg) (disp : Int)
  /-- `sd s, disp(b)`. -/
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
  /-- `sll d, d, s` (shift amount modulo 64). -/
  | sll (d s : Reg)
  /-- `srl d, d, s`. -/
  | srl (d s : Reg)
  | divu (d a b : Reg)
  | div (d a b : Reg)
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
  mem   : Memory 64
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

def M.ea (m : M) (b : Reg) (disp : Int) : W := m.regs b + BitVec.ofInt 64 disp

/-- `divu`: all ones on a zero divisor. -/
def divu (a b : W) : W := if b = 0#64 then BitVec.allOnes 64 else a.udiv b

/-- `div`: all ones (`-1`) on a zero divisor; otherwise `BitVec.sdiv` (which wraps on overflow). -/
def divs (a b : W) : W := if b = 0#64 then BitVec.allOnes 64 else a.sdiv b

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
  | .addImm d v => .next (m.arith d (m.regs d + BitVec.ofInt 64 v))
  | .shlImm d k => .next (m.arith d (m.regs d <<< (k % 64)))
  | .not d => .next (m.arith d (~~~m.regs d))
  | .neg d => .next (m.arith d (0#64 - m.regs d))
  | .sltiu d s k => .next (m.arith d (Word.ofBool ((m.regs s).ult (BitVec.ofNat 64 k))))
  | .sll d s => .next (m.arith d (m.regs d <<< ((m.regs s).toNat % 64)))
  | .srl d s => .next (m.arith d (m.regs d >>> ((m.regs s).toNat % 64)))
  | .divu d a b => .next (m.arith d (divu (m.regs a) (m.regs b)))
  | .div d a b => .next (m.arith d (divs (m.regs a) (m.regs b)))
  | .bcc c a b t => .next (if c.eval (m.regs a) (m.regs b) then { m with pc := t } else m.adv)
  | .beqz a t => .next (if m.regs a = 0#64 then { m with pc := t } else m.adv)
  | .bnez a t => .next (if m.regs a = 0#64 then m.adv else { m with pc := t })
  | .jmp t => .next { m with pc := t }
  | .call t =>
      let sp := m.regs .s5 - 8#64
      let ra := BitVec.ofNat 64 (m.pc + 1)
      match m.mem.write? sp ra with
      | some mem' => .next { ((m.setReg .ra ra).setReg .s5 sp) with mem := mem', pc := t }
      | none => .fault
  | .ret =>
      match m.mem.read? (m.regs .s5) with
      | some v => .next { ((m.setReg .ra v).setReg .s5 (m.regs .s5 + 8#64)) with pc := v.toNat }
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

end RV
end WordDialect
