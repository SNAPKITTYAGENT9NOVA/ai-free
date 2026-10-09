import A64.Isa

/-!
# A64.DataOps

The AArch64 data-processing instructions in their general form, as hand-written programs use
them: three registers (`add x2, x0, x1`) and shifts by a constant (`lsl x9, x0, #2`), including the
arithmetic shift `asr`. The lowering does not need these forms; they are in the model so that
AArch64 programs written by hand can be run and reasoned about in Lean.

* `alu_toNat`, `lsl_toNat`, `lsr_toNat`, `udiv_toNat`: the unsigned meaning of each instruction,
  in natural numbers modulo `2^64`;
* `sub_toInt`, `mul_toInt`, `asr_toInt`: the signed meaning (`asr` is division by `2^n` rounded
  toward negative infinity, which `lsr` is not for negative numbers: `asr_neg_example`);
* `dataProcessing`: a short program exercising every one of them (initialise `x0 = 10`,
  `x1 = 3`, then `add sub mul udiv and orr eor lsl lsr asr`), and `dataProcessing_run`: running it
  in the model halts with `x2 … x11 = 13 7 30 3 2 11 9 40 5 5`.

`a64c check` runs the same program, printed by `A64.Emit`, under `qemu-aarch64` and compares
the registers with the model (`A64Main.lean`).
-/

namespace WordDialect
namespace A64

open Reg

/-! ## What each instruction computes -/

theorem exec_alu (op : Alu) (d a b : Reg) (m : M) :
    exec (.alu op d a b) m = .next (m.arith d (op.eval (m.regs a) (m.regs b))) := rfl

theorem exec_shiftImm (k : Shift) (d a : Reg) (n : Nat) (m : M) :
    exec (.shiftImm k d a n) m = .next (m.arith d (k.eval (m.regs a) n)) := rfl

/-- `add`, `sub`, `mul` are arithmetic modulo `2^64`; `and`, `orr`, `eor` are bitwise. -/
theorem alu_toNat (a b : W) :
    (Alu.add.eval a b).toNat = (a.toNat + b.toNat) % 2 ^ 64 ∧
    (Alu.sub.eval a b).toNat = (2 ^ 64 - b.toNat + a.toNat) % 2 ^ 64 ∧
    (Alu.mul.eval a b).toNat = a.toNat * b.toNat % 2 ^ 64 ∧
    (Alu.and.eval a b).toNat = a.toNat &&& b.toNat ∧
    (Alu.orr.eval a b).toNat = a.toNat ||| b.toNat ∧
    (Alu.eor.eval a b).toNat = a.toNat ^^^ b.toNat := by
  simp [Alu.eval, BitVec.toNat_add, BitVec.toNat_sub, BitVec.toNat_mul]

/-- Signed reading: `sub` and `mul` are integer subtraction and multiplication, wrapped into
64-bit two's complement. -/
theorem sub_toInt (a b : W) : Alu.sub.eval a b = BitVec.ofInt 64 (a.toInt - b.toInt) := by
  rw [Int.sub_eq_add_neg, BitVec.ofInt_add, BitVec.ofInt_neg, BitVec.ofInt_toInt, BitVec.ofInt_toInt,
    ← BitVec.sub_eq_add_neg]
  rfl

theorem mul_toInt (a b : W) : Alu.mul.eval a b = BitVec.ofInt 64 (a.toInt * b.toInt) := by
  simp [Alu.eval, BitVec.ofInt_mul]

/-- `lsl #n` multiplies by `2^n` modulo `2^64`. -/
theorem lsl_toNat (a : W) (n : Nat) : (Shift.lsl.eval a n).toNat = a.toNat * 2 ^ n % 2 ^ 64 := by
  simp [Shift.eval, BitVec.toNat_shiftLeft, Nat.shiftLeft_eq]

/-- `lsr #n` divides the unsigned value by `2^n`. -/
theorem lsr_toNat (a : W) (n : Nat) : (Shift.lsr.eval a n).toNat = a.toNat / 2 ^ n := by
  simp [Shift.eval, BitVec.toNat_ushiftRight, Nat.shiftRight_eq_div_pow]

/-- `asr #n` divides the signed value by `2^n`, rounding toward negative infinity. -/
theorem asr_toInt (a : W) (n : Nat) : (Shift.asr.eval a n).toInt = a.toInt / 2 ^ n := by
  simp [Shift.eval, BitVec.toInt_sshiftRight, Int.shiftRight_eq_div_pow]

/-- `udiv` divides the unsigned values (and gives `0` for a zero divisor). -/
theorem udiv_toNat (a b : W) : (a.udiv b).toNat = a.toNat / b.toNat := by
  show (a / b).toNat = _
  exact BitVec.toNat_udiv

/-- `asr` and `lsr` differ on negative numbers: `-10 asr 1 = -5`, while `lsr` gives a large
positive number. -/
theorem asr_neg_example :
    Shift.asr.eval (BitVec.ofInt 64 (-10)) 1 = BitVec.ofInt 64 (-5) ∧
      Shift.lsr.eval (BitVec.ofInt 64 (-10)) 1 = 0x7ffffffffffffffb#64 := by
  decide

/-! ## A data-processing program -/

/-- The program: `mov x0, #10; mov x1, #3`, then one of each data-processing instruction, then
halt. -/
def dataProcessing : List (Instr Nat) :=
  [.movImm x0 10#64, .movImm x1 3#64,
   .alu .add x2 x0 x1, .alu .sub x3 x0 x1, .alu .mul x4 x0 x1, .udiv x5 x0 x1,
   .alu .and x6 x0 x1, .alu .orr x7 x0 x1, .alu .eor x8 x0 x1,
   .shiftImm .lsl x9 x0 2, .shiftImm .lsr x10 x0 1, .shiftImm .asr x11 x0 1,
   .exitHalt]

/-- The registers the program sets, in order `x0 x1 x2 … x11`. -/
def dataRegs : List Reg := [x0, x1, x2, x3, x4, x5, x6, x7, x8, x9, x10, x11]

/-- Run a program from register file `r` at `pc = 0` and read `regs` when it halts. -/
def haltRegs (code : List (Instr Nat)) (fuel : Nat) (r : Reg → W) (mem : Memory 64)
    (regs : List Reg) : Option (List W) :=
  match run code fuel { regs := r, flags := none, mem := mem, pc := 0 } with
  | some (.halted m) => some (regs.map m.regs)
  | _ => none

/-- **The program computes what its comments say**, from any initial registers and memory:
`10 + 3 = 13`, `10 - 3 = 7`, `10 * 3 = 30`, `10 / 3 = 3`, `10 & 3 = 2`, `10 | 3 = 11`,
`10 ^ 3 = 9`, `10 << 2 = 40`, `10 >> 1 = 5` (logical and arithmetic). -/
theorem dataProcessing_run (r : Reg → W) (mem : Memory 64) :
    haltRegs dataProcessing 20 r mem dataRegs =
      some [10#64, 3#64, 13#64, 7#64, 30#64, 3#64, 2#64, 11#64, 9#64, 40#64, 5#64, 5#64] := by
  simp [haltRegs, dataProcessing, dataRegs, run, step, exec, M.mov, M.arith, M.setReg, M.adv,
    Alu.eval, Shift.eval]

end A64
end WordDialect
