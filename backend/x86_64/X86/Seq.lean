import X86.Rel

/-!
# X86.Seq

Straight-line x86 execution (`xseq`) with its `XSteps` correctness, and the guard pattern
`jcc c (pc+2); exitTrap t` used for every trap check in the lowering.
-/

namespace WordDialect
namespace X86

open Reg

def Instr.straightX : Instr Nat → Bool
  | .jmp _ | .jcc _ _ | .call _ | .ret | .exitHalt | .exitTrap _ | .exitOvf => false
  | _ => true

def xseq : List (Instr Nat) → M → Out
  | [], m => .next m
  | i :: is, m =>
    match exec i m with
    | .next m' => xseq is m'
    | o => o

theorem exec_straightX_pc (i : Instr Nat) (m m' : M) (hi : i.straightX = true)
    (h : exec i m = .next m') : m'.pc = m.pc + 1 := by
  cases i <;> simp only [Instr.straightX] at hi <;> (try contradiction) <;>
    simp only [exec] at h <;> (try split at h) <;> (try split at h) <;> (try split at h) <;>
    (try split at h) <;> (try cases h) <;> simp [M.mov, M.arith, M.adv, M.setReg]

theorem xseq_steps {code : List (Instr Nat)} :
    ∀ {seg : List (Instr Nat)} {m m' : M},
      (∀ i ∈ seg, i.straightX = true) → XAt code m.pc seg → xseq seg m = .next m' →
      XSteps code m m' ∧ m'.pc = m.pc + seg.length := by
  intro seg
  induction seg with
  | nil => intro m m' _ _ h; simp [xseq] at h; subst h; exact ⟨.refl, by simp⟩
  | cons i is ih =>
    intro m m' hs ha h
    obtain ⟨hf, hrest⟩ := ha
    have hi : i.straightX = true := hs i (by simp)
    simp only [xseq] at h
    cases hx : exec i m with
    | next m1 =>
      rw [hx] at h
      have hpc := exec_straightX_pc i m m1 hi hx
      have hst : step code m = .next m1 := by rw [xstep_of_fetch hf, hx]
      obtain ⟨h1, h2⟩ := ih (fun j hj => hs j (by simp [hj])) (by rw [hpc]; exact hrest) h
      exact ⟨.cons hst h1, by rw [h2, hpc]; simp; omega⟩
    | halted _ => rw [hx] at h; simp at h
    | trapped _ => rw [hx] at h; simp at h
    | overflow => rw [hx] at h; simp at h
    | fault => rw [hx] at h; simp at h

theorem guard_pass {code : List (Instr Nat)} {pc : Nat} {m : M} {c : Cc} {t : Trap} {f : Flags}
    (hat : XAt code pc [.jcc c (pc + 2), .exitTrap t]) (hpc : m.pc = pc)
    (hf : m.flags = some f) (hc : c.holds f = true) :
    XSteps code m { m with pc := pc + 2 } := by
  obtain ⟨h1, _⟩ := hat
  apply XSteps.single
  rw [xstep_of_fetch (by rw [hpc]; exact h1)]
  simp [exec, hf, hc, hpc]

theorem guard_trap {code : List (Instr Nat)} {pc : Nat} {m : M} {c : Cc} {t : Trap} {f : Flags}
    (hat : XAt code pc [.jcc c (pc + 2), .exitTrap t]) (hpc : m.pc = pc)
    (hf : m.flags = some f) (hc : c.holds f = false) :
    XExec code m (.trapped t) := by
  obtain ⟨h1, h2, _⟩ := hat
  refine .next (m1 := { m with pc := pc + 1 }) ?_ (.trap ?_)
  · rw [xstep_of_fetch (by rw [hpc]; exact h1)]
    simp [exec, hf, hc, hpc, M.adv]
  · rw [xstep_of_fetch (m := { m with pc := pc + 1 }) h2]
    simp [exec]

end X86
end WordDialect
