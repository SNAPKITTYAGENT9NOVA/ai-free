import Forth.Compile

/-!
# Forth.OpCorrect

Each Forth operation, lowered to straight-line IR, behaves exactly as `Op.sem` says:
* if `Op.sem` succeeds, `execSeq` of the lowered code reaches the corresponding state;
* if `Op.sem` fails with trap `t`, `execSeq` of the lowered code traps with the same `t`.
-/

namespace WordDialect
namespace Forth

open IR

/-- `SELECT` on a `CMP` flag picks by the comparison, for every width (at `n = 0` both choices
are the one word). -/
theorem ite_isTrue_ofBool {n : Nat} (c : Bool) (x y : Word n) :
    (if Word.isTrue (Word.ofBool (n := n) c) = true then x else y) = (if c = true then x else y) := by
  rcases Nat.eq_zero_or_pos n with h | h
  · subst h
    have : x = y := BitVec.eq_of_toNat_eq (by have := x.isLt; have := y.isLt; simp at *; omega)
    subst this; simp
  · rw [Word.isTrue_ofBool h]

theorem compileOp_straight {n : Nat} (o : Op) :
    ∀ i ∈ (compileOp o : List (Instr n)), i.isStraight = true := by
  cases o <;> simp [compileOp, cmpFlagCode, Instr.isStraight]

theorem compileOp_ok {n : Nat} (o : Op) (hl : o.loopy = false) (s : State n) (st' : FState n)
    (h : o.sem ⟨s.dstack, s.mem, s.astack⟩ = .ok st') :
    execSeq (compileOp o) s =
      .next { s with pc := s.pc + (compileOp o : List (Instr n)).length,
                     dstack := st'.stack, mem := st'.mem,
                     astack := st'.rstack } := by
  obtain ⟨pc, d, rs, as, regs, mem⟩ := s
  cases o <;> (try (simp [Op.loopy] at hl; done)) <;> rcases d with _ | ⟨x, _ | ⟨y, _ | ⟨z, _ | ⟨q, d⟩⟩⟩⟩ <;>
    rcases as with _ | ⟨u, _ | ⟨v, _ | ⟨w, as⟩⟩⟩ <;>
    simp only [Op.sem] at h <;>
    (try split at h) <;> (try split at h) <;>
    first
      | (exfalso; cases h; done)
      | (cases h
         simp [compileOp, cmpFlagCode, execSeq, exec, State.fall, flag, BitVec.mul_comm,
           ite_isTrue_ofBool, *])

theorem compileOp_err {n : Nat} (o : Op) (hl : o.loopy = false) (s : State n) (t : Trap)
    (h : o.sem ⟨s.dstack, s.mem, s.astack⟩ = .error t) :
    execSeq (compileOp o) s = .trapped t := by
  obtain ⟨pc, d, rs, as, regs, mem⟩ := s
  cases o <;> (try (simp [Op.loopy] at hl; done)) <;> rcases d with _ | ⟨x, _ | ⟨y, _ | ⟨z, _ | ⟨q, d⟩⟩⟩⟩ <;>
    rcases as with _ | ⟨u, _ | ⟨v, _ | ⟨w, as⟩⟩⟩ <;>
    simp only [Op.sem] at h <;>
    (try split at h) <;> (try split at h) <;>
    first
      | (exfalso; cases h; done)
      | (cases h
         simp [compileOp, cmpFlagCode, execSeq, exec, State.fall, *])

end Forth
end WordDialect
