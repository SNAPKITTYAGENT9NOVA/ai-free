import WordDialect.Invariants

/-!
# WordDialect.Exec

Execution semantics built on `step`:

* `Exec p s o`  — running `p` from `s` terminates with final outcome `o` (halted or trapped).
* `Steps p s s'` — `s'` is reached from `s` by finitely many non-terminal steps.
* `run`          — fuel-bounded executable interpreter, proved equivalent to `Exec`.

`Steps` composed with `Exec` is the tool used to prove translation correctness: a
translated fragment is shown to take the machine from one state to another with `Steps`,
and the rest of the program is handled by `Exec`.
-/

namespace WordDialect

inductive Exec {n : Nat} (p : Prog n) : State n → Outcome n → Prop where
  | halt  {s s' : State n} : step p s = .halted s' → Exec p s (.halted s')
  | trap  {s : State n} {t : Trap} : step p s = .trapped t → Exec p s (.trapped t)
  | next  {s s' : State n} {o : Outcome n} :
      step p s = .next s' → Exec p s' o → Exec p s o

inductive Steps {n : Nat} (p : Prog n) : State n → State n → Prop where
  | refl {s : State n} : Steps p s s
  | cons {s s' s'' : State n} : step p s = .next s' → Steps p s' s'' → Steps p s s''

namespace Steps

theorem single {n : Nat} {p : Prog n} {s s' : State n} (h : step p s = .next s') :
    Steps p s s' := .cons h .refl

theorem trans {n : Nat} {p : Prog n} {s s' s'' : State n}
    (h₁ : Steps p s s') (h₂ : Steps p s' s'') : Steps p s s'' := by
  induction h₁ with
  | refl => exact h₂
  | cons hs _ ih => exact .cons hs (ih h₂)

end Steps

theorem Exec.of_steps {n : Nat} {p : Prog n} {s s' : State n} {o : Outcome n}
    (hs : Steps p s s') (he : Exec p s' o) : Exec p s o := by
  induction hs with
  | refl => exact he
  | cons h _ ih => exact .next h (ih he)

/-- A final outcome is never `next`. -/
theorem Exec.terminal {n : Nat} {p : Prog n} {s : State n} {o : Outcome n}
    (h : Exec p s o) : ∀ s', o ≠ .next s' := by
  induction h with
  | halt _ => intro _ h; cases h
  | trap _ => intro _ h; cases h
  | next _ _ ih => exact ih

/-- The machine is deterministic: a program and an initial state fix the final outcome. -/
theorem Exec.deterministic {n : Nat} {p : Prog n} {s : State n} {o₁ o₂ : Outcome n}
    (h₁ : Exec p s o₁) (h₂ : Exec p s o₂) : o₁ = o₂ := by
  induction h₁ generalizing o₂ with
  | halt hs =>
    cases h₂ with
    | halt hs' => rw [hs] at hs'; cases hs'; rfl
    | trap hs' => rw [hs] at hs'; cases hs'
    | next hs' _ => rw [hs] at hs'; cases hs'
  | trap hs =>
    cases h₂ with
    | halt hs' => rw [hs] at hs'; cases hs'
    | trap hs' => rw [hs] at hs'; cases hs'; rfl
    | next hs' _ => rw [hs] at hs'; cases hs'
  | next hs _ ih =>
    cases h₂ with
    | halt hs' => rw [hs] at hs'; cases hs'
    | trap hs' => rw [hs] at hs'; cases hs'
    | next hs' h₂' => rw [hs] at hs'; cases hs'; exact ih h₂'

/-- Fuel-bounded interpreter. `none` means the fuel ran out before a final outcome. -/
def run {n : Nat} (p : Prog n) : Nat → State n → Option (Outcome n)
  | 0, _ => none
  | fuel + 1, s =>
    match step p s with
    | .next s' => run p fuel s'
    | o => some o

theorem run_sound {n : Nat} {p : Prog n} :
    ∀ {fuel : Nat} {s : State n} {o : Outcome n}, run p fuel s = some o → Exec p s o := by
  intro fuel
  induction fuel with
  | zero => intro s o h; simp [run] at h
  | succ f ih =>
    intro s o h
    simp only [run] at h
    cases hs : step p s with
    | next s' => rw [hs] at h; exact .next hs (ih h)
    | halted s' => rw [hs] at h; cases h; exact .halt hs
    | trapped t => rw [hs] at h; cases h; exact .trap hs

theorem run_complete {n : Nat} {p : Prog n} {s : State n} {o : Outcome n}
    (h : Exec p s o) : ∃ fuel, run p fuel s = some o := by
  induction h with
  | halt hs => exact ⟨1, by simp [run, hs]⟩
  | trap hs => exact ⟨1, by simp [run, hs]⟩
  | next hs _ ih =>
    obtain ⟨f, hf⟩ := ih
    exact ⟨f + 1, by simp [run, hs, hf]⟩

theorem run_mono {n : Nat} {p : Prog n} {o : Outcome n} :
    ∀ {fuel : Nat} {s : State n}, run p fuel s = some o → run p (fuel + 1) s = some o := by
  intro fuel
  induction fuel with
  | zero => intro s h; simp [run] at h
  | succ f ih =>
    intro s h
    simp only [run] at h ⊢
    cases hs : step p s with
    | next s' => rw [hs] at h; simp only []; exact ih h
    | halted s' => rw [hs] at h; exact h
    | trapped t => rw [hs] at h; exact h

theorem exec_iff_run {n : Nat} {p : Prog n} {s : State n} {o : Outcome n} :
    Exec p s o ↔ ∃ fuel, run p fuel s = some o :=
  ⟨run_complete, fun ⟨_, h⟩ => run_sound h⟩

/-! ## Control flow -/

theorem step_of_fetch {n : Nat} {p : Prog n} {s : State n} {i : Instr n}
    (h : p[s.pc]? = some i) : step p s = exec i s := by
  simp [step, h]

/-- Fetching outside the program traps; there is no fall-off-the-end behaviour. -/
theorem step_pc_oob {n : Nat} {p : Prog n} {s : State n} (h : p.length ≤ s.pc) :
    step p s = .trapped .badPc := by
  simp [step, List.getElem?_eq_none h]

theorem step_jmp {n : Nat} {p : Prog n} {s : State n} {t : Nat}
    (h : p[s.pc]? = some (.jmp t)) : step p s = .next { s with pc := t } := by
  rw [step_of_fetch h]; simp [exec]

theorem step_branch_taken {n : Nat} {p : Prog n} {s : State n} {t : Nat} {c : Word n}
    {d : List (Word n)} (h : p[s.pc]? = some (.branch t)) (hs : s.dstack = c :: d)
    (hc : Word.isTrue c = true) : step p s = .next { s with pc := t, dstack := d } := by
  rw [step_of_fetch h]; simp [exec, hs, hc]

theorem step_branch_fall {n : Nat} {p : Prog n} {s : State n} {t : Nat} {c : Word n}
    {d : List (Word n)} (h : p[s.pc]? = some (.branch t)) (hs : s.dstack = c :: d)
    (hc : Word.isTrue c = false) : step p s = .next { s with pc := s.pc + 1, dstack := d } := by
  rw [step_of_fetch h]; simp [exec, hs, hc, State.fall]

theorem step_call {n : Nat} {p : Prog n} {s : State n} {t : Nat}
    (h : p[s.pc]? = some (.call t)) :
    step p s = .next { s with pc := t, rstack := (s.pc + 1) :: s.rstack } := by
  rw [step_of_fetch h]; simp [exec]

theorem step_ret {n : Nat} {p : Prog n} {s : State n} {a : Nat} {rs : List Nat}
    (h : p[s.pc]? = some .ret) (hs : s.rstack = a :: rs) :
    step p s = .next { s with pc := a, rstack := rs } := by
  rw [step_of_fetch h]; simp [exec, hs]

theorem step_ret_empty {n : Nat} {p : Prog n} {s : State n}
    (h : p[s.pc]? = some .ret) (hs : s.rstack = []) :
    step p s = .trapped .returnUnderflow := by
  rw [step_of_fetch h]; simp [exec, hs]

/-- A call whose target is an immediate `ret` returns to the instruction after the call,
with every component of the state unchanged except the program counter. -/
theorem call_ret_roundtrip {n : Nat} {p : Prog n} {s : State n} {t : Nat}
    (hc : p[s.pc]? = some (.call t)) (hr : p[t]? = some .ret) :
    Steps p s { s with pc := s.pc + 1 } := by
  refine .cons (step_call hc) (.single ?_)
  exact step_ret (s := { s with pc := t, rstack := (s.pc + 1) :: s.rstack }) hr rfl

/-- Fetched instructions are unaffected by appending code after them. -/
theorem step_append_right {n : Nat} {p q : Prog n} {s : State n} {o : Outcome n}
    (hlt : s.pc < p.length) (h : step p s = o) : step (p ++ q) s = o := by
  simp [step, List.getElem?_append_left hlt] at h ⊢
  exact h

theorem Steps.append_right {n : Nat} {p q : Prog n} {s s' : State n}
    (hs : Steps p s s') (hb : ∀ x, Steps p s x → x.pc < p.length) :
    Steps (p ++ q) s s' := by
  induction hs with
  | refl => exact .refl
  | cons h _ ih =>
    refine .cons (step_append_right (hb _ .refl) h) (ih fun x hx => hb x (.cons h hx))

end WordDialect
