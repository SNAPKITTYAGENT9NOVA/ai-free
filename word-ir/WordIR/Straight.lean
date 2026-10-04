import WordDialect

/-!
# WordIR.Straight

Universal Word IR is the Lean `Instr` stream defined in `WordDialect.Machine`. This module
provides the machinery every frontend uses to prove that a lowered *straight-line* code
sequence behaves as the source says:

* `isStraight i`  — `i` always continues at `pc + 1`.
* `At p pc code`  — `code` is located at address `pc` in program `p`.
* `execSeq code s` — a pure executor for a code sequence, defined with `exec` only.
* `execSeq_steps` / `execSeq_trap` — what `execSeq` computes is exactly what the machine
  does: a completed sequence is a `Steps` path; a trapping sequence is a `Steps` path
  followed by a trapping `step`.

Frontends therefore only need to prove equalities about `execSeq`, which is ordinary
equational reasoning.
-/

namespace WordDialect

def Instr.isStraight {n : Nat} : Instr n → Bool
  | .jmp _ | .branch _ | .call _ | .ret | .halt => false
  | _ => true

namespace IR

theorem exec_straight_pc {n : Nat} (i : Instr n) (s s' : State n)
    (hi : i.isStraight = true) (h : exec i s = .next s') : s'.pc = s.pc + 1 := by
  obtain ⟨pc, d, rs, as, regs, mem⟩ := s
  cases i <;> rcases d with _ | ⟨x, _ | ⟨y, _ | ⟨z, d⟩⟩⟩ <;>
    simp only [exec, State.fall, Instr.isStraight] at h hi <;>
    (try split at h) <;> (try split at h) <;> (try cases h) <;> simp_all

/-- `code` occurs in `p` starting at address `pc`. -/
def At {n : Nat} : Prog n → Nat → List (Instr n) → Prop
  | _, _, [] => True
  | p, pc, i :: is => p[pc]? = some i ∧ At p (pc + 1) is

theorem at_append {n : Nat} {p : Prog n} {pc : Nat} {c₁ c₂ : List (Instr n)} :
    At p pc (c₁ ++ c₂) ↔ At p pc c₁ ∧ At p (pc + c₁.length) c₂ := by
  induction c₁ generalizing pc with
  | nil => simp [At]
  | cons i is ih =>
    simp only [List.cons_append, At, ih, List.length_cons]
    constructor
    · rintro ⟨h, h1, h2⟩; refine ⟨⟨h, h1⟩, ?_⟩
      have e : pc + 1 + is.length = pc + (is.length + 1) := by omega
      rw [← e]; exact h2
    · rintro ⟨⟨h, h1⟩, h2⟩; refine ⟨h, h1, ?_⟩
      have e : pc + 1 + is.length = pc + (is.length + 1) := by omega
      rw [e]; exact h2

theorem at_embed {n : Nat} (pre code post : Prog n) : At (pre ++ code ++ post) pre.length code := by
  induction code generalizing pre with
  | nil => simp [At]
  | cons i is ih =>
    refine ⟨by simp, ?_⟩
    have := ih (pre ++ [i])
    simpa [List.append_assoc] using this

/-- Pure executor for a code sequence: runs each instruction with `exec`. Yields `next s'`
when the whole sequence completes, or the first trap / halt it meets. -/
def execSeq {n : Nat} : List (Instr n) → State n → Outcome n
  | [], s => .next s
  | i :: is, s =>
    match exec i s with
    | .next s' => execSeq is s'
    | o => o

/-- Continue with `f` if the outcome is `next`; otherwise keep the outcome. -/
def _root_.WordDialect.Outcome.andThen {n : Nat} : Outcome n → (State n → Outcome n) → Outcome n
  | .next s, f => f s
  | o, _ => o

theorem execSeq_append {n : Nat} (c₁ c₂ : List (Instr n)) (s : State n) :
    execSeq (c₁ ++ c₂) s = (execSeq c₁ s).andThen (execSeq c₂) := by
  induction c₁ generalizing s with
  | nil => simp [execSeq, Outcome.andThen]
  | cons i is ih =>
    simp only [List.cons_append, execSeq]
    cases h : exec i s <;> simp [ih, Outcome.andThen]

theorem execSeq_cons {n : Nat} (i : Instr n) (is : List (Instr n)) (s : State n) :
    execSeq (i :: is) s = (exec i s).andThen (execSeq is) := by
  simp only [execSeq]
  cases exec i s <;> simp [Outcome.andThen]

/-- A completed straight-line sequence is a `Steps` path and advances `pc` by its length. -/
theorem execSeq_steps {n : Nat} {p : Prog n} :
    ∀ {code : List (Instr n)} {s s' : State n},
      (∀ i ∈ code, i.isStraight = true) → At p s.pc code →
      execSeq code s = .next s' → Steps p s s' ∧ s'.pc = s.pc + code.length := by
  intro code
  induction code with
  | nil =>
    intro s s' _ _ h
    simp [execSeq] at h; subst h; exact ⟨.refl, by simp⟩
  | cons i is ih =>
    intro s s' hs ha h
    obtain ⟨hf, hrest⟩ := ha
    have hi : i.isStraight = true := hs i (by simp)
    simp only [execSeq] at h
    cases hx : exec i s with
    | next s1 =>
      rw [hx] at h
      have hpc := exec_straight_pc i s s1 hi hx
      have hst : step p s = .next s1 := by rw [step_of_fetch hf, hx]
      obtain ⟨h1, h2⟩ := ih (fun j hj => hs j (by simp [hj])) (by rw [hpc]; exact hrest) h
      exact ⟨.cons hst h1, by rw [h2, hpc]; simp; omega⟩
    | halted _ => rw [hx] at h; simp at h
    | trapped _ => rw [hx] at h; simp at h

/-- A trapping straight-line sequence is a `Steps` path followed by a trapping step. -/
theorem execSeq_trap {n : Nat} {p : Prog n} :
    ∀ {code : List (Instr n)} {s : State n} {t : Trap},
      (∀ i ∈ code, i.isStraight = true) → At p s.pc code →
      execSeq code s = .trapped t → ∃ s1, Steps p s s1 ∧ step p s1 = .trapped t := by
  intro code
  induction code with
  | nil => intro s t _ _ h; simp [execSeq] at h
  | cons i is ih =>
    intro s t hs ha h
    obtain ⟨hf, hrest⟩ := ha
    have hi : i.isStraight = true := hs i (by simp)
    simp only [execSeq] at h
    cases hx : exec i s with
    | next s1 =>
      rw [hx] at h
      have hpc := exec_straight_pc i s s1 hi hx
      have hst : step p s = .next s1 := by rw [step_of_fetch hf, hx]
      obtain ⟨s2, h1, h2⟩ := ih (fun j hj => hs j (by simp [hj])) (by rw [hpc]; exact hrest) h
      exact ⟨s2, .cons hst h1, h2⟩
    | halted _ => rw [hx] at h; simp at h
    | trapped t' =>
      rw [hx] at h; simp at h; subst h
      exact ⟨s, .refl, by rw [step_of_fetch hf, hx]⟩

end IR

end WordDialect
