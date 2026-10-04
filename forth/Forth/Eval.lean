import Forth.Semantics

/-!
# Forth.Eval

A fuel-bounded executable interpreter for the Forth reference semantics, proved sound
against `Run`: if it returns a result, `Run` derives that result. It lets concrete facts about
the reference semantics (including recursive words) be established by evaluation.
-/

namespace WordDialect
namespace Forth

/-- Run `b` from `st` with at most `fuel` nested evaluation steps; `none` means out of fuel. -/
def eval {n : Nat} (defs : List Block) : Nat → Block → FState n → Option (Res n)
  | 0, _, _ => none
  | _ + 1, .nil, st => some (.ok st)
  | _ + 1, .exit _, st => some (.exit st)
  | f + 1, .op o rest, st =>
    match o.sem st with
    | .ok st' => eval defs f rest st'
    | .error t => some (.error t)
  | _ + 1, .ite _ _ _, ⟨[], _, _⟩ => some (.error .stackUnderflow)
  | f + 1, .ite t e rest, ⟨c :: d, m, rs⟩ =>
    match eval defs f (if Word.isTrue c then t else e) ⟨d, m, rs⟩ with
    | none => none
    | some (.error x) => some (.error x)
    | some (.exit st1) => some (.exit st1)
    | some (.ok st1) => eval defs f rest st1
  | f + 1, .untilL body rest, st =>
    match eval defs f body st with
    | none => none
    | some (.error x) => some (.error x)
    | some (.exit st1) => some (.exit st1)
    | some (.ok ⟨[], _, _⟩) => some (.error .stackUnderflow)
    | some (.ok ⟨c :: d, m, rs⟩) =>
      if Word.isTrue c then eval defs f rest ⟨d, m, rs⟩
      else eval defs f (.untilL body rest) ⟨d, m, rs⟩
  | f + 1, .call i rest, st =>
    match defs[i]? with
    | none => some (.error .badPc)
    | some body =>
      match eval defs f body st with
      | none => none
      | some (.error x) => some (.error x)
      | some (.exit st1) => eval defs f rest st1
      | some (.ok st1) => eval defs f rest st1
  | f + 1, .doLoop body rest, ⟨i :: l :: d, m, rs⟩ =>
    match eval defs f body ⟨d, m, i :: l :: rs⟩ with
    | none => none
    | some (.error x) => some (.error x)
    | some (.exit st1) => some (.exit st1)
    | some (.ok ⟨d1, m1, i1 :: l1 :: rs1⟩) =>
      if i1 + 1#n = l1 then eval defs f rest ⟨d1, m1, rs1⟩
      else eval defs f (.doLoop body rest) ⟨(i1 + 1#n) :: l1 :: d1, m1, rs1⟩
    | some (.ok _) => some (.error .returnUnderflow)
  | _ + 1, .doLoop _ _, _ => some (.error .stackUnderflow)

theorem eval_sound {n : Nat} {defs : List Block} :
    ∀ (fuel : Nat) (b : Block) (st : FState n) (r : Res n),
      eval defs fuel b st = some r → Run defs b st r := by
  intro fuel
  induction fuel with
  | zero => intro b st r h; simp [eval] at h
  | succ f ih =>
    intro b st r h
    cases b with
    | nil => simp only [eval, Option.some.injEq] at h; subst h; exact .nil
    | exit rest => simp only [eval, Option.some.injEq] at h; subst h; exact .exit
    | op o rest =>
      simp only [eval] at h
      split at h
      · exact .opOk ‹_› (ih _ _ _ h)
      · cases h; exact .opErr ‹_›
    | ite t e rest =>
      obtain ⟨d, m, rs⟩ := st
      cases d with
      | nil => simp only [eval, Option.some.injEq] at h; subst h; exact .iteUnder
      | cons c d =>
        simp only [eval] at h
        split at h
        · cases h
        · rename_i x hx
          cases h
          cases hc : Word.isTrue c
          · rw [hc] at hx; exact .iteFalseStop hc (ih _ _ _ hx) rfl
          · rw [hc] at hx; exact .iteTrueStop hc (ih _ _ _ hx) rfl
        · rename_i x hx
          cases h
          cases hc : Word.isTrue c
          · rw [hc] at hx; exact .iteFalseStop hc (ih _ _ _ hx) rfl
          · rw [hc] at hx; exact .iteTrueStop hc (ih _ _ _ hx) rfl
        · rename_i st1 hx
          cases hc : Word.isTrue c
          · rw [hc] at hx; exact .iteFalse hc (ih _ _ _ hx) (ih _ _ _ h)
          · rw [hc] at hx; exact .iteTrue hc (ih _ _ _ hx) (ih _ _ _ h)
    | untilL body rest =>
      simp only [eval] at h
      split at h
      · cases h
      · rename_i x hx; cases h; exact .untilBodyStop (ih _ _ _ hx) rfl
      · rename_i x hx; cases h; exact .untilBodyStop (ih _ _ _ hx) rfl
      · rename_i m rs hx; cases h; exact .untilUnder (ih _ _ _ hx)
      · rename_i c d m rs hx
        cases hc : Word.isTrue c
        · rw [hc] at h; exact .untilAgain (ih _ _ _ hx) hc (ih _ _ _ h)
        · rw [hc] at h; exact .untilDone (ih _ _ _ hx) hc (ih _ _ _ h)
    | call i rest =>
      simp only [eval] at h
      split at h
      · cases h; exact .callUndef ‹_›
      · rename_i body hi
        split at h
        · cases h
        · rename_i x hx; cases h; exact .callErr hi (ih _ _ _ hx)
        · rename_i st1 hx; exact .callOk hi (ih _ _ _ hx) rfl (ih _ _ _ h)
        · rename_i st1 hx; exact .callOk hi (ih _ _ _ hx) rfl (ih _ _ _ h)
    | doLoop body rest =>
      obtain ⟨d, m, rs⟩ := st
      rcases d with _ | ⟨i, _ | ⟨l, d⟩⟩
      · simp only [eval, Option.some.injEq] at h; subst h; exact .doUnder (by simp)
      · simp only [eval, Option.some.injEq] at h; subst h; exact .doUnder (by simp)
      simp only [eval] at h
      split at h
      · cases h
      · rename_i x hx; cases h; exact .doBodyStop (ih _ _ _ hx) rfl
      · rename_i x hx; cases h; exact .doBodyStop (ih _ _ _ hx) rfl
      · rename_i d1 m1 i1 l1 rs1 hx
        split at h
        · exact .doDone (ih _ _ _ hx) ‹_› (ih _ _ _ h)
        · exact .doAgain (ih _ _ _ hx) ‹_› (ih _ _ _ h)
      · rename_i st1 hne hx
        cases h
        obtain ⟨d1, m1, rs1⟩ := st1
        rcases rs1 with _ | ⟨a, _ | ⟨b, rs1⟩⟩
        · exact .doTestUnder (ih _ _ _ hx) (by simp)
        · exact .doTestUnder (ih _ _ _ hx) (by simp)
        · exact absurd rfl (hne d1 m1 a b rs1)

end Forth
end WordDialect
