import BCPL.Compile

/-!
# BCPL.ExprCorrect

Straight-line correctness of expression and assignment lowering against `evalE` /
`assignSem`: whenever the reference semantics succeeds, `execSeq` of the lowered code
reaches the corresponding state; whenever it traps, `execSeq` traps with the same trap.
-/

namespace WordDialect
namespace BCPL

open IR

theorem binCode_straight {n : Nat} (o : BinOp) :
    ∀ i ∈ (binCode o : List (Instr n)), i.isStraight = true := by
  cases o <;> simp [binCode, cmpFlagCode, Instr.isStraight]

theorem unCode_straight {n : Nat} (o : UnOp) :
    ∀ i ∈ (unCode o : List (Instr n)), i.isStraight = true := by
  cases o <;> simp [unCode, Instr.isStraight]

theorem compileE_straight {n : Nat} (addr : Var → Word n) (e : Expr) :
    ∀ i ∈ (compileE addr e), i.isStraight = true := by
  induction e with
  | num z => simp [compileE, Instr.isStraight]
  | var x => simp [compileE, Instr.isStraight]
  | addrOf x => simp [compileE, Instr.isStraight]
  | rv e ih =>
    intro i hi
    simp only [compileE, List.mem_append, List.mem_singleton] at hi
    rcases hi with hi | rfl
    · exact ih i hi
    · rfl
  | un o e ih =>
    intro i hi
    simp only [compileE, List.mem_append] at hi
    rcases hi with hi | hi
    · exact ih i hi
    · exact unCode_straight o i hi
  | bin o a b iha ihb =>
    intro i hi
    simp only [compileE, List.mem_append] at hi
    rcases hi with (hi | hi) | hi
    · exact iha i hi
    · exact ihb i hi
    · exact binCode_straight o i hi

theorem assignCode_straight {n : Nat} (addr : Var → Word n) (l : LVal) (e : Expr) :
    ∀ i ∈ (assignCode addr l e), i.isStraight = true := by
  cases l with
  | var x =>
    intro i hi
    simp only [assignCode, List.mem_append, List.mem_cons, List.not_mem_nil, or_false] at hi
    rcases hi with hi | rfl | rfl
    · exact compileE_straight addr e i hi
    · rfl
    · rfl
  | rv a =>
    intro i hi
    simp only [assignCode, List.mem_append, List.mem_cons, List.not_mem_nil, or_false] at hi
    rcases hi with (hi | hi) | rfl
    · exact compileE_straight addr e i hi
    · exact compileE_straight addr a i hi
    · rfl


theorem binCode_ok {n : Nat} (o : BinOp) (s : State n) (a b v : Word n) (d : List (Word n))
    (hs : s.dstack = b :: a :: d) (h : o.sem a b = .ok v) :
    execSeq (binCode o) s =
      .next { s with pc := s.pc + (binCode o : List (Instr n)).length, dstack := v :: d } := by
  cases o <;> simp only [BinOp.sem] at h <;> (try split at h) <;>
    first
      | (exfalso; cases h; done)
      | (cases h
         first
           | (simp [binCode, execSeq, exec, State.fall, hs, *]; done)
           | (simp [binCode, cmpFlagCode, execSeq, exec, State.fall, hs, flag, *]))

theorem binCode_err {n : Nat} (o : BinOp) (s : State n) (a b : Word n) (d : List (Word n))
    (t : Trap) (hs : s.dstack = b :: a :: d) (h : o.sem a b = .error t) :
    execSeq (binCode o) s = .trapped t := by
  cases o <;> simp only [BinOp.sem] at h <;> (try split at h) <;>
    first
      | (exfalso; cases h; done)
      | (cases h; simp [binCode, execSeq, exec, State.fall, hs, *])

theorem unCode_ok {n : Nat} (o : UnOp) (s : State n) (a : Word n) (d : List (Word n))
    (hs : s.dstack = a :: d) :
    execSeq (unCode o) s =
      .next { s with pc := s.pc + (unCode o : List (Instr n)).length, dstack := o.sem a :: d } := by
  cases o <;> simp [unCode, UnOp.sem, execSeq, exec, State.fall, hs]

