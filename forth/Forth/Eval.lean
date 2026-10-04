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
def eval {n : Nat} (defs : List Block) : Nat → Block → FState n → Option (Except Trap (FState n))
  | 0, _, _ => none
  | _ + 1, .nil, st => some (.ok st)
  | f + 1, .op o rest, st =>
    match o.sem st with
    | .ok st' => eval defs f rest st'
    | .error t => some (.error t)
  | _ + 1, .ite _ _ _, ⟨[], _⟩ => some (.error .stackUnderflow)
  | f + 1, .ite t e rest, ⟨c :: d, m⟩ =>
    match eval defs f (if Word.isTrue c then t else e) ⟨d, m⟩ with
    | none => none
    | some (.error x) => some (.error x)
    | some (.ok st1) => eval defs f rest st1
  | f + 1, .untilL body rest, st =>
    match eval defs f body st with
    | none => none
    | some (.error x) => some (.error x)
    | some (.ok ⟨[], _⟩) => some (.error .stackUnderflow)
    | some (.ok ⟨c :: d, m⟩) =>
      if Word.isTrue c then eval defs f rest ⟨d, m⟩ else eval defs f (.untilL body rest) ⟨d, m⟩
  | f + 1, .call i rest, st =>
    match defs[i]? with
    | none => some (.error .badPc)
    | some body =>
      match eval defs f body st with
      | none => none
      | some (.error x) => some (.error x)
      | some (.ok st1) => eval defs f rest st1

theorem eval_sound {n : Nat} {defs : List Block} :
    ∀ (fuel : Nat) (b : Block) (st : FState n) (r : Except Trap (FState n)),
      eval defs fuel b st = some r → Run defs b st r := by
  intro fuel
  induction fuel with
  | zero => intro b st r h; simp [eval] at h
  | succ f ih =>
    intro b st r h
    cases b with
    | nil => simp only [eval, Option.some.injEq] at h; subst h; exact .nil
    | op o rest =>
      simp only [eval] at h
      split at h
      · exact .opOk ‹_› (ih _ _ _ h)
      · cases h; exact .opErr ‹_›
    | ite t e rest =>
      obtain ⟨d, m⟩ := st
      cases d with
      | nil => simp only [eval, Option.some.injEq] at h; subst h; exact .iteUnder
      | cons c d =>
        simp only [eval] at h
        split at h
        · cases h
        · rename_i x hx
          cases h
          cases hc : Word.isTrue c
          · rw [hc] at hx; exact .iteFalseErr hc (ih _ _ _ hx)
          · rw [hc] at hx; exact .iteTrueErr hc (ih _ _ _ hx)
        · rename_i st1 hx
          cases hc : Word.isTrue c
          · rw [hc] at hx; exact .iteFalse hc (ih _ _ _ hx) (ih _ _ _ h)
          · rw [hc] at hx; exact .iteTrue hc (ih _ _ _ hx) (ih _ _ _ h)
    | untilL body rest =>
      simp only [eval] at h
      split at h
      · cases h
      · rename_i x hx; cases h; exact .untilBodyErr (ih _ _ _ hx)
      · rename_i m hx; cases h; exact .untilUnder (ih _ _ _ hx)
      · rename_i c d m hx
        cases hc : Word.isTrue c
        · rw [hc] at h; exact .untilAgain (ih _ _ _ hx) hc (ih _ _ _ h)
        · rw [hc] at h; exact .untilExit (ih _ _ _ hx) hc (ih _ _ _ h)
    | call i rest =>
      simp only [eval] at h
      split at h
      · cases h; exact .callUndef ‹_›
      · rename_i body hi
        split at h
        · cases h
        · rename_i x hx; cases h; exact .callErr hi (ih _ _ _ hx)
        · rename_i st1 hx; exact .callOk hi (ih _ _ _ hx) (ih _ _ _ h)

end Forth
end WordDialect
