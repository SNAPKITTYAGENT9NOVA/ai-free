import Forth.OpCorrect

/-!
# Forth.Correct

Translation correctness of the Forth lowering.

`compile_correct`: whenever the Forth reference semantics derives a result `r` for block `b`
from state `st`, the machine, started at the block's address with a matching data stack and
memory, either
* reaches (via `Steps`) the end of the block's code with data stack and memory equal to the
  Forth result, or
* reaches a state whose next step traps with exactly the trap Forth reports.

`compileProgram_correct` lifts this to a whole program run from the initial machine state.
-/

namespace WordDialect
namespace Forth

open IR

/-- The machine realizes result `r`, ending at address `e` when `r` is a success. -/
def Reaches {n : Nat} (p : Prog n) (s : State n) (e : Nat) : Except Trap (FState n) → Prop
  | .ok st' => ∃ s', Steps p s s' ∧ s'.pc = e ∧ s'.dstack = st'.stack ∧ s'.mem = st'.mem
  | .error t => ∃ s1, Steps p s s1 ∧ step p s1 = .trapped t

theorem reaches_trans {n : Nat} {p : Prog n} {s s1 : State n} {e : Nat}
    {r : Except Trap (FState n)} (h1 : Steps p s s1) (h2 : Reaches p s1 e r) :
    Reaches p s e r := by
  cases r with
  | ok st' =>
    obtain ⟨s', hs, hpc, hd, hm⟩ := h2
    exact ⟨s', h1.trans hs, hpc, hd, hm⟩
  | error t =>
    obtain ⟨s2, hs, ht⟩ := h2
    exact ⟨s2, h1.trans hs, ht⟩

