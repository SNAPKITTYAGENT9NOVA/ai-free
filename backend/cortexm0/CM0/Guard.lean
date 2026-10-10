import CM0.Micro

/-!
# CM0.Guard

The operand-count guard `uf` and the stack-capacity guards `ovfD`, `ovfR`: each loads a limit and
compares with one `bcc`. With enough operands (or room) it falls through; otherwise it exits with
`stackUnderflow` (exactly the IR trap) or `overflow`.
-/

namespace WordDialect
namespace CM0

open Reg

theorem ufSize_pos {n : Nat} (hn : 0 < n) : ufSize n = 3 := by simp [ufSize]; omega

theorem uf_eq (L : Layout) {n : Nat} (hn : 0 < n) (base : Nat) :
    uf L n base = [.movImm r0 (L.dEnd - BitVec.ofNat 32 (4 * n)), .bcc .ule r4 r0 (base + 3),
      .exitTrap .stackUnderflow] := by
  simp [uf]; omega

theorem ule_ofN {a b : Nat} (ha : a < 2 ^ 32) (hb : b < 2 ^ 32) :
    (ofN a).ule (ofN b) = decide (a ≤ b) := by
  simp [BitVec.ule_eq_decide, ofN, BitVec.toNat_ofNat, Nat.mod_eq_of_lt ha, Nat.mod_eq_of_lt hb]

/-- The guard's comparison, in terms of stack depth. -/
theorem uf_cond {c : Cfg} {p : Prog 32} {s : State 32} {x : M} (hg : Geom c) (hs : Rel0 c p s x)
    {L : Layout} (hL : L.dEnd = ofN c.dEnd) {n : Nat} (hn : 0 < n) (hn3 : n ≤ 3) :
    Cond.eval .ule (x.regs Reg.r4) (L.dEnd - BitVec.ofNat 32 (4 * n)) =
      decide (n ≤ s.dstack.length) := by
  have hcap := hs.capD
  have hdE := hg.dEnd_lt
  have hge := hg.dEnd_ge
  simp only [Cond.eval]
  rw [hs.r4, hL, show BitVec.ofNat 32 (4 * n) = ofN (4 * n) from rfl,
    ofN_sub (by omega), ule_ofN (by omega) (by omega)]
  by_cases h : n ≤ s.dstack.length
  · simp [h]; omega
  · simp [h]; omega

/-- Enough operands: the guard falls through to `base + 3`, changing only scratch state. -/
theorem uf_pass {c : Cfg} {p : Prog 32} {s : State 32} {x : M} {code : List (Instr Nat)}
    {L : Layout} {base n : Nat} (hg : Geom c) (hs : Rel0 c p s x) (hL : L.dEnd = ofN c.dEnd)
    (hn : 0 < n) (hn3 : n ≤ 3) (hk : n ≤ s.dstack.length) (hpc : x.pc = base)
    (hat : RAt code base (uf L n base)) :
    ∃ x1, RSteps code x x1 ∧ Rel0 c p s x1 ∧ x1.pc = base + 3 ∧ x1.mem = x.mem ∧
      (∀ r, r ≠ r0 → x1.regs r = x.regs r) := by
  rw [uf_eq L hn] at hat
  obtain ⟨h1, h2, h3, _⟩ := hat
  let xa := x.mov r0 (L.dEnd - BitVec.ofNat 32 (4 * n))
  have hst1 : step code x = .next xa := by rw [rstep_of_fetch (by rw [hpc]; exact h1)]; rfl
  have hxa_pc : xa.pc = base + 1 := by simp [xa, M.mov, M.setReg, M.adv, hpc]
  have hholds : Cond.eval .ule (xa.regs r4) (xa.regs r0) = true := by
    have := uf_cond hg hs hL hn hn3
    simpa [xa, M.mov, M.setReg, M.adv, hk] using this
  have hsteps := guard_pass (code := code) (pc := base + 1) (m := xa) (t := .stackUnderflow)
    (by simpa [RAt] using And.intro h2 h3) hxa_pc hholds
  refine ⟨{ xa with pc := base + 1 + 2 }, (RSteps.single hst1).trans hsteps, ?_, by simp,
    by simp [xa, M.adv, M.mov, M.setReg], ?_⟩
  · refine hs.congr (by simp [xa, M.adv, M.mov, M.setReg]) ?_ ?_ ?_ ?_ ?_ ?_ <;>
      simp [xa, M.adv, M.mov, M.setReg]
  · intro r hr; simp [xa, M.adv, M.mov, M.setReg, hr]

