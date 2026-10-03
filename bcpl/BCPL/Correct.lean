import BCPL.ExprCorrect

/-!
# BCPL.Correct

Translation correctness of the BCPL lowering.

`compile_correct`: whenever the reference semantics derives result `r` for statement `s`
from memory `m`, the machine, started at the statement's address with memory `m`, either
* reaches (via `Steps`) the end of the statement's code with the data stack unchanged and
  memory equal to the BCPL result, or
* reaches a state whose next step traps with exactly the trap BCPL reports.

`compileProgram_correct` lifts this to a whole program run from the initial machine state.
-/

namespace WordDialect
namespace BCPL

open IR

theorem assignCode_ok {n : Nat} (addr : Var → Word n) (l : LVal) (e : Expr) (s : State n)
    (m' : Memory n) (h : assignSem addr l e s.mem = .ok m') :
    execSeq (assignCode addr l e) s =
      .next { s with pc := s.pc + (assignCode addr l e).length, mem := m' } := by
  cases l with
  | var x =>
    simp only [assignSem] at h
    split at h
    · cases h
    · rename_i v hv
      simp only [writeW] at h
      split at h
      · rename_i hw; cases h
        rw [assignCode, execSeq_append, compileE_ok addr e s v hv]
        simp [Outcome.andThen, execSeq, exec, State.fall, hw, Nat.add_assoc]
      · cases h
  | rv a =>
    simp only [assignSem] at h
    split at h
    · cases h
    · rename_i v hv
      split at h
      · cases h
      · rename_i a' ha
        simp only [writeW] at h
        split at h
        · rename_i hw; cases h
          rw [assignCode, execSeq_append, execSeq_append, compileE_ok addr e s v hv]
          simp only [Outcome.andThen]
          rw [compileE_ok addr a { s with pc := s.pc + (compileE addr e).length, dstack := v :: s.dstack } a' ha]
          simp [Outcome.andThen, execSeq, exec, State.fall, hw, Nat.add_assoc]
        · cases h

theorem assignCode_err {n : Nat} (addr : Var → Word n) (l : LVal) (e : Expr) (s : State n)
    (t : Trap) (h : assignSem addr l e s.mem = .error t) :
    execSeq (assignCode addr l e) s = .trapped t := by
  cases l with
  | var x =>
    simp only [assignSem] at h
    split at h
    · rename_i _ ht; cases h
      rw [assignCode, execSeq_append, compileE_err addr e s _ ht] <;> rfl
    · rename_i v hv
      simp only [writeW] at h
      split at h
      · cases h
      · rename_i hw; cases h
        rw [assignCode, execSeq_append, compileE_ok addr e s v hv]
        simp [Outcome.andThen, execSeq, exec, State.fall, hw]
  | rv a =>
    simp only [assignSem] at h
    split at h
    · rename_i _ ht; cases h
      rw [assignCode, execSeq_append, execSeq_append, compileE_err addr e s _ ht] <;> rfl
    · rename_i v hv
      split at h
      · rename_i _ ht; cases h
        rw [assignCode, execSeq_append, execSeq_append, compileE_ok addr e s v hv]
        simp only [Outcome.andThen]
        rw [compileE_err addr a { s with pc := s.pc + (compileE addr e).length, dstack := v :: s.dstack } _ ht] <;> rfl
      · rename_i a' ha
        simp only [writeW] at h
        split at h
        · cases h
        · rename_i hw; cases h
          rw [assignCode, execSeq_append, execSeq_append, compileE_ok addr e s v hv]
          simp only [Outcome.andThen]
          rw [compileE_ok addr a { s with pc := s.pc + (compileE addr e).length, dstack := v :: s.dstack } a' ha]
          simp [Outcome.andThen, execSeq, exec, State.fall, hw]
/-- The machine realizes result `r`, ending at address `e` with data stack `d` on success. -/
def Reaches {n : Nat} (p : Prog n) (s : State n) (d : List (Word n)) (e : Nat) :
    Except Trap (Memory n) → Prop
  | .ok m' => ∃ s', Steps p s s' ∧ s'.pc = e ∧ s'.dstack = d ∧ s'.mem = m'
  | .error t => ∃ s1, Steps p s s1 ∧ step p s1 = .trapped t

theorem reaches_trans {n : Nat} {p : Prog n} {s s1 : State n} {d : List (Word n)} {e : Nat}
    {r : Except Trap (Memory n)} (h1 : Steps p s s1) (h2 : Reaches p s1 d e r) :
    Reaches p s d e r := by
  cases r with
  | ok m' =>
    obtain ⟨s', hs, hpc, hd, hm⟩ := h2
    exact ⟨s', h1.trans hs, hpc, hd, hm⟩
  | error t =>
    obtain ⟨s2, hs, ht⟩ := h2
    exact ⟨s2, h1.trans hs, ht⟩

theorem reaches_cast {n : Nat} {p : Prog n} {s : State n} {d : List (Word n)} {e e' : Nat}
    {r : Except Trap (Memory n)} (h : e = e') (hr : Reaches p s d e r) : Reaches p s d e' r := by
  subst h; exact hr

theorem reaches_dstack {n : Nat} {p : Prog n} {s : State n} {d d' : List (Word n)} {e : Nat}
    {r : Except Trap (Memory n)} (h : d = d') (hr : Reaches p s d e r) : Reaches p s d' e r := by
  subst h; exact hr

theorem size_assign {n : Nat} (addr : Var → Word n) (l : LVal) (e : Expr) :
    (compile addr (.assign l e)).size = (assignCode addr l e).length := rfl

theorem size_seq {n : Nat} (addr : Var → Word n) (a b : Stmt) :
    (compile addr (.seq a b)).size = (compile addr a).size + (compile addr b).size := rfl

theorem size_test {n : Nat} (addr : Var → Word n) (c : Expr) (t e : Stmt) :
    (compile addr (.test c t e)).size =
      (compileE addr c).length + ((compile addr e).size + (compile addr t).size + 2) := rfl

theorem size_while {n : Nat} (addr : Var → Word n) (c : Expr) (body : Stmt) :
    (compile addr (.while c body)).size =
      (compileE addr c).length + (compile addr body).size + 3 := rfl

theorem compile_correct {n : Nat} {addr : Var → Word n} {s : Stmt} {m : Memory n}
    {r : Except Trap (Memory n)} (h : Exec addr s m r) :
    ∀ (p : Prog n) (base : Nat) (st : State n),
      At p base ((compile addr s).emit base) → st.pc = base → st.mem = m →
      Reaches p st st.dstack (base + (compile addr s).size) r := by
  induction h with
  | skip =>
    intro p base st _ hpc hm
    exact ⟨st, .refl, by simp [compile, Frag.empty, Frag.ofCode, hpc], rfl, hm⟩
  | @assign l e m r hr =>
    intro p base st hat hpc hm
    subst hr
    have hcode : At p base (assignCode addr l e) := by simpa [compile, Frag.ofCode] using hat
    cases hres : assignSem addr l e m with
    | ok m' =>
      have hx := assignCode_ok addr l e st m' (by rw [hm]; exact hres)
      obtain ⟨hst, hpc'⟩ :=
        execSeq_steps (assignCode_straight addr l e) (by rw [hpc]; exact hcode) hx
      exact ⟨_, hst, by rw [size_assign]; simp [hpc], rfl, rfl⟩
    | error t =>
      have hx := assignCode_err addr l e st t (by rw [hm]; exact hres)
      exact execSeq_trap (assignCode_straight addr l e) (by rw [hpc]; exact hcode) hx
  | @seqOk a b m m1 r _ _ iha ihb =>
    intro p base st hat hpc hm
    have hat' := Frag.seq_at (by simpa [compile] using hat)
    obtain ⟨s1, hs1, hpc1, hd1, hm1⟩ := iha p base st hat'.1 hpc hm
    have ih2 := ihb p (base + (compile addr a).size) s1 hat'.2 hpc1 hm1
    rw [hd1] at ih2
    refine reaches_cast ?_ (reaches_trans hs1 ih2)
    rw [size_seq]; omega
  | @seqErr a b m t _ iha =>
    intro p base st hat hpc hm
    have hat' := Frag.seq_at (by simpa [compile] using hat)
    exact iha p base st hat'.1 hpc hm
  | @testErr c t e m x hc =>
    intro p base st hat hpc hm
    have hat' := Frag.seq_at (by simpa [compile] using hat)
    have hcode : At p base (compileE addr c) := by simpa [Frag.ofCode] using hat'.1
    exact execSeq_trap (compileE_straight addr c) (by rw [hpc]; exact hcode)
      (compileE_err addr c st x (by rw [hm]; exact hc))
  | @testTrue c t e m v r hc ht _ iht =>
    intro p base st hat hpc hm
    have hat' := Frag.seq_at (by simpa [compile] using hat)
    have hcode : At p base (compileE addr c) := by simpa [Frag.ofCode] using hat'.1
    have hx := compileE_ok addr c st v (by rw [hm]; exact hc)
    obtain ⟨hst, hpc1⟩ := execSeq_steps (compileE_straight addr c) (by rw [hpc]; exact hcode) hx
    have hite : At p (base + (compileE addr c).length)
        ((Frag.ite (compile addr t) (compile addr e)).emit (base + (compileE addr c).length)) :=
      hat'.2
    obtain ⟨_, _, _, ht'⟩ := ite_decode hite
    have h1 := ite_true_rule hite
      (s := { st with pc := st.pc + (compileE addr c).length, dstack := v :: st.dstack })
      (by simp [hpc]) rfl ht
    have ih2 := iht p (base + (compileE addr c).length + 2 + (compile addr e).size)
      { st with pc := base + (compileE addr c).length + 2 + (compile addr e).size, dstack := st.dstack }
      ht' (by simp [hpc]) hm
    refine reaches_cast ?_ (reaches_trans (hst.trans (by simpa [hpc] using h1)) ih2)
    rw [size_test]; omega
  | @testFalse c t e m v r hc hf _ ihe =>
    intro p base st hat hpc hm
    have hat' := Frag.seq_at (by simpa [compile] using hat)
    have hcode : At p base (compileE addr c) := by simpa [Frag.ofCode] using hat'.1
    have hx := compileE_ok addr c st v (by rw [hm]; exact hc)
    obtain ⟨hst, hpc1⟩ := execSeq_steps (compileE_straight addr c) (by rw [hpc]; exact hcode) hx
    have hite : At p (base + (compileE addr c).length)
        ((Frag.ite (compile addr t) (compile addr e)).emit (base + (compileE addr c).length)) :=
      hat'.2
    obtain ⟨h0, he, _, _⟩ := ite_decode hite
    cases r with
    | ok m1 =>
      obtain ⟨s2, hs2, hpc2, hd2, hm2⟩ := ihe p (base + (compileE addr c).length + 1)
        { st with pc := base + (compileE addr c).length + 1, dstack := st.dstack }
        he (by simp [hpc]) hm
      have h1 := ite_false_rule hite
        (s := { st with pc := st.pc + (compileE addr c).length, dstack := v :: st.dstack })
        (by simp [hpc]) rfl hf
        (s1 := s2) (by simpa [hpc] using hs2) (by simpa using hpc2)
      refine ⟨_, hst.trans h1, ?_, hd2, hm2⟩
      show base + (compileE addr c).length + 2 + (compile addr e).size + (compile addr t).size = _
      rw [size_test]; omega
    | error t' =>
      obtain ⟨s2, hs2, ht2⟩ := ihe p (base + (compileE addr c).length + 1)
        { st with pc := base + (compileE addr c).length + 1, dstack := st.dstack }
        he (by simp [hpc]) hm
      have hfall := step_branch_fall
        (s := { st with pc := st.pc + (compileE addr c).length, dstack := v :: st.dstack })
        (by simp [hpc]; exact h0) rfl hf
      exact ⟨s2, hst.trans (.cons (by simpa [hpc] using hfall) hs2), ht2⟩
  | @whileErr c body m x hc =>
    intro p base st hat hpc hm
    obtain ⟨hc_at, _, _, _, _⟩ := while_decode (by simpa [compile] using hat)
    have hcode : At p base (compileE addr c) := by simpa [Frag.ofCode] using hc_at
    exact execSeq_trap (compileE_straight addr c) (by rw [hpc]; exact hcode)
      (compileE_err addr c st x (by rw [hm]; exact hc))
  | @whileExit c body m v hc hf =>
    intro p base st hat hpc hm
    have hat' : At p base ((Frag.whileLoop (Frag.ofCode (compileE addr c)) (compile addr body)).emit base) := by
      simpa [compile] using hat
    obtain ⟨hc_at, _, _, _, _⟩ := while_decode hat'
    have hcode : At p base (compileE addr c) := by simpa [Frag.ofCode] using hc_at
    have hx := compileE_ok addr c st v (by rw [hm]; exact hc)
    obtain ⟨hst, hpc1⟩ := execSeq_steps (compileE_straight addr c) (by rw [hpc]; exact hcode) hx
    have h1 := while_exit_rule hat'
      (s1 := { st with pc := st.pc + (compileE addr c).length, dstack := v :: st.dstack })
      (by simp [hpc, Frag.ofCode]) rfl hf
    refine ⟨_, hst.trans h1, ?_, rfl, hm⟩
    rw [size_while]; simp [Frag.ofCode]; omega
  | @whileBodyErr c body m v x hc ht _ ihb =>
    intro p base st hat hpc hm
    have hat' : At p base ((Frag.whileLoop (Frag.ofCode (compileE addr c)) (compile addr body)).emit base) := by
      simpa [compile] using hat
    obtain ⟨hc_at, _, _, hb_at, _⟩ := while_decode hat'
    have hcode : At p base (compileE addr c) := by simpa [Frag.ofCode] using hc_at
    have hx := compileE_ok addr c st v (by rw [hm]; exact hc)
    obtain ⟨hst, hpc1⟩ := execSeq_steps (compileE_straight addr c) (by rw [hpc]; exact hcode) hx
    have h1 := while_enter_rule hat'
      (s1 := { st with pc := st.pc + (compileE addr c).length, dstack := v :: st.dstack })
      (by simp [hpc, Frag.ofCode]) rfl ht
    have ih2 := ihb p (base + (Frag.ofCode (compileE addr c)).size + 2)
      { st with pc := base + (Frag.ofCode (compileE addr c)).size + 2, dstack := st.dstack }
      hb_at (by simp [hpc]) hm
    exact reaches_trans (hst.trans h1) ih2
  | @whileAgain c body m v m1 r hc ht _ _ ihb ihl =>
    intro p base st hat hpc hm
    have hat' : At p base ((Frag.whileLoop (Frag.ofCode (compileE addr c)) (compile addr body)).emit base) := by
      simpa [compile] using hat
    obtain ⟨hc_at, _, _, hb_at, _⟩ := while_decode hat'
    have hcode : At p base (compileE addr c) := by simpa [Frag.ofCode] using hc_at
    have hx := compileE_ok addr c st v (by rw [hm]; exact hc)
    obtain ⟨hst, hpc1⟩ := execSeq_steps (compileE_straight addr c) (by rw [hpc]; exact hcode) hx
    have h1 := while_enter_rule hat'
      (s1 := { st with pc := st.pc + (compileE addr c).length, dstack := v :: st.dstack })
      (by simp [hpc, Frag.ofCode]) rfl ht
    obtain ⟨s3, hs3, hpc3, hd3, hm3⟩ := ihb p (base + (Frag.ofCode (compileE addr c)).size + 2)
      { st with pc := base + (Frag.ofCode (compileE addr c)).size + 2, dstack := st.dstack }
      hb_at (by simp [hpc]) hm
    have h2 := while_back_rule hat' (s1 := s3) hpc3
    have hd3' : s3.dstack = st.dstack := hd3
    have ih4 : Reaches p { s3 with pc := base } st.dstack
        (base + (compile addr (Stmt.while c body)).size) r :=
      reaches_dstack hd3' (ihl p base { s3 with pc := base } hat rfl hm3)
    exact reaches_trans (((hst.trans h1).trans hs3).trans h2) ih4

/-- Whole-program correctness from the initial machine state (empty stacks, given memory). -/
theorem compileProgram_correct {n : Nat} {addr : Var → Word n} {s : Stmt} {mem : Memory n}
    {r : Except Trap (Memory n)} (h : Exec addr s mem r) :
    match r with
    | .ok m' =>
        ∃ s', WordDialect.Exec (compileProgram addr s) (State.init mem) (.halted s') ∧
          s'.dstack = [] ∧ s'.mem = m'
    | .error t => WordDialect.Exec (compileProgram addr s) (State.init mem) (.trapped t) := by
  have hat : At (compileProgram addr s) 0 ((compile addr s).emit 0) := by
    have := at_embed ([] : Prog n) ((compile addr s).emit 0) [.halt]
    simpa [compileProgram] using this
  have key := compile_correct h (compileProgram addr s) 0 (State.init mem) hat rfl rfl
  cases r with
  | ok m' =>
    obtain ⟨s', hs, hpc, hd, hm⟩ := key
    have hfetch : (compileProgram addr s)[s'.pc]? = some .halt := by
      rw [hpc]
      simp [compileProgram, (compile addr s).len]
    refine ⟨s', WordDialect.Exec.of_steps hs (.halt ?_), hd, hm⟩
    rw [step_of_fetch hfetch]; rfl
  | error t =>
    obtain ⟨s1, hs, ht⟩ := key
    exact WordDialect.Exec.of_steps hs (.trap ht)

end BCPL
end WordDialect
