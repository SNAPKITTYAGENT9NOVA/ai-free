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

theorem compileOp_straight {n : Nat} (o : Op) :
    ∀ i ∈ (compileOp o : List (Instr n)), i.isStraight = true := by
  cases o <;> simp [compileOp, cmpFlagCode, Instr.isStraight]

theorem compileOp_ok {n : Nat} (o : Op) (s : State n) (st' : FState n)
    (h : o.sem ⟨s.dstack, s.mem⟩ = .ok st') :
    execSeq (compileOp o) s =
      .next { s with pc := s.pc + (compileOp o : List (Instr n)).length,
                     dstack := st'.stack, mem := st'.mem } := by
  obtain ⟨pc, d, rs, as, regs, mem⟩ := s
  cases o <;> rcases d with _ | ⟨x, _ | ⟨y, _ | ⟨z, d⟩⟩⟩ <;>
    simp only [Op.sem] at h <;>
    (try split at h) <;> (try split at h) <;>
    first
      | (exfalso; cases h; done)
      | (cases h
         simp [compileOp, cmpFlagCode, execSeq, exec, State.fall, flag, BitVec.mul_comm, *])

theorem compileOp_err {n : Nat} (o : Op) (s : State n) (t : Trap)
    (h : o.sem ⟨s.dstack, s.mem⟩ = .error t) :
    execSeq (compileOp o) s = .trapped t := by
  obtain ⟨pc, d, rs, as, regs, mem⟩ := s
  cases o <;> rcases d with _ | ⟨x, _ | ⟨y, _ | ⟨z, d⟩⟩⟩ <;>
    simp only [Op.sem] at h <;>
    (try split at h) <;> (try split at h) <;>
    first
      | (exfalso; cases h; done)
      | (cases h
         simp [compileOp, cmpFlagCode, execSeq, exec, State.fall, *])

end Forth
end WordDialect
