import X86.Micro

/-!
# X86.Guard

The operand-count guard `uf`: with enough operands it falls through; otherwise it exits with
`stackUnderflow`, which is exactly the IR trap.
-/

namespace WordDialect
namespace X86

open Reg

theorem ufSize_pos {n : Nat} (hn : 0 < n) : ufSize n = 4 := by simp [ufSize]; omega

theorem uf_eq (L : Layout) {n : Nat} (hn : 0 < n) (base : Nat) :
    uf L n base = [.movImm rax (L.dEnd - BitVec.ofNat 64 (8 * n)), .cmp r15 rax, .jcc .be (base + 4),
      .exitTrap .stackUnderflow] := by
  simp [uf]; omega

theorem ule_ofN {a b : Nat} (ha : a < 2 ^ 64) (hb : b < 2 ^ 64) :
    (ofN a).ule (ofN b) = decide (a ≤ b) := by
  simp [BitVec.ule_eq_decide, ofN, BitVec.toNat_ofNat, Nat.mod_eq_of_lt ha, Nat.mod_eq_of_lt hb]

/-- The comparison inside the guard, in terms of stack depth. -/
theorem uf_flags {c : Cfg} {p : Prog 64} {s : State 64} {x : M} (hg : Geom c) (hs : Rel0 c p s x)
    {L : Layout} (hL : L.dEnd = ofN c.dEnd) {n : Nat} (hn : 0 < n) (hn3 : n ≤ 3) :
    ((subFlags (x.regs Reg.r15) (L.dEnd - BitVec.ofNat 64 (8 * n))) |> Cc.be.holds) =
      decide (n ≤ s.dstack.length) := by
  have hcap := hs.capD
  have hdE := hg.dEnd_lt
  have hge := hg.dEnd_ge
  rw [holds_be, hs.r15, hL, show BitVec.ofNat 64 (8 * n) = ofN (8 * n) from rfl,
    ofN_sub (by omega), ule_ofN (by omega) (by omega)]
  by_cases h : n ≤ s.dstack.length
  · simp [h]; omega
  · simp [h]; omega

/-- Enough operands: the guard falls through to `base + 4`, changing only scratch state. -/
theorem uf_pass {c : Cfg} {p : Prog 64} {s : State 64} {x : M} {code : List (Instr Nat)}
    {L : Layout} {base n : Nat} (hg : Geom c) (hs : Rel0 c p s x) (hL : L.dEnd = ofN c.dEnd)
    (hn : 0 < n) (hn3 : n ≤ 3) (hk : n ≤ s.dstack.length) (hpc : x.pc = base)
    (hat : XAt code base (uf L n base)) :
    ∃ x1, XSteps code x x1 ∧ Rel0 c p s x1 ∧ x1.pc = base + 4 ∧ x1.mem = x.mem ∧
      (∀ r, r ≠ rax → x1.regs r = x.regs r) := by
  rw [uf_eq L hn] at hat
  obtain ⟨h1, h2, h3, h4, _⟩ := hat
  let xa := x.mov rax (L.dEnd - BitVec.ofNat 64 (8 * n))
  have hst1 : step code x = .next xa := by rw [xstep_of_fetch (by rw [hpc]; exact h1)]; rfl
  have hxa_pc : xa.pc = base + 1 := by simp [xa, M.mov, M.setReg, M.adv, hpc]
  let xb : M := { xa.adv with flags := some (subFlags (xa.regs r15) (xa.regs rax)) }
  have hst2 : step code xa = .next xb := by
    rw [xstep_of_fetch (m := xa) (by rw [hxa_pc]; exact h2)]; rfl
  have hxb_pc : xb.pc = base + 2 := by simp [xb, M.adv, hxa_pc]
  have hr15 : xa.regs r15 = x.regs r15 := by simp [xa, M.mov, M.setReg, M.adv]
  have hflags : xb.flags = some (subFlags (x.regs r15) (L.dEnd - BitVec.ofNat 64 (8 * n))) := by
    simp [xb, hr15, xa, M.mov, M.setReg, M.adv]
  have hholds : Cc.be.holds (subFlags (x.regs r15) (L.dEnd - BitVec.ofNat 64 (8 * n))) = true := by
    have := uf_flags hg hs hL hn hn3
    simpa [hk] using this
  have hsteps := guard_pass (code := code) (pc := base + 2) (m := xb) (c := .be) (t := .stackUnderflow)
    (f := subFlags (x.regs r15) (L.dEnd - BitVec.ofNat 64 (8 * n)))
    (by simpa [XAt] using And.intro h3 h4) hxb_pc hflags hholds
  refine ⟨{ xb with pc := base + 2 + 2 }, ((XSteps.single hst1).trans (XSteps.single hst2)).trans
    (by simpa using hsteps), ?_, by simp, by simp [xb, xa, M.adv, M.mov, M.setReg], ?_⟩
  · refine hs.congr (by simp [xb, xa, M.adv, M.mov, M.setReg]) ?_ ?_ ?_ ?_ ?_ <;>
      simp [xb, xa, M.adv, M.mov, M.setReg]
  · intro r hr; simp [xb, xa, M.adv, M.mov, M.setReg, hr]

/-- Too few operands: the guard exits with `stackUnderflow`. -/
theorem uf_trap {c : Cfg} {p : Prog 64} {s : State 64} {x : M} {code : List (Instr Nat)}
    {L : Layout} {base n : Nat} (hg : Geom c) (hs : Rel0 c p s x) (hL : L.dEnd = ofN c.dEnd)
    (hn : 0 < n) (hn3 : n ≤ 3) (hk : s.dstack.length < n) (hpc : x.pc = base)
    (hat : XAt code base (uf L n base)) : XExec code x (.trapped .stackUnderflow) := by
  rw [uf_eq L hn] at hat
  obtain ⟨h1, h2, h3, h4, _⟩ := hat
  let xa := x.mov rax (L.dEnd - BitVec.ofNat 64 (8 * n))
  have hst1 : step code x = .next xa := by rw [xstep_of_fetch (by rw [hpc]; exact h1)]; rfl
  have hxa_pc : xa.pc = base + 1 := by simp [xa, M.mov, M.setReg, M.adv, hpc]
  let xb : M := { xa.adv with flags := some (subFlags (xa.regs r15) (xa.regs rax)) }
  have hst2 : step code xa = .next xb := by
    rw [xstep_of_fetch (m := xa) (by rw [hxa_pc]; exact h2)]; rfl
  have hxb_pc : xb.pc = base + 2 := by simp [xb, M.adv, hxa_pc]
  have hr15 : xa.regs r15 = x.regs r15 := by simp [xa, M.mov, M.setReg, M.adv]
  have hflags : xb.flags = some (subFlags (x.regs r15) (L.dEnd - BitVec.ofNat 64 (8 * n))) := by
    simp [xb, hr15, xa, M.mov, M.setReg, M.adv]
  have hholds : Cc.be.holds (subFlags (x.regs r15) (L.dEnd - BitVec.ofNat 64 (8 * n))) = false := by
    have := uf_flags hg hs hL hn hn3
    have h : ¬ n ≤ s.dstack.length := by omega
    simpa [h] using this
  exact (XExec.of_steps ((XSteps.single hst1).trans (XSteps.single hst2))
    (guard_trap (code := code) (pc := base + 2) (m := xb) (c := .be) (t := .stackUnderflow)
      (f := subFlags (x.regs r15) (L.dEnd - BitVec.ofNat 64 (8 * n)))
      (by simpa [XAt] using And.intro h3 h4) hxb_pc hflags hholds))

end X86
end WordDialect
