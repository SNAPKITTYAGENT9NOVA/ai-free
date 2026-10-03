import Wasm.Rel

/-!
# Wasm.Seq

Straight-line execution (`execL`) with its `Run` derivation, sequencing, and the operand-count
guard `uf`.
-/

namespace WordDialect
namespace Wasm

/-- Straight-line evaluation of non-control instructions. -/
def execL : List WI → WState → Option WState
  | [], s => some s
  | i :: is, s => (stepI i s).bind (execL is)

theorem run_of_execL {fs : Funcs} : ∀ {is : List WI} {s s' : WState},
    (∀ i ∈ is, i.isCtl = false) → execL is s = some s' → Run fs is s (.normal s')
  | [], s, s', _, h => by simp [execL] at h; subst h; exact .nil
  | i :: is, s, s', hc, h => by
    simp only [execL] at h
    cases hs : stepI i s with
    | none => simp [hs] at h
    | some s1 =>
      rw [hs] at h
      exact .consNormal (.simple (hc i (by simp)) hs)
        (run_of_execL (fun j hj => hc j (by simp [hj])) h)

theorem run_append {fs : Funcs} : ∀ (a : List WI) {b : List WI} {s s' : WState} {r : Res},
    Run fs a s (.normal s') → Run fs b s' r → Run fs (a ++ b) s r
  | [], b, s, s', r, h1, h2 => by cases h1; simpa using h2
  | i :: a, b, s, s', r, h1, h2 => by
    cases h1 with
    | consNormal hi hs => exact .consNormal hi (run_append a hs h2)
    | consAbrupt hi hab => exact absurd hab (by simp [Res.abrupt])

theorem run_append_abrupt {fs : Funcs} : ∀ (a : List WI) {b : List WI} {s : WState} {r : Res},
    Run fs a s r → r.abrupt → Run fs (a ++ b) s r
  | [], b, s, r, h1, hr => by cases h1; exact absurd hr (by simp [Res.abrupt])
  | i :: a, b, s, r, h1, hr => by
    cases h1 with
    | consNormal hi hs => exact .consNormal hi (run_append_abrupt a hs hr)
    | consAbrupt hi hab => exact .consAbrupt hi hab

/-- `if` whose condition is false: continue with the condition popped. -/
theorem run_ite_false {fs : Funcs} {thn : List WI} {w : WState} {r : List Val} (hs : w.stack = .i32 0#32 :: r) :
    Run fs [.ite thn] w (.normal { w with stack := r }) :=
  .consNormal (.iteElse hs rfl) .nil

/-- `if (cond ≠ 0) { exit code }`. -/
theorem run_ite_exit {fs : Funcs} {w : WState} {r : List Val} {c : W32} {k : Nat}
    (hs : w.stack = .i32 c :: r) (hc : c ≠ 0#32) : Run fs [.ite [.exitTrap k]] w (.exit k) :=
  .consAbrupt (.iteThen hs hc (.consAbrupt .exitTrap trivial) .exit) trivial

/-- All instructions are non-control. -/
def allSimple (l : List WI) : Bool := l.all fun i => !i.isCtl

theorem allSimple_spec {l : List WI} (h : allSimple l = true) : ∀ i ∈ l, i.isCtl = false := by
  intro i hi
  have := List.all_eq_true.mp h i hi
  simpa using this

end Wasm
end WordDialect
