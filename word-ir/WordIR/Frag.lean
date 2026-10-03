import WordIR.Straight

/-!
# WordIR.Frag

Position-parametric code fragments. A `Frag n` is code whose absolute jump targets depend
on the address `b` at which it is placed; its *size* does not. Every frontend builds control
flow from the combinators here, so the control-flow proofs are done once.

Stack conventions:
* `ite t e`        — consumes a flag; nonzero runs `t`, zero runs `e`.
* `untilLoop body` — `body` leaves a flag; nonzero exits, zero repeats (Forth `BEGIN … UNTIL`).
* `whileLoop c b`  — `c` leaves a flag; nonzero runs `b` then re-tests, zero exits.

Each `*_rule` theorem states how the machine moves through the emitted code in terms of
`Steps`, assuming the emitted code is located at `b` in the program (`At`).
-/

namespace WordDialect
namespace IR

structure Frag (n : Nat) where
  size : Nat
  emit : Nat → List (Instr n)
  len  : ∀ b, (emit b).length = size

namespace Frag

def ofCode {n : Nat} (c : List (Instr n)) : Frag n := ⟨c.length, fun _ => c, fun _ => rfl⟩

def empty {n : Nat} : Frag n := ofCode []

def seq {n : Nat} (f g : Frag n) : Frag n where
  size := f.size + g.size
  emit := fun b => f.emit b ++ g.emit (b + f.size)
  len := fun b => by simp [f.len, g.len]

def ite {n : Nat} (t e : Frag n) : Frag n where
  size := e.size + t.size + 2
  emit := fun b =>
    [.branch (b + 2 + e.size)] ++ e.emit (b + 1) ++ [.jmp (b + 2 + e.size + t.size)] ++
      t.emit (b + 2 + e.size)
  len := fun b => by simp [e.len, t.len]; omega

def untilLoop {n : Nat} (body : Frag n) : Frag n where
  size := body.size + 2
  emit := fun b => body.emit b ++ [.branch (b + body.size + 2), .jmp b]
  len := fun b => by simp [body.len]

def whileLoop {n : Nat} (c k : Frag n) : Frag n where
  size := c.size + k.size + 3
  emit := fun b =>
    c.emit b ++ [.branch (b + c.size + 2), .jmp (b + c.size + k.size + 3)] ++
      k.emit (b + c.size + 2) ++ [.jmp b]
  len := fun b => by simp [c.len, k.len]; omega

theorem seq_size {n : Nat} (f g : Frag n) : (f.seq g).size = f.size + g.size := rfl
theorem ite_size {n : Nat} (t e : Frag n) : (Frag.ite t e).size = e.size + t.size + 2 := rfl
theorem until_size {n : Nat} (body : Frag n) : (Frag.untilLoop body).size = body.size + 2 := rfl
theorem while_size {n : Nat} (c k : Frag n) : (Frag.whileLoop c k).size = c.size + k.size + 3 := rfl
theorem ofCode_size {n : Nat} (c : List (Instr n)) : (Frag.ofCode c).size = c.length := rfl

theorem seq_at {n : Nat} {p : Prog n} {b : Nat} {f g : Frag n}
    (h : At p b ((f.seq g).emit b)) : At p b (f.emit b) ∧ At p (b + f.size) (g.emit (b + f.size)) := by
  have := at_append.mp (by simpa [seq] using h)
  simpa [f.len] using this

end Frag

/-! ## `ite` -/

section Ite
variable {n : Nat} {p : Prog n} {b : Nat} {t e : Frag n} {s : State n}

theorem ite_decode (h : At p b ((Frag.ite t e).emit b)) :
    p[b]? = some (.branch (b + 2 + e.size)) ∧
    At p (b + 1) (e.emit (b + 1)) ∧
    p[b + 1 + e.size]? = some (.jmp (b + 2 + e.size + t.size)) ∧
    At p (b + 2 + e.size) (t.emit (b + 2 + e.size)) := by
  simp only [Frag.ite, at_append, At, List.length_append, List.length_singleton, e.len] at h
  obtain ⟨⟨⟨⟨h1, _⟩, h2⟩, ⟨h3, _⟩⟩, h4⟩ := h
  refine ⟨h1, h2, ?_, ?_⟩
  · have e1 : b + 1 + e.size = b + 1 + e.size := rfl
    simpa [Nat.add_assoc] using h3
  · have e2 : b + (1 + e.size + 1) = b + 2 + e.size := by omega
    rw [e2] at h4; exact h4

/-- Flag true: run `t`. -/
theorem ite_true_rule (h : At p b ((Frag.ite t e).emit b)) (hpc : s.pc = b)
    {c : Word n} {d : List (Word n)} (hs : s.dstack = c :: d) (hc : Word.isTrue c = true) :
    Steps p s { s with pc := b + 2 + e.size, dstack := d } := by
  obtain ⟨h1, _, _, _⟩ := ite_decode h
  exact .single (step_branch_taken (by rw [hpc]; exact h1) hs hc)

/-- Flag false: run `e`, then jump over `t`. -/
theorem ite_false_rule (h : At p b ((Frag.ite t e).emit b)) (hpc : s.pc = b)
    {c : Word n} {d : List (Word n)} (hs : s.dstack = c :: d) (hc : Word.isTrue c = false)
    {s1 : State n} (hrun : Steps p { s with pc := b + 1, dstack := d } s1)
    (hend : s1.pc = b + 1 + e.size) :
    Steps p s { s1 with pc := b + 2 + e.size + t.size } := by
  obtain ⟨h1, _, h3, _⟩ := ite_decode h
  have hfall := step_branch_fall (s := s) (by rw [hpc]; exact h1) hs hc
  rw [hpc] at hfall
  have hj : step p s1 = .next { s1 with pc := b + 2 + e.size + t.size } :=
    step_jmp (by rw [hend]; exact h3)
  exact .cons hfall (hrun.trans (.single hj))

