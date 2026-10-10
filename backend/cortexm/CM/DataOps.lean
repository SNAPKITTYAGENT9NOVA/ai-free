import CM.Isa

/-!
# CM.DataOps

The Thumb-2 data-processing instructions in their general form, as hand-written Cortex-M programs
use them: three registers (`add r2, r0, r1`), shifts by a register (`lsl r0, r0, r1`, bottom
byte of the amount) and shifts by a constant (`lsl r9, r0, #2`), including the arithmetic shift
`asr`. The lowering does not need these forms; they are in the model so that Cortex-M programs
written by hand can be run and reasoned about in Lean. This is the Cortex-M counterpart of
`A64.DataOps`, `RV.DataOps` and `RV32.DataOps`.

* `alu_toNat`, `lsl_toNat`, `lsr_toNat`, `divu_toNat`: the unsigned meaning of each
  instruction, in natural numbers modulo `2^32`;
* `sub_toInt`, `mul_toInt`, `asr_toInt`: the signed meaning (`asr` is division by `2^n` rounded
  toward negative infinity, which `lsr` is not for negative numbers: `asr_neg_example`);
* `shift_reg`, `lsl_reg_40`, `lsl_reg_257`: a register shift uses the bottom byte of the amount,
  so shifting by 40 gives zero but shifting by 257 shifts by 1 (unlike Thumb-2, which uses the
  amount modulo the word size);
* `divu_zero`, `div_zero`: division by zero gives zero and does not fault;
* `dataProcessing`: the data-processing program of `A64.DataOps` in Thumb-2 (initialise
  `r0 = 10`, `r1 = 3`, then `add sub mul udiv and orr eor lsl lsr asr`), and
  `dataProcessing_run`: running it in the model halts with `r2 … r11 = 13 7 30 3 2 11 9 40 5 5`.

`cmc check` runs the same program, printed by `CM.Emit`, on the emulated Cortex-M3 board and
compares the registers with the model (`CMMain.lean`).
-/

namespace WordDialect
namespace CM

open Reg

/-! ## What each instruction computes -/

theorem exec_alu (op : Alu) (d a b : Reg) (m : M) :
    exec (.alu op d a b) m = .next (m.arith d (op.eval (m.regs a) (m.regs b))) := rfl

theorem exec_shiftImm (k : Shift) (d a : Reg) (n : Nat) (m : M) :
    exec (.shiftImm k d a n) m = .next (m.arith d (k.eval (m.regs a) n)) := rfl

/-- `add`, `sub`, `mul` are arithmetic modulo `2^32`; `and`, `orr`, `eor` are bitwise. -/
theorem alu_toNat (a b : W) :
    (Alu.add.eval a b).toNat = (a.toNat + b.toNat) % 2 ^ 32 ∧
    (Alu.sub.eval a b).toNat = (2 ^ 32 - b.toNat + a.toNat) % 2 ^ 32 ∧
    (Alu.mul.eval a b).toNat = a.toNat * b.toNat % 2 ^ 32 ∧
    (Alu.and.eval a b).toNat = a.toNat &&& b.toNat ∧
    (Alu.orr.eval a b).toNat = a.toNat ||| b.toNat ∧
    (Alu.eor.eval a b).toNat = a.toNat ^^^ b.toNat := by
  simp [Alu.eval, BitVec.toNat_add, BitVec.toNat_sub, BitVec.toNat_mul]

/-- Signed reading: `sub` and `mul` are integer subtraction and multiplication, wrapped into
32-bit two's complement. -/
theorem sub_toInt (a b : W) : Alu.sub.eval a b = BitVec.ofInt 32 (a.toInt - b.toInt) := by
  rw [Int.sub_eq_add_neg, BitVec.ofInt_add, BitVec.ofInt_neg, BitVec.ofInt_toInt, BitVec.ofInt_toInt,
    ← BitVec.sub_eq_add_neg]
  rfl

theorem mul_toInt (a b : W) : Alu.mul.eval a b = BitVec.ofInt 32 (a.toInt * b.toInt) := by
  simp [Alu.eval, BitVec.ofInt_mul]

