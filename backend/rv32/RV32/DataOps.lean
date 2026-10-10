import RV32.Isa

/-!
# RV32.DataOps

The RISC-V data-processing instructions in their general form, as hand-written programs use them:
three registers (`add a2, a0, a1`), register shifts (`sll sra srl`, amount modulo 32) and shifts by a
constant (`slli srli srai`). The lowering does not need these forms; they are in the model so that
RISC-V programs written by hand can be run and reasoned about in Lean. This is the RISC-V
counterpart of `A64.DataOps` and `RV.DataOps`, at 32 bits.

* `alu_toNat`, `slli_toNat`, `srli_toNat`, `divu_toNat`: the unsigned meaning of each
  instruction, in natural numbers modulo `2^32`;
* `sub_toInt`, `mul_toInt`, `srai_toInt`: the signed meaning (`srai` is division by `2^n`
  rounded toward negative infinity, which `srli` is not for negative numbers:
  `srai_neg_example`);
* `sll_mod`: a register shift uses only the low five bits of the amount (`sll` by 65 is `sll` by 1);
* `divu_zero`, `div_zero`: division by zero gives all ones and does not fault;
* `dataProcessing`: the RISC-V version of the AArch64 data-processing program (initialise
  `a0 = 10`, `a1 = 3`, then `add sub mul divu and or xor slli srli srai`), and
  `dataProcessing_run`: running it in the model halts with
  `a2 … a7, s7 … s10 = 13 7 30 3 2 11 9 40 5 5`.

`rv32c check` runs the same program, printed by `RV32.Emit`, on the bare `virt` board under
`qemu-system-riscv32` and compares the registers with the model (`RV32Main.lean`).
-/

namespace WordDialect
namespace RV32

open Reg

/-! ## What each instruction computes -/

theorem exec_alu (op : Alu) (d a b : Reg) (m : M) :
    exec (.alu op d a b) m = .next (m.arith d (op.eval (m.regs a) (m.regs b))) := rfl

theorem exec_shiftImm (k : Shift) (d a : Reg) (n : Nat) (m : M) :
    exec (.shiftImm k d a n) m = .next (m.arith d (k.eval (m.regs a) n)) := rfl

/-- `add`, `sub`, `mul` are arithmetic modulo `2^32`; `and`, `or`, `xor` are bitwise. -/
theorem alu_toNat (a b : W) :
    (Alu.add.eval a b).toNat = (a.toNat + b.toNat) % 2 ^ 32 ∧
    (Alu.sub.eval a b).toNat = (2 ^ 32 - b.toNat + a.toNat) % 2 ^ 32 ∧
    (Alu.mul.eval a b).toNat = a.toNat * b.toNat % 2 ^ 32 ∧
    (Alu.and.eval a b).toNat = a.toNat &&& b.toNat ∧
    (Alu.or.eval a b).toNat = a.toNat ||| b.toNat ∧
    (Alu.xor.eval a b).toNat = a.toNat ^^^ b.toNat := by
  simp [Alu.eval, BitVec.toNat_add, BitVec.toNat_sub, BitVec.toNat_mul]

/-- Signed reading: `sub` and `mul` are integer subtraction and multiplication, wrapped into
32-bit two's complement. -/
theorem sub_toInt (a b : W) : Alu.sub.eval a b = BitVec.ofInt 32 (a.toInt - b.toInt) := by
  rw [Int.sub_eq_add_neg, BitVec.ofInt_add, BitVec.ofInt_neg, BitVec.ofInt_toInt, BitVec.ofInt_toInt,
    ← BitVec.sub_eq_add_neg]
  rfl

theorem mul_toInt (a b : W) : Alu.mul.eval a b = BitVec.ofInt 32 (a.toInt * b.toInt) := by
  simp [Alu.eval, BitVec.ofInt_mul]

/-- The register shifts are the constant shifts by the amount modulo 32. -/
theorem shift_reg (a b : W) :
    Alu.sll.eval a b = Shift.sll.eval a (b.toNat % 32) ∧
    Alu.srl.eval a b = Shift.srl.eval a (b.toNat % 32) ∧
    Alu.sra.eval a b = Shift.sra.eval a (b.toNat % 32) := by
  simp [Alu.eval, Shift.eval]