end Ite

/-! ## `untilLoop` -/

section Until
variable {n : Nat} {p : Prog n} {b : Nat} {body : Frag n}

theorem until_decode (h : At p b ((Frag.untilLoop body).emit b)) :
    At p b (body.emit b) ∧
    p[b + body.size]? = some (.branch (b + body.size + 2)) ∧
    p[b + body.size + 1]? = some (.jmp b) := by
  simp only [Frag.untilLoop, at_append, At, body.len] at h
  obtain ⟨h1, h2, h3⟩ := h
  exact ⟨h1, h2, h3.1⟩

/-- Flag true: leave the loop. `s1` is the state right after the body, flag on top. -/
theorem until_exit_rule (h : At p b ((Frag.untilLoop body).emit b))
    {s1 : State n} (hpc : s1.pc = b + body.size)
    {c : Word n} {d : List (Word n)} (hs : s1.dstack = c :: d) (hc : Word.isTrue c = true) :
    Steps p s1 { s1 with pc := b + body.size + 2, dstack := d } := by
  obtain ⟨_, h2, _⟩ := until_decode h
  exact .single (step_branch_taken (by rw [hpc]; exact h2) hs hc)

/-- Flag false: go around again. -/
theorem until_again_rule (h : At p b ((Frag.untilLoop body).emit b))
    {s1 : State n} (hpc : s1.pc = b + body.size)
    {c : Word n} {d : List (Word n)} (hs : s1.dstack = c :: d) (hc : Word.isTrue c = false) :
    Steps p s1 { s1 with pc := b, dstack := d } := by
  obtain ⟨_, h2, h3⟩ := until_decode h
  have hfall := step_branch_fall (s := s1) (by rw [hpc]; exact h2) hs hc
  have hj : step p { s1 with pc := s1.pc + 1, dstack := d } =
      .next { s1 with pc := b, dstack := d } :=
    step_jmp (s := { s1 with pc := s1.pc + 1, dstack := d }) (by simp only []; rw [hpc]; exact h3)
  exact .cons hfall (.single hj)

end Until

/-! ## `whileLoop` -/

section While
variable {n : Nat} {p : Prog n} {b : Nat} {c k : Frag n}

theorem while_decode (h : At p b ((Frag.whileLoop c k).emit b)) :
    At p b (c.emit b) ∧
    p[b + c.size]? = some (.branch (b + c.size + 2)) ∧
    p[b + c.size + 1]? = some (.jmp (b + c.size + k.size + 3)) ∧
    At p (b + c.size + 2) (k.emit (b + c.size + 2)) ∧
    p[b + c.size + 2 + k.size]? = some (.jmp b) := by
  simp only [Frag.whileLoop, at_append, At, List.length_append, List.length_cons,
    List.length_nil, c.len, k.len] at h
  obtain ⟨⟨⟨h1, h2, h3, _⟩, h4⟩, h5, _⟩ := h
  refine ⟨h1, h2, ?_, ?_, ?_⟩
  · simpa using h3
  · have e : b + (c.size + 2) = b + c.size + 2 := by omega
    simpa [e] using h4
  · have e : b + (c.size + 2 + k.size) = b + c.size + 2 + k.size := by omega
    simpa [e] using h5

/-- Condition true: enter the body. `s1` is the state right after the condition. -/
theorem while_enter_rule (h : At p b ((Frag.whileLoop c k).emit b))
    {s1 : State n} (hpc : s1.pc = b + c.size)
    {v : Word n} {d : List (Word n)} (hs : s1.dstack = v :: d) (hv : Word.isTrue v = true) :
    Steps p s1 { s1 with pc := b + c.size + 2, dstack := d } := by
  obtain ⟨_, h2, _⟩ := while_decode h
  exact .single (step_branch_taken (by rw [hpc]; exact h2) hs hv)

/-- Condition false: leave the loop. -/
theorem while_exit_rule (h : At p b ((Frag.whileLoop c k).emit b))
    {s1 : State n} (hpc : s1.pc = b + c.size)
    {v : Word n} {d : List (Word n)} (hs : s1.dstack = v :: d) (hv : Word.isTrue v = false) :
    Steps p s1 { s1 with pc := b + c.size + k.size + 3, dstack := d } := by
  obtain ⟨_, h2, h3, _⟩ := while_decode h
  have hfall := step_branch_fall (s := s1) (by rw [hpc]; exact h2) hs hv
  have hj : step p { s1 with pc := s1.pc + 1, dstack := d } =
      .next { s1 with pc := b + c.size + k.size + 3, dstack := d } :=
    step_jmp (s := { s1 with pc := s1.pc + 1, dstack := d }) (by simp only []; rw [hpc]; exact h3)
  exact .cons hfall (.single hj)

/-- After the body: jump back to re-test the condition. -/
theorem while_back_rule (h : At p b ((Frag.whileLoop c k).emit b))
    {s1 : State n} (hpc : s1.pc = b + c.size + 2 + k.size) :
    Steps p s1 { s1 with pc := b } := by
  obtain ⟨_, _, _, _, h5⟩ := while_decode h
  exact .single (step_jmp (by rw [hpc]; exact h5))

end While

end IR
end WordDialect
