import CM0.Rel

/-!
# CM0.Seq

Straight-line ARMv6-M execution (`rseq`) with its `RSteps` correctness, and the guard pattern
`bcc c a b (pc+2); exitTrap t` (or `exitOvf`) used for every check in the lowering.
-/

namespace WordDialect
namespace CM0

open Reg

def Instr.straightR : Instr Nat → Bool
  | .jmp _ | .bcc _ _ _ _ | .beqz _ _ | .bnez _ _ | .call _ | .ret | .exitHalt | .exitTrap _
  | .exitOvf => false
  | _ => true

def rseq : List (Instr Nat) → M → Out
  | [], m => .next m
  | i :: is, m =>
    match exec i m with
    | .next m' => rseq is m'
    | o => o

theorem exec_straightR_pc (i : Instr Nat) (m m' : M) (hi : i.straightR = true)
    (h : exec i m = .next m') : m'.pc = m.pc + 1 := by
  cases i <;> simp only [Instr.straightR] at hi <;> (try contradiction) <;>
    simp only [exec] at h <;> (try split at h) <;> (try split at h) <;> (try split at h) <;>
    (try split at h) <;> (try cases h) <;> simp [M.mov, M.arith, M.adv, M.setReg]

theorem rseq_steps {code : List (Instr Nat)} :
    ∀ {seg : List (Instr Nat)} {m m' : M},
      (∀ i ∈ seg, i.straightR = true) → RAt code m.pc seg → rseq seg m = .next m' →
      RSteps code m m' ∧ m'.pc = m.pc + seg.length := by
  intro seg
  induction seg with
  | nil => intro m m' _ _ h; simp [rseq] at h; subst h; exact ⟨.refl, by simp⟩
  | cons i is ih =>
    intro m m' hs ha h
    obtain ⟨hf, hrest⟩ := ha
    have hi : i.straightR = true := hs i (by simp)
    simp only [rseq] at h
    cases hx : exec i m with
    | next m1 =>
      rw [hx] at h
      have hpc := exec_straightR_pc i m m1 hi hx
      have hst : step code m = .next m1 := by rw [rstep_of_fetch hf, hx]
      obtain ⟨h1, h2⟩ := ih (fun j hj => hs j (by simp [hj])) (by rw [hpc]; exact hrest) h
      exact ⟨.cons hst h1, by rw [h2, hpc]; simp; omega⟩
    | halted _ => rw [hx] at h; simp at h
    | trapped _ => rw [hx] at h; simp at h
    | overflow => rw [hx] at h; simp at h
    | fault => rw [hx] at h; simp at h

theorem guard_pass {code : List (Instr Nat)} {pc : Nat} {m : M} {c : Cond} {a b : Reg} {t : Trap}
    (hat : RAt code pc [.bcc c a b (pc + 2), .exitTrap t]) (hpc : m.pc = pc)
    (hc : c.eval (m.regs a) (m.regs b) = true) :
    RSteps code m { m with pc := pc + 2 } := by
  obtain ⟨h1, _⟩ := hat
  apply RSteps.single
  rw [rstep_of_fetch (by rw [hpc]; exact h1)]
  simp [exec, hc]

theorem guard_trap {code : List (Instr Nat)} {pc : Nat} {m : M} {c : Cond} {a b : Reg} {t : Trap}
    (hat : RAt code pc [.bcc c a b (pc + 2), .exitTrap t]) (hpc : m.pc = pc)
    (hc : c.eval (m.regs a) (m.regs b) = false) :
    RExec code m (.trapped t) := by
  obtain ⟨h1, h2, _⟩ := hat
  refine .next (m1 := { m with pc := pc + 1 }) ?_ (.trap ?_)
  · rw [rstep_of_fetch (by rw [hpc]; exact h1)]
    simp [exec, hc, hpc, M.adv]
  · rw [rstep_of_fetch (m := { m with pc := pc + 1 }) h2]
    simp [exec]

/-- The overflow guard: the branch skips `exitOvf` when the condition holds. -/
theorem ovf_pass {code : List (Instr Nat)} {pc : Nat} {m : M} {c : Cond} {a b : Reg}
    (h1 : code[pc]? = some (.bcc c a b (pc + 2))) (hpc : m.pc = pc)
    (hc : c.eval (m.regs a) (m.regs b) = true) :
    RSteps code m { m with pc := pc + 2 } := by
  apply RSteps.single
  rw [rstep_of_fetch (by rw [hpc]; exact h1)]
  simp [exec, hc]

theorem ovf_trap {code : List (Instr Nat)} {pc : Nat} {m : M} {c : Cond} {a b : Reg}
    (h1 : code[pc]? = some (.bcc c a b (pc + 2))) (h2 : code[pc + 1]? = some .exitOvf)
    (hpc : m.pc = pc) (hc : c.eval (m.regs a) (m.regs b) = false) : RExec code m .overflow := by
  refine .next (m1 := { m with pc := pc + 1 }) ?_ (.ovf ?_)
  · rw [rstep_of_fetch (by rw [hpc]; exact h1)]
    simp [exec, hc, hpc, M.adv]
  · rw [rstep_of_fetch (m := { m with pc := pc + 1 }) h2]
    simp [exec]

end CM0
end WordDialect