/-- Only the low six bits of a register shift amount count: shifting by 65 is shifting by 1. -/
theorem sll_mod (a : W) : Alu.sll.eval a 65#32 = Shift.sll.eval a 1 := by
  simp [Alu.eval, Shift.eval]

/-- `slli n` multiplies by `2^n` modulo `2^32`. -/
theorem slli_toNat (a : W) (n : Nat) : (Shift.sll.eval a n).toNat = a.toNat * 2 ^ n % 2 ^ 32 := by
  simp [Shift.eval, BitVec.toNat_shiftLeft, Nat.shiftLeft_eq]

/-- `srli n` divides the unsigned value by `2^n`. -/
theorem srli_toNat (a : W) (n : Nat) : (Shift.srl.eval a n).toNat = a.toNat / 2 ^ n := by
  simp [Shift.eval, BitVec.toNat_ushiftRight, Nat.shiftRight_eq_div_pow]

/-- `srai n` divides the signed value by `2^n`, rounding toward negative infinity. -/
theorem srai_toInt (a : W) (n : Nat) : (Shift.sra.eval a n).toInt = a.toInt / 2 ^ n := by
  simp [Shift.eval, BitVec.toInt_sshiftRight, Int.shiftRight_eq_div_pow]

/-- `divu` divides the unsigned values when the divisor is not zero. -/
theorem divu_toNat (a b : W) (h : b ≠ 0#32) : (divu a b).toNat = a.toNat / b.toNat := by
  simp only [divu, h, if_false]
  show (a / b).toNat = _
  exact BitVec.toNat_udiv

/-- Division by zero does not fault: both divisions give all ones (`-1`). -/
theorem divu_zero (a : W) : divu a 0#32 = BitVec.allOnes 32 := by simp [divu]

theorem div_zero (a : W) : divs a 0#32 = BitVec.allOnes 32 := by simp [divs]

/-- `srai` and `srli` differ on negative numbers: `-10 srai 1 = -5`, while `srli` gives a large
positive number. -/
theorem srai_neg_example :
    Shift.sra.eval (BitVec.ofInt 32 (-10)) 1 = BitVec.ofInt 32 (-5) ∧
      Shift.srl.eval (BitVec.ofInt 32 (-10)) 1 = 0x7ffffffb#32 := by
  decide

/-! ## A data-processing program -/

/-- The program: `li a0, 10; li a1, 3`, then one of each data-processing instruction, then
halt. -/
def dataProcessing : List (Instr Nat) :=
  [.movImm a0 10#32, .movImm a1 3#32,
   .alu .add a2 a0 a1, .alu .sub a3 a0 a1, .alu .mul a4 a0 a1, .divu a5 a0 a1,
   .alu .and a6 a0 a1, .alu .or a7 a0 a1, .alu .xor s7 a0 a1,
   .shiftImm .sll s8 a0 2, .shiftImm .srl s9 a0 1, .shiftImm .sra s10 a0 1,
   .exitHalt]

/-- The registers the program sets, in order `a0 … a7, s7 … s10`. -/
def dataRegs : List Reg := [a0, a1, a2, a3, a4, a5, a6, a7, s7, s8, s9, s10]

/-- Run a program from register file `r` at `pc = 0` and read `regs` when it halts. -/
def haltRegs (code : List (Instr Nat)) (fuel : Nat) (r : Reg → W) (mem : Memory 32)
    (regs : List Reg) : Option (List W) :=
  match run code fuel { regs := r, mem := mem, pc := 0 } with
  | some (.halted m) => some (regs.map m.regs)
  | _ => none

/-- **The program computes what its comments say**, from any initial registers and memory:
`10 + 3 = 13`, `10 - 3 = 7`, `10 * 3 = 30`, `10 / 3 = 3`, `10 & 3 = 2`, `10 | 3 = 11`,
`10 ^ 3 = 9`, `10 << 2 = 40`, `10 >> 1 = 5` (logical and arithmetic). -/
theorem dataProcessing_run (r : Reg → W) (mem : Memory 32) :
    haltRegs dataProcessing 20 r mem dataRegs =
      some [10#32, 3#32, 13#32, 7#32, 30#32, 3#32, 2#32, 11#32, 9#32, 40#32, 5#32, 5#32] := by
  simp [haltRegs, dataProcessing, dataRegs, run, step, exec, M.mov, M.arith, M.setReg, M.adv,
    Alu.eval, Shift.eval, divu]

end RV32
end WordDialect