theorem compileE_ok {n : Nat} (addr : Var → Word n) (e : Expr) :
    ∀ (s : State n) (v : Word n), evalE addr e s.mem = .ok v →
      execSeq (compileE addr e) s =
        .next { s with pc := s.pc + (compileE addr e).length, dstack := v :: s.dstack } := by
  induction e with
  | num z =>
    intro s v h
    simp only [evalE] at h; cases h
    simp [compileE, execSeq, exec, State.fall]
  | var x =>
    intro s v h
    simp only [evalE, readW] at h
    split at h
    · rename_i hr; cases h
      simp [compileE, execSeq, exec, State.fall, hr]
    · cases h
  | addrOf x =>
    intro s v h
    simp only [evalE] at h; cases h
    simp [compileE, execSeq, exec, State.fall]
  | rv e ih =>
    intro s v h
    simp only [evalE] at h
    split at h
    · cases h
    · rename_i a ha
      simp only [readW] at h
      split at h
      · rename_i hr; cases h
        rw [compileE, execSeq_append, ih s a ha]
        simp [Outcome.andThen, execSeq, exec, State.fall, hr, Nat.add_assoc]
      · cases h
  | un o e ih =>
    intro s v h
    simp only [evalE] at h
    split at h
    · cases h
    · rename_i a ha; cases h
      rw [compileE, execSeq_append, ih s a ha]
      simp only [Outcome.andThen]
      rw [unCode_ok o _ a s.dstack rfl]
      simp [List.length_append]; omega
  | bin o a b iha ihb =>
    intro s v h
    simp only [evalE] at h
    split at h
    · cases h
    · rename_i va ha
      split at h
      · cases h
      · rename_i vb hb
        rw [compileE, execSeq_append, execSeq_append, iha s va ha]
        simp only [Outcome.andThen]
        rw [ihb { s with pc := s.pc + (compileE addr a).length, dstack := va :: s.dstack } vb hb]
        simp only [Outcome.andThen]
        rw [binCode_ok o _ va vb v s.dstack rfl h]
        simp [List.length_append]; omega

theorem compileE_err {n : Nat} (addr : Var → Word n) (e : Expr) :
    ∀ (s : State n) (t : Trap), evalE addr e s.mem = .error t →
      execSeq (compileE addr e) s = .trapped t := by
  induction e with
  | num z => intro s t h; simp [evalE] at h
  | var x =>
    intro s t h
    simp only [evalE, readW] at h
    split at h
    · cases h
    · rename_i hr; cases h
      simp [compileE, execSeq, exec, State.fall, hr]
  | addrOf x => intro s t h; simp [evalE] at h
  | rv e ih =>
    intro s t h
    simp only [evalE] at h
    split at h
    · rename_i t' ht; cases h
      rw [compileE, execSeq_append, ih s _ ht]; rfl
    · rename_i a ha
      simp only [readW] at h
      split at h
      · cases h
      · rename_i hr; cases h
        rw [compileE, execSeq_append, compileE_ok addr e s a ha]
        simp [Outcome.andThen, execSeq, exec, State.fall, hr, Nat.add_assoc]
  | un o e ih =>
    intro s t h
    simp only [evalE] at h
    split at h
    · rename_i t' ht; cases h
      rw [compileE, execSeq_append, ih s _ ht]; rfl
    · cases h
  | bin o a b iha ihb =>
    intro s t h
    simp only [evalE] at h
    split at h
    · rename_i t' ht; cases h
      rw [compileE, execSeq_append, execSeq_append, iha s _ ht]; rfl
    · rename_i va ha
      split at h
      · rename_i t' ht; cases h
        rw [compileE, execSeq_append, execSeq_append, compileE_ok addr a s va ha]
        simp only [Outcome.andThen]
        rw [ihb { s with pc := s.pc + (compileE addr a).length, dstack := va :: s.dstack } _ ht]
      · rename_i vb hb
        rw [compileE, execSeq_append, execSeq_append, compileE_ok addr a s va ha]
        simp only [Outcome.andThen]
        rw [compileE_ok addr b { s with pc := s.pc + (compileE addr a).length, dstack := va :: s.dstack } vb hb]
        simp only [Outcome.andThen]
        exact binCode_err o _ va vb s.dstack t rfl h

end BCPL
end WordDialect
