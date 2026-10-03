import WordIR.Straight

/-!
# WordIR.Flag

Truth values as `-1` / `0`, shared by every frontend whose source language uses them
(Forth and BCPL both do). `CMP` yields `1`/`0`; `0 - x` turns that into `-1`/`0`.
-/

namespace WordDialect
namespace IR

/-- Source-level truth value: `-1` (all bits set) for true, `0` for false. -/
def flag {n : Nat} (b : Bool) : Word n := 0#n - Word.ofBool b

theorem flag_true {n : Nat} : (flag true : Word n) = BitVec.allOnes n := by
  simp [flag, Word.ofBool, BitVec.neg_one_eq_allOnes]

theorem flag_false {n : Nat} : (flag false : Word n) = 0#n := by
  simp [flag, Word.ofBool]

/-- `CMP c` then convert 1/0 to -1/0. -/
def cmpFlagCode {n : Nat} (c : Cond) : List (Instr n) := [.cmp c, .word 0#n, .swap, .sub]

theorem cmpFlagCode_straight {n : Nat} (c : Cond) :
    ∀ i ∈ (cmpFlagCode c : List (Instr n)), i.isStraight = true := by
  simp [cmpFlagCode, Instr.isStraight]

theorem cmpFlagCode_exec {n : Nat} (c : Cond) (s : State n) (a b : Word n) (d : List (Word n))
    (h : s.dstack = b :: a :: d) :
    execSeq (cmpFlagCode c) s =
      .next { s with pc := s.pc + 4, dstack := flag (c.eval a b) :: d } := by
  simp [cmpFlagCode, execSeq, exec, State.fall, h, flag]

end IR
end WordDialect
