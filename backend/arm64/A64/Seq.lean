import A64.Rel

/-!
# A64.Seq

Straight-line AArch64 execution (`aseq`) with its `ASteps` correctness, and the guard pattern
`jcc c (pc+2); exitTrap t` used for every trap check in the lowering.
-/

namespace WordDialect
namespace A64

open Reg

def Instr.straightA : Instr Nat → Bool
  | .jmp _ | .jcc _ _ | .call _ | .ret | .exitHalt | .exitTrap _ | .exitOvf => false
  | _ => true

def aseq : List (Instr Nat) → M → Out
  | [], m => .next m
  | i :: is, m =>
    match exec i m with
    | .next m' => aseq is m'
    | o => o

theorem exec_straightA_pc (i : Instr Nat) (m m' : M) (hi : i.straightA = true)
    (h : exec i m = .next m') : m'.pc = m.pc + 1 := by
  cases i <;> simp only [Instr.straightA] at hi <;> (try contradiction) <;>
    simp only [exec] at h <;> (try split at h) <;> (try split at h) <;> (try split at h) <;>
    (try split at h) <;> (try cases h) <;> simp [M.mov, M.arith, M.adv, M.setReg]

theorem aseq_steps {code : List (Instr Nat)} :
    ∀ {seg : List (Instr Nat)} {m m' : M},
      (∀ i ∈ seg, i.straightA = true) → AAt code m.pc seg → aseq seg m = .next m' →
      ASteps code m m' ∧ m'.pc = m.pc + seg.length := by
  intro seg
  induction seg with
  | nil => intro m m' _ _ h; simp [aseq] at h; subst h; exact ⟨.refl, by simp⟩
  | cons i is ih =>
    intro m m' hs ha h
    obtain ⟨hf, hrest⟩ := ha
    have hi : i.straightA = true := hs i (by simp)
    simp only [aseq] at h
    cases hx : exec i m with
    | next m1 =>
      rw [hx] at h
      have hpc := exec_straightA_pc i m m1 hi hx
      have hst : step code m = .next m1 := by rw [astep_of_fetch hf, hx]
      obtain ⟨h1, h2⟩ := ih (fun j hj => hs j (by simp [hj])) (by rw [hpc]; exact hrest) h
      exact ⟨.cons hst h1, by rw [h2, hpc]; simp; omega⟩
    | halted _ => rw [hx] at h; simp at h
    | trapped _ => rw [hx] at h; simp at h
    | overflow => rw [hx] at h; simp at h
    | fault => rw [hx] at h; simp at h

theorem guard_pass {code : List (Instr Nat)} {pc : Nat} {m : M} {c : Cc} {t : Trap} {f : Flags}
    (hat : AAt code pc [.jcc c (pc + 2), .exitTrap t]) (hpc : m.pc = pc)
    (hf : m.flags = some f) (hc : c.holds f = true) :
    ASteps code m { m with pc := pc + 2 } := by
  obtain ⟨h1, _⟩ := hat
  apply ASteps.single
  rw [astep_of_fetch (by rw [hpc]; exact h1)]
  simp [exec, hf, hc, hpc]

theorem guard_trap {code : List (Instr Nat)} {pc : Nat} {m : M} {c : Cc} {t : Trap} {f : Flags}
    (hat : AAt code pc [.jcc c (pc + 2), .exitTrap t]) (hpc : m.pc = pc)
    (hf : m.flags = some f) (hc : c.holds f = false) :
    AExec code m (.trapped t) := by
  obtain ⟨h1, h2, _⟩ := hat
  refine .next (m1 := { m with pc := pc + 1 }) ?_ (.trap ?_)
  · rw [astep_of_fetch (by rw [hpc]; exact h1)]
    simp [exec, hf, hc, hpc, M.adv]
  · rw [astep_of_fetch (m := { m with pc := pc + 1 }) h2]
    simp [exec]

end A64
end WordDialect