/-- Too few operands: the guard exits with `stackUnderflow`. -/
theorem uf_trap {c : Cfg} {p : Prog 32} {s : State 32} {x : M} {code : List (Instr Nat)}
    {L : Layout} {base n : Nat} (hg : Geom c) (hs : Rel0 c p s x) (hL : L.dEnd = ofN c.dEnd)
    (hn : 0 < n) (hn3 : n ≤ 3) (hk : s.dstack.length < n) (hpc : x.pc = base)
    (hat : RAt code base (uf L n base)) : RExec code x (.trapped .stackUnderflow) := by
  rw [uf_eq L hn] at hat
  obtain ⟨h1, h2, h3, _⟩ := hat
  let xa := x.mov r0 (L.dEnd - BitVec.ofNat 32 (4 * n))
  have hst1 : step code x = .next xa := by rw [rstep_of_fetch (by rw [hpc]; exact h1)]; rfl
  have hxa_pc : xa.pc = base + 1 := by simp [xa, M.mov, M.setReg, M.adv, hpc]
  have hholds : Cond.eval .ule (xa.regs r4) (xa.regs r0) = false := by
    have := uf_cond hg hs hL hn hn3
    have h : ¬ n ≤ s.dstack.length := by omega
    simpa [xa, M.mov, M.setReg, M.adv, h] using this
  exact RExec.of_steps (RSteps.single hst1)
    (guard_trap (code := code) (pc := base + 1) (m := xa) (t := .stackUnderflow)
      (by simpa [RAt] using And.intro h2 h3) hxa_pc hholds)

section Ovf

variable {c : Cfg} {p : Prog 32} {s : State 32} {x : M} {code : List (Instr Nat)} {L : Layout}
  {base : Nat}

/-- The data-stack guard's comparison, in terms of stack depth. -/
theorem ovfD_cond (hg : Geom c) (hs : Rel0 c p s x) (hLd : L.dLim = ofN (c.dBase + 4)) :
    Cond.eval .uge (x.regs Reg.r4) L.dLim =
      decide (c.dBase + 4 * (s.dstack.length + 1) ≤ c.dEnd) := by
  have hcap := hs.capD
  have hdE := hg.dEnd_lt
  have h8 := hg.dBase_8
  simp only [Cond.eval]
  rw [hs.r4, hLd, ule_ofN (by omega) (by omega)]
  by_cases h : c.dBase + 4 * (s.dstack.length + 1) ≤ c.dEnd
  · simp [h]; omega
  · simp [h]; omega

theorem ovfD_run (hpc : x.pc = base) (hat : RAt code base (ovfD L base)) :
    ∃ xa : M, RSteps code x xa ∧ xa.pc = base + 1 ∧ xa.regs r0 = L.dLim ∧ xa.mem = x.mem ∧
      (∀ r, r ≠ r0 → xa.regs r = x.regs r) ∧
      code[base + 1]? = some (.bcc .uge r4 r0 (base + 1 + 2)) ∧ code[base + 1 + 1]? = some .exitOvf := by
  obtain ⟨h1, h2, h3, _⟩ := hat
  let xa := x.mov r0 L.dLim
  have hst1 : step code x = .next xa := by rw [rstep_of_fetch (by rw [hpc]; exact h1)]; rfl
  refine ⟨xa, RSteps.single hst1, by simp [xa, M.mov, M.setReg, M.adv, hpc],
    by simp [xa, M.mov, M.setReg, M.adv], by simp [xa, M.adv, M.mov, M.setReg], ?_,
    fetch_cast h2 (by omega), fetch_cast h3 (by omega)⟩
  intro r hr; simp [xa, M.adv, M.mov, M.setReg, hr]

/-- Room for one more data word: the guard falls through to `base + 3`. -/
theorem ovfD_pass (hg : Geom c) (hs : Rel0 c p s x) (hLd : L.dLim = ofN (c.dBase + 4))
    (hfit : c.dBase + 4 * (s.dstack.length + 1) ≤ c.dEnd) (hpc : x.pc = base)
    (hat : RAt code base (ovfD L base)) :
    ∃ x1, RSteps code x x1 ∧ Rel0 c p s x1 ∧ x1.pc = base + 3 ∧ x1.mem = x.mem ∧
      (∀ r, r ≠ r0 → x1.regs r = x.regs r) := by
  obtain ⟨xa, hsa, hpca, hta, hma, hra, hj, _⟩ := ovfD_run hpc hat
  have hholds : Cond.eval .uge (xa.regs r4) (xa.regs r0) = true := by
    rw [hra r4 (by decide), hta, ovfD_cond hg hs hLd]; simpa using hfit
  refine ⟨{ xa with pc := base + 1 + 2 }, hsa.trans (ovf_pass hj hpca hholds), ?_, rfl, hma, hra⟩
  refine hs.congr hma ?_ ?_ ?_ ?_ ?_ ?_ <;> exact hra _ (by decide)

/-- Data stack full: the guard exits with `overflow`. -/
theorem ovfD_trap (hg : Geom c) (hs : Rel0 c p s x) (hLd : L.dLim = ofN (c.dBase + 4))
    (h : ¬ c.dBase + 4 * (s.dstack.length + 1) ≤ c.dEnd) (hpc : x.pc = base)
    (hat : RAt code base (ovfD L base)) : RExec code x .overflow := by
  obtain ⟨xa, hsa, hpca, hta, _, hra, hj, he⟩ := ovfD_run hpc hat
  have hholds : Cond.eval .uge (xa.regs r4) (xa.regs r0) = false := by
    rw [hra r4 (by decide), hta, ovfD_cond hg hs hLd]; simpa using h
  exact RExec.of_steps hsa (ovf_trap hj he hpca hholds)