theorem reaches_cast {n : Nat} {p : Prog n} {s : State n} {e e' : Nat}
    {r : Except Trap (FState n)} (h : e = e') (hr : Reaches p s e r) : Reaches p s e' r := by
  subst h; exact hr

theorem size_op {n : Nat} (o : Op) (rest : Block) :
    (compile (.op o rest) : Frag n).size = (compileOp o : List (Instr n)).length + (compile rest : Frag n).size := rfl

theorem size_ite {n : Nat} (t e rest : Block) :
    (compile (.ite t e rest) : Frag n).size =
      ((compile e : Frag n).size + (compile t : Frag n).size + 2) + (compile rest : Frag n).size := rfl

theorem size_until {n : Nat} (body rest : Block) :
    (compile (.untilL body rest) : Frag n).size =
      ((compile body : Frag n).size + 2) + (compile rest : Frag n).size := rfl

theorem fstate_eta {n : Nat} (st : FState n) : (⟨st.stack, st.mem⟩ : FState n) = st := by
  cases st; rfl

theorem compile_correct {n : Nat} {b : Block} {st : FState n} {r : Except Trap (FState n)}
    (h : Run b st r) :
    ∀ (p : Prog n) (base : Nat) (s : State n),
      At p base ((compile b : Frag n).emit base) → s.pc = base →
      s.dstack = st.stack → s.mem = st.mem →
      Reaches p s (base + (compile b : Frag n).size) r := by
  induction h with
  | nil =>
    intro p base s _ hpc hd hm
    exact ⟨s, .refl, by simp [compile, Frag.empty, Frag.ofCode, hpc], hd, hm⟩
  | @opOk o rest st st' r hs _ ih =>
    intro p base s hat hpc hd hm
    have hat' := Frag.seq_at (by simpa [compile] using hat)
    have hcode : At p base (compileOp o : List (Instr n)) := by
      simpa [Frag.ofCode] using hat'.1
    have hrest : At p (base + (compileOp o : List (Instr n)).length)
        ((compile rest : Frag n).emit (base + (compileOp o : List (Instr n)).length)) := by
      simpa [Frag.ofCode] using hat'.2
    have hsem : o.sem ⟨s.dstack, s.mem⟩ = .ok st' := by
      rw [hd, hm, fstate_eta]; exact hs
    have hx := compileOp_ok o s st' hsem
    obtain ⟨hst, hpc'⟩ := execSeq_steps (compileOp_straight o) (by rw [hpc]; exact hcode) hx
    have := ih p (base + (compileOp o : List (Instr n)).length)
      { s with pc := s.pc + (compileOp o : List (Instr n)).length, dstack := st'.stack, mem := st'.mem } hrest
      (by simp [hpc]) rfl rfl
    refine reaches_cast ?_ (reaches_trans hst this)
    rw [size_op]; omega
  | @opErr o rest st t hs =>
    intro p base s hat hpc hd hm
    have hat' := Frag.seq_at (by simpa [compile] using hat)
    have hcode : At p base (compileOp o : List (Instr n)) := by
      simpa [Frag.ofCode] using hat'.1
    have hsem : o.sem ⟨s.dstack, s.mem⟩ = .error t := by
      rw [hd, hm, fstate_eta]; exact hs
    have hx := compileOp_err o s t hsem
    exact execSeq_trap (compileOp_straight o) (by rw [hpc]; exact hcode) hx
  | @iteUnder t e rest m =>
    intro p base s hat hpc hd hm
    have hat' := Frag.seq_at (by simpa [compile] using hat)
    obtain ⟨h1, _, _, _⟩ := ite_decode hat'.1
    refine ⟨s, .refl, ?_⟩
    rw [step_of_fetch (by rw [hpc]; exact h1)]
    exact exec_underflow _ s (by simp [hd, Instr.pops])
  | @iteTrue t e rest c d m st1 r hc _ _ iht ihr =>
    intro p base s hat hpc hd hm
    have hat' := Frag.seq_at (by simpa [compile] using hat)
    obtain ⟨_, _, _, ht⟩ := ite_decode hat'.1
    have h1 := ite_true_rule hat'.1 hpc hd hc
    have h2 := iht p _ { s with pc := base + 2 + (compile e : Frag n).size, dstack := d } ht
      rfl rfl hm
    obtain ⟨s2, hs2, hpc2, hd2, hm2⟩ := h2
    have h3 := ihr p (base + (Frag.ite (compile t) (compile e) : Frag n).size) s2
      (by simpa using hat'.2)
      (by rw [Frag.ite_size]; omega) hd2 hm2
    refine reaches_cast ?_ (reaches_trans (h1.trans hs2) h3)
    rw [size_ite, Frag.ite_size]; omega
  | @iteTrueErr t e rest c d m x hc _ iht =>
    intro p base s hat hpc hd hm
    have hat' := Frag.seq_at (by simpa [compile] using hat)
    obtain ⟨_, _, _, ht⟩ := ite_decode hat'.1
    have h1 := ite_true_rule hat'.1 hpc hd hc
    have h2 := iht p _ { s with pc := base + 2 + (compile e : Frag n).size, dstack := d } ht
      rfl rfl hm
    exact reaches_trans h1 h2
  | @iteFalse t e rest c d m st1 r hc _ _ ihe ihr =>
    intro p base s hat hpc hd hm
    have hat' := Frag.seq_at (by simpa [compile] using hat)
    obtain ⟨_, he, _, _⟩ := ite_decode hat'.1
    have h2 := ihe p (base + 1) { s with pc := base + 1, dstack := d } he rfl rfl hm
    obtain ⟨s2, hs2, hpc2, hd2, hm2⟩ := h2
    have h1 := ite_false_rule hat'.1 hpc hd hc hs2 hpc2
    have h3 := ihr p (base + (Frag.ite (compile t) (compile e) : Frag n).size)
      { s2 with pc := base + 2 + (compile e : Frag n).size + (compile t : Frag n).size }
      (by simpa using hat'.2)
      (by show base + 2 + (compile e : Frag n).size + (compile t : Frag n).size = _; rw [Frag.ite_size]; omega) hd2 hm2
    refine reaches_cast ?_ (reaches_trans h1 h3)
    rw [size_ite, Frag.ite_size]; omega
  | @iteFalseErr t e rest c d m x hc _ ihe =>
    intro p base s hat hpc hd hm
    have hat' := Frag.seq_at (by simpa [compile] using hat)
    obtain ⟨h0, he, _, _⟩ := ite_decode hat'.1
    have hfall := step_branch_fall (s := s) (by rw [hpc]; exact h0) hd hc
    rw [hpc] at hfall
    have h2 := ihe p (base + 1) { s with pc := base + 1, dstack := d } he rfl rfl hm
    exact reaches_trans (.single hfall) h2
  | @untilBodyErr body rest st x _ ihb =>
    intro p base s hat hpc hd hm
    have hat' := Frag.seq_at (by simpa [compile] using hat)
    obtain ⟨hb, _, _⟩ := until_decode hat'.1
    exact ihb p base s hb hpc hd hm
  | @untilUnder body rest st m _ ihb =>
    intro p base s hat hpc hd hm
    have hat' := Frag.seq_at (by simpa [compile] using hat)
    obtain ⟨hb, h2, _⟩ := until_decode hat'.1
    obtain ⟨s1, hs1, hpc1, hd1, hm1⟩ := ihb p base s hb hpc hd hm
    refine ⟨s1, hs1, ?_⟩
    rw [step_of_fetch (by rw [hpc1]; exact h2)]
    exact exec_underflow _ s1 (by simp [hd1, Instr.pops])
  | @untilExit body rest st c d m r _ hc _ ihb ihr =>
    intro p base s hat hpc hd hm
    have hat' := Frag.seq_at (by simpa [compile] using hat)
    obtain ⟨hb, _, _⟩ := until_decode hat'.1
    obtain ⟨s1, hs1, hpc1, hd1, hm1⟩ := ihb p base s hb hpc hd hm
    have h1 := until_exit_rule hat'.1 hpc1 hd1 hc
    have h3 := ihr p (base + (Frag.untilLoop (compile body) : Frag n).size)
      { s1 with pc := base + (compile body : Frag n).size + 2, dstack := d }
      (by simpa using hat'.2) (by show base + (compile body : Frag n).size + 2 = _; rw [Frag.until_size]; omega) rfl hm1
    refine reaches_cast ?_ (reaches_trans (hs1.trans h1) h3)
    rw [size_until, Frag.until_size]; omega
  | @untilAgain body rest st c d m r _ hc _ ihb ihl =>
    intro p base s hat hpc hd hm
    obtain ⟨s1, hs1, hpc1, hd1, hm1⟩ := ihb p base s
      (until_decode (Frag.seq_at (by simpa [compile] using hat)).1).1 hpc hd hm
    have h1 := until_again_rule (Frag.seq_at (by simpa [compile] using hat)).1 hpc1 hd1 hc
    have h3 := ihl p base { s1 with pc := base, dstack := d } hat rfl rfl hm1
    exact reaches_trans (hs1.trans h1) h3

/-- Whole-program correctness from the initial machine state (empty stacks, given memory). -/
theorem compileProgram_correct {n : Nat} {b : Block} {mem : Memory n}
    {r : Except Trap (FState n)} (h : Run b ⟨[], mem⟩ r) :
    match r with
    | .ok st' =>
        ∃ s', Exec (compileProgram b : Prog n) (State.init mem) (.halted s') ∧
          s'.dstack = st'.stack ∧ s'.mem = st'.mem
    | .error t => Exec (compileProgram b : Prog n) (State.init mem) (.trapped t) := by
  have hat : At (compileProgram b : Prog n) 0 ((compile b : Frag n).emit 0) := by
    have := at_embed ([] : Prog n) ((compile b : Frag n).emit 0) [.halt]
    simpa [compileProgram] using this
  have key := compile_correct h (compileProgram b) 0 (State.init mem) hat rfl rfl rfl
  cases r with
  | ok st' =>
    obtain ⟨s', hs, hpc, hd, hm⟩ := key
    have hfetch : (compileProgram b : Prog n)[s'.pc]? = some .halt := by
      rw [hpc]
      simp [compileProgram, List.getElem?_append_right, (compile b : Frag n).len]
    refine ⟨s', Exec.of_steps hs (.halt ?_), hd, hm⟩
    rw [step_of_fetch hfetch]; rfl
  | error t =>
    obtain ⟨s1, hs, ht⟩ := key
    exact Exec.of_steps hs (.trap ht)

end Forth
end WordDialect