/-- The register shifts are the constant shifts by the bottom byte of the amount. -/
theorem shift_reg (a b : W) :
    Alu.lsl.eval a b = Shift.lsl.eval a (b.toNat % 256) ∧
    Alu.lsr.eval a b = Shift.lsr.eval a (b.toNat % 256) ∧
    Alu.asr.eval a b = Shift.asr.eval a (b.toNat % 256) := by
  simp [Alu.eval, Shift.eval]

/-- Shifting left by a register holding 40 gives zero: the amount is not reduced modulo 32. -/
theorem lsl_reg_40 (a : W) : Alu.lsl.eval a 40#32 = 0#32 := by
  apply BitVec.eq_of_toNat_eq
  simp [Alu.eval, BitVec.toNat_shiftLeft, Nat.shiftLeft_eq]

/-- Only the bottom byte counts: shifting by 257 is shifting by 1. -/
theorem lsl_reg_257 (a : W) : Alu.lsl.eval a 257#32 = Shift.lsl.eval a 1 := by
  simp [Alu.eval, Shift.eval]

/-- `lsl #n` multiplies by `2^n` modulo `2^32`. -/
theorem lsl_toNat (a : W) (n : Nat) : (Shift.lsl.eval a n).toNat = a.toNat * 2 ^ n % 2 ^ 32 := by
  simp [Shift.eval, BitVec.toNat_shiftLeft, Nat.shiftLeft_eq]

/-- `lsr #n` divides the unsigned value by `2^n`. -/
theorem lsr_toNat (a : W) (n : Nat) : (Shift.lsr.eval a n).toNat = a.toNat / 2 ^ n := by
  simp [Shift.eval, BitVec.toNat_ushiftRight, Nat.shiftRight_eq_div_pow]

/-- `asr #n` divides the signed value by `2^n`, rounding toward negative infinity. -/
theorem asr_toInt (a : W) (n : Nat) : (Shift.asr.eval a n).toInt = a.toInt / 2 ^ n := by
  simp [Shift.eval, BitVec.toInt_sshiftRight, Int.shiftRight_eq_div_pow]

/-- `udiv` divides the unsigned values when the divisor is not zero. -/
theorem divu_toNat (a b : W) (h : b ≠ 0#32) : (divu a b).toNat = a.toNat / b.toNat := by
  simp only [divu, h, if_false]
  show (a / b).toNat = _
  exact BitVec.toNat_udiv

/-- Division by zero does not fault: both divisions give zero. -/
theorem divu_zero (a : W) : divu a 0#32 = 0#32 := by simp [divu]

theorem div_zero (a : W) : divs a 0#32 = 0#32 := by simp [divs]

/-- `asr` and `lsr` differ on negative numbers: `-10 asr 1 = -5`, while `lsr` gives a large
positive number. -/
theorem asr_neg_example :
    Shift.asr.eval (BitVec.ofInt 32 (-10)) 1 = BitVec.ofInt 32 (-5) ∧
      Shift.lsr.eval (BitVec.ofInt 32 (-10)) 1 = 0x7ffffffb#32 := by
  decide

/-! ## A data-processing program -/

/-- The program: `mov r0, #10; mov r1, #3`, then one of each data-processing instruction, then
halt. -/
def dataProcessing : List (Instr Nat) :=
  [.movImm r0 10#32, .movImm r1 3#32,
   .alu .add r2 r0 r1, .alu .sub r3 r0 r1, .alu .mul r4 r0 r1, .divu r5 r0 r1,
   .alu .and r6 r0 r1, .alu .orr r7 r0 r1, .alu .eor r8 r0 r1,
   .shiftImm .lsl r9 r0 2, .shiftImm .lsr r10 r0 1, .shiftImm .asr r11 r0 1,
   .exitHalt]

/-- The registers the program sets, in order `r0 r1 r2 … r11`. -/
def dataRegs : List Reg := [r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11]

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

end CM
end WordDialect