/-- The return-stack guard's comparison, in terms of return-stack depth. -/
theorem ovfR_cond (hg : Geom c) (hs : Rel0 c p s x) (hLr : L.rGap = ofN (4 * c.rcap - 8)) :
    Cond.eval .uge (x.regs Reg.sp) (x.regs Reg.r9 - L.rGap) =
      decide (s.rstack.length + 2 ≤ c.rcap) := by
  have hcapR := hs.capR
  have hrc := hg.rcap_le
  have hsp := hg.sp0_lt
  have hge := hg.rcap_ge
  simp only [Cond.eval]
  rw [hs.sp, hs.r9, hLr, ofN_sub (by omega), ule_ofN (by omega) (by omega)]
  by_cases h : s.rstack.length + 2 ≤ c.rcap
  · simp [h]; omega
  · simp [h]; omega

theorem ovfR_run (hpc : x.pc = base) (hat : RAt code base (ovfR L base)) :
    ∃ xc : M, RSteps code x xc ∧ xc.pc = base + 3 ∧
      xc.regs r0 = x.regs r9 - L.rGap ∧ xc.mem = x.mem ∧
      (∀ r, r ≠ r0 → r ≠ r1 → xc.regs r = x.regs r) ∧
      code[base + 3]? = some (.bcc .uge sp r0 (base + 3 + 2)) ∧ code[base + 3 + 1]? = some .exitOvf := by
  obtain ⟨h1, h2, h3, h4, h5, _⟩ := hat
  let xa := x.mov r0 (x.regs r9)
  have hst1 : step code x = .next xa := by rw [rstep_of_fetch (by rw [hpc]; exact h1)]; rfl
  have hxa_pc : xa.pc = base + 1 := by simp [xa, M.mov, M.setReg, M.adv, hpc]
  let xb := xa.mov r1 L.rGap
  have hst2 : step code xa = .next xb := by
    rw [rstep_of_fetch (m := xa) (by rw [hxa_pc]; exact h2)]; rfl
  have hxb_pc : xb.pc = base + 2 := by simp [xb, M.mov, M.setReg, M.adv, hxa_pc]
  let xc := xb.arith r0 (xb.regs r0 - xb.regs r1)
  have hst3 : step code xb = .next xc := by
    rw [rstep_of_fetch (m := xb) (by rw [hxb_pc]; exact h3)]; rfl
  refine ⟨xc, ((RSteps.single hst1).trans (RSteps.single hst2)).trans (RSteps.single hst3),
    by simp [xc, M.arith, M.setReg, hxb_pc], ?_, ?_, ?_,
    fetch_cast h4 (by omega), fetch_cast h5 (by omega)⟩
  · simp [xc, xb, xa, M.arith, M.mov, M.setReg, M.adv]
  · simp [xc, xb, xa, M.arith, M.mov, M.setReg, M.adv]
  · intro r hr hr'; simp [xc, xb, xa, M.arith, M.mov, M.setReg, M.adv, hr, hr']

/-- Room for one more return address: the guard falls through to `base + 5`. -/
theorem ovfR_pass (hg : Geom c) (hs : Rel0 c p s x) (hLr : L.rGap = ofN (4 * c.rcap - 8))
    (hfit : s.rstack.length + 2 ≤ c.rcap) (hpc : x.pc = base) (hat : RAt code base (ovfR L base)) :
    ∃ x1, RSteps code x x1 ∧ Rel0 c p s x1 ∧ x1.pc = base + 5 ∧ x1.mem = x.mem := by
  obtain ⟨xc, hsc, hpcc, htc, hmc, hrc, hj, _⟩ := ovfR_run hpc hat
  have hholds : Cond.eval .uge (xc.regs sp) (xc.regs r0) = true := by
    rw [hrc sp (by decide) (by decide), htc, ovfR_cond hg hs hLr]; simpa using hfit
  refine ⟨{ xc with pc := base + 3 + 2 }, hsc.trans (ovf_pass hj hpcc hholds), ?_, rfl, hmc⟩
  refine hs.congr hmc ?_ ?_ ?_ ?_ ?_ ?_ <;> exact hrc _ (by decide) (by decide)

/-- Return stack full: the guard exits with `overflow`. -/
theorem ovfR_trap (hg : Geom c) (hs : Rel0 c p s x) (hLr : L.rGap = ofN (4 * c.rcap - 8))
    (h : ¬ s.rstack.length + 2 ≤ c.rcap) (hpc : x.pc = base) (hat : RAt code base (ovfR L base)) :
    RExec code x .overflow := by
  obtain ⟨xc, hsc, hpcc, htc, _, hrc, hj, he⟩ := ovfR_run hpc hat
  have hholds : Cond.eval .uge (xc.regs sp) (xc.regs r0) = false := by
    rw [hrc sp (by decide) (by decide), htc, ovfR_cond hg hs hLr]; simpa using h
  exact RExec.of_steps hsc (ovf_trap hj he hpcc hholds)

end Ovf

end CM0
end WordDialect
