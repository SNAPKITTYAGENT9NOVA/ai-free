import RV.Lower

/-!
# RV.Run

Run relations for the RISC-V model (`RSteps`, `RExec`), code placement (`RAt`), and the lemma
locating each IR instruction's lowered code inside `lowerProg`.
-/

namespace WordDialect
namespace RV

inductive RSteps (code : List (Instr Nat)) : M → M → Prop where
  | refl {m : M} : RSteps code m m
  | cons {m m1 m2 : M} : step code m = .next m1 → RSteps code m1 m2 → RSteps code m m2

theorem RSteps.single {code : List (Instr Nat)} {m m1 : M} (h : step code m = .next m1) :
    RSteps code m m1 := .cons h .refl

theorem RSteps.trans {code : List (Instr Nat)} {m m1 m2 : M}
    (h₁ : RSteps code m m1) (h₂ : RSteps code m1 m2) : RSteps code m m2 := by
  induction h₁ with
  | refl => exact h₂
  | cons hs _ ih => exact .cons hs (ih h₂)

/-- Running to a final outcome. -/
inductive RExec (code : List (Instr Nat)) : M → Out → Prop where
  | halt {m m' : M} : step code m = .halted m' → RExec code m (.halted m')
  | trap {m : M} {t : Trap} : step code m = .trapped t → RExec code m (.trapped t)
  | ovf {m : M} : step code m = .overflow → RExec code m .overflow
  | next {m m1 : M} {o : Out} : step code m = .next m1 → RExec code m1 o → RExec code m o

theorem RExec.of_steps {code : List (Instr Nat)} {m m1 : M} {o : Out}
    (hs : RSteps code m m1) (he : RExec code m1 o) : RExec code m o := by
  induction hs with
  | refl => exact he
  | cons h _ ih => exact .next h (ih he)

/-- `seg` occurs in `code` starting at index `pc`. -/
def RAt : List (Instr Nat) → Nat → List (Instr Nat) → Prop
  | _, _, [] => True
  | code, pc, i :: is => code[pc]? = some i ∧ RAt code (pc + 1) is

theorem rat_append {code : List (Instr Nat)} {pc : Nat} {c₁ c₂ : List (Instr Nat)} :
    RAt code pc (c₁ ++ c₂) ↔ RAt code pc c₁ ∧ RAt code (pc + c₁.length) c₂ := by
  induction c₁ generalizing pc with
  | nil => simp [RAt]
  | cons i is ih =>
    simp only [List.cons_append, RAt, ih, List.length_cons]
    constructor
    · rintro ⟨h, h1, h2⟩; refine ⟨⟨h, h1⟩, ?_⟩
      have e : pc + 1 + is.length = pc + (is.length + 1) := by omega
      rw [← e]; exact h2
    · rintro ⟨⟨h, h1⟩, h2⟩; refine ⟨h, h1, ?_⟩
      have e : pc + 1 + is.length = pc + (is.length + 1) := by omega
      rw [e]; exact h2

theorem fetch_cast {code : List (Instr Nat)} {i : Instr Nat} {a b : Nat}
    (h : code[a]? = some i) (hab : a = b) : code[b]? = some i := hab ▸ h

theorem rstep_of_fetch {code : List (Instr Nat)} {m : M} {i : Instr Nat}
    (h : code[m.pc]? = some i) : step code m = exec i m := by
  simp [step, h]

/-- Prefix sums: `offs` of a cons. -/
theorem offs_cons (i : WordDialect.Instr 64) (is : Prog 64) (k : Nat) :
    offs (i :: is) (k + 1) = isize i + offs is k := by
  simp [offs, List.take_succ_cons]

theorem offs_zero (p : Prog 64) : offs p 0 = 0 := by simp [offs]

theorem rat_embed (pre seg post : List (Instr Nat)) : RAt (pre ++ seg ++ post) pre.length seg := by
  induction seg generalizing pre with
  | nil => simp [RAt]
  | cons i is ih =>
    refine ⟨by simp, ?_⟩
    have := ih (pre ++ [i])
    simpa [List.append_assoc] using this

/-- Where the lowered code of IR instruction `k` sits: at index `pre.length + offs ps k`. -/
theorem lowerGo_at (L : Layout) (off : Nat → Nat) :
    ∀ (ps : Prog 64) (pre : List (Instr Nat)) (k : Nat) (i : WordDialect.Instr 64),
      ps[k]? = some i →
      RAt (pre ++ lowerGo L off pre.length ps) (pre.length + offs ps k)
        (lowerInstr L (pre.length + offs ps k) off i) := by
  intro ps
  induction ps with
  | nil => intro pre k i h; simp at h
  | cons j js ih =>
    intro pre k i h
    cases k with
    | zero =>
      simp at h; subst h
      simp only [offs_zero, Nat.add_zero, lowerGo]
      have := rat_embed pre (lowerInstr L pre.length off j) (lowerGo L off (pre.length + isize j) js)
      simpa [List.append_assoc] using this
    | succ k =>
      simp only [List.getElem?_cons_succ] at h
      have := ih (pre ++ lowerInstr L pre.length off j) k i h
      have hl : (pre ++ lowerInstr L pre.length off j).length = pre.length + isize j := by
        simp [lowerInstr_length]
      rw [hl] at this
      simp only [lowerGo, offs_cons]
      have e : pre.length + (isize j + offs js k) = pre.length + isize j + offs js k := by omega
      rw [e]
      simpa [List.append_assoc] using this

theorem lowerProg_at (L : Layout) (p : Prog 64) (k : Nat) (i : WordDialect.Instr 64)
    (h : p[k]? = some i) :
    RAt (lowerProg L p) (offs p k) (lowerInstr L (offs p k) (offs p) i) := by
  have := lowerGo_at L (offs p) p [] k i h
  simpa [lowerProg] using this

/-- The final stub (bad-pc trap) sits at `offs p p.length`. -/
theorem lowerGo_stub (L : Layout) (off : Nat → Nat) :
    ∀ (ps : Prog 64) (pre : List (Instr Nat)),
      RAt (pre ++ lowerGo L off pre.length ps) (pre.length + offs ps ps.length) [.exitTrap .badPc] := by
  intro ps
  induction ps with
  | nil =>
    intro pre
    simp only [lowerGo, List.length_nil, offs, List.take_nil, List.map_nil, List.sum_nil,
      Nat.add_zero]
    have := rat_embed pre [.exitTrap .badPc] []
    simpa using this
  | cons j js ih =>
    intro pre
    have := ih (pre ++ lowerInstr L pre.length off j)
    have hl : (pre ++ lowerInstr L pre.length off j).length = pre.length + isize j := by
      simp [lowerInstr_length]
    rw [hl] at this
    simp only [lowerGo, List.length_cons, offs_cons]
    have e : pre.length + (isize j + offs js js.length) = pre.length + isize j + offs js js.length := by omega
    rw [e]
    simpa [List.append_assoc] using this

theorem lowerProg_stub (L : Layout) (p : Prog 64) :
    RAt (lowerProg L p) (offs p p.length) [.exitTrap .badPc] := by
  have := lowerGo_stub L (offs p) p []
  simpa [lowerProg] using this

end RV
end WordDialect
