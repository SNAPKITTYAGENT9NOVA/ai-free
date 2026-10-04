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
  · refine hs.congr (by simp [xb, xa, M.adv, M.mov, M.setReg]) ?_ ?_ ?_ ?_ ?_ ?_ <;>
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

section Ovf

variable {c : Cfg} {p : Prog 64} {s : State 64} {x : M} {code : List (Instr Nat)} {L : Layout}
  {base : Nat}

theorem ovf_jcc_pass {pc : Nat} {m : M} {f : Flags} (h1 : code[pc]? = some (.jcc .ae (pc + 2)))
    (hpc : m.pc = pc) (hf : m.flags = some f) (hc : Cc.ae.holds f = true) :
    XSteps code m { m with pc := pc + 2 } := by
  apply XSteps.single
  rw [xstep_of_fetch (by rw [hpc]; exact h1)]
  simp [exec, hf, hc]

theorem ovf_jcc_trap {pc : Nat} {m : M} {f : Flags} (h1 : code[pc]? = some (.jcc .ae (pc + 2)))
    (h2 : code[pc + 1]? = some .exitOvf) (hpc : m.pc = pc) (hf : m.flags = some f)
    (hc : Cc.ae.holds f = false) : XExec code m .overflow := by
  refine .next (m1 := { m with pc := pc + 1 }) ?_ (.ovf ?_)
  · rw [xstep_of_fetch (by rw [hpc]; exact h1)]
    simp [exec, hf, hc, hpc, M.adv]
  · rw [xstep_of_fetch (m := { m with pc := pc + 1 }) h2]
    simp [exec]

/-- The data-stack guard's comparison, in terms of stack depth. -/
theorem ovfD_flags (hg : Geom c) (hs : Rel0 c p s x) (hLd : L.dLim = ofN (c.dBase + 8)) :
    Cc.ae.holds (subFlags (x.regs Reg.r15) L.dLim) =
      decide (c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd) := by
  have hcap := hs.capD
  have hdE := hg.dEnd_lt
  have h8 := hg.dBase_8
  rw [holds_ae, hs.r15, hLd, ule_ofN (by omega) (by omega)]
  by_cases h : c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd
  · simp [h]; omega
  · simp [h]; omega

theorem ovfD_run (hpc : x.pc = base) (hat : XAt code base (ovfD L base)) :
    ∃ xb : M, XSteps code x xb ∧ xb.pc = base + 2 ∧
      xb.flags = some (subFlags (x.regs Reg.r15) L.dLim) ∧ xb.mem = x.mem ∧
      (∀ r, r ≠ rax → xb.regs r = x.regs r) ∧
      code[base + 2]? = some (.jcc .ae (base + 2 + 2)) ∧ code[base + 2 + 1]? = some .exitOvf := by
  obtain ⟨h1, h2, h3, h4, _⟩ := hat
  let xa := x.mov rax L.dLim
  have hst1 : step code x = .next xa := by rw [xstep_of_fetch (by rw [hpc]; exact h1)]; rfl
  have hxa_pc : xa.pc = base + 1 := by simp [xa, M.mov, M.setReg, M.adv, hpc]
  let xb : M := { xa.adv with flags := some (subFlags (xa.regs r15) (xa.regs rax)) }
  have hst2 : step code xa = .next xb := by
    rw [xstep_of_fetch (m := xa) (by rw [hxa_pc]; exact h2)]; rfl
  refine ⟨xb, (XSteps.single hst1).trans (XSteps.single hst2), by simp [xb, M.adv, hxa_pc],
    by simp [xb, xa, M.mov, M.setReg, M.adv], by simp [xb, xa, M.adv, M.mov, M.setReg], ?_,
    fetch_cast h3 (by omega), fetch_cast h4 (by omega)⟩
  intro r hr; simp [xb, xa, M.adv, M.mov, M.setReg, hr]

/-- Room for one more data word: the guard falls through to `base + 4`. -/
theorem ovfD_pass (hg : Geom c) (hs : Rel0 c p s x) (hLd : L.dLim = ofN (c.dBase + 8))
    (hfit : c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd) (hpc : x.pc = base)
    (hat : XAt code base (ovfD L base)) :
    ∃ x1, XSteps code x x1 ∧ Rel0 c p s x1 ∧ x1.pc = base + 4 ∧ x1.mem = x.mem ∧
      (∀ r, r ≠ rax → x1.regs r = x.regs r) := by
  obtain ⟨xb, hsb, hpcb, hfb, hmb, hrb, hj, _⟩ := ovfD_run hpc hat
  have hholds : Cc.ae.holds (subFlags (x.regs Reg.r15) L.dLim) = true := by
    rw [ovfD_flags hg hs hLd]; simpa using hfit
  refine ⟨{ xb with pc := base + 2 + 2 }, hsb.trans (ovf_jcc_pass hj hpcb hfb hholds), ?_, rfl, hmb, hrb⟩
  refine hs.congr hmb ?_ ?_ ?_ ?_ ?_ ?_ <;> exact hrb _ (by decide)

/-- Data stack full: the guard exits with `overflow`. -/
theorem ovfD_trap (hg : Geom c) (hs : Rel0 c p s x) (hLd : L.dLim = ofN (c.dBase + 8))
    (h : ¬ c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd) (hpc : x.pc = base)
    (hat : XAt code base (ovfD L base)) : XExec code x .overflow := by
  obtain ⟨xb, hsb, hpcb, hfb, _, _, hj, he⟩ := ovfD_run hpc hat
  have hholds : Cc.ae.holds (subFlags (x.regs Reg.r15) L.dLim) = false := by
    rw [ovfD_flags hg hs hLd]; simpa using h
  exact XExec.of_steps hsb (ovf_jcc_trap hj he hpcb hfb hholds)

/-- The return-stack guard's comparison, in terms of return-stack depth. -/
theorem ovfR_flags (hg : Geom c) (hs : Rel0 c p s x) (hLr : L.rGap = ofN (8 * c.rcap - 16)) :
    Cc.ae.holds (subFlags (x.regs Reg.rsp) (x.regs Reg.r12 - L.rGap)) =
      decide (s.rstack.length + 2 ≤ c.rcap) := by
  have hcapR := hs.capR
  have hrc := hg.rcap_le
  have hsp := hg.sp0_lt
  have hge := hg.rcap_ge
  rw [holds_ae, hs.rsp, hs.r12, hLr, ofN_sub (by omega), ule_ofN (by omega) (by omega)]
  by_cases h : s.rstack.length + 2 ≤ c.rcap
  · simp [h]; omega
  · simp [h]; omega

theorem ovfR_run (hpc : x.pc = base) (hat : XAt code base (ovfR L base)) :
    ∃ xd : M, XSteps code x xd ∧ xd.pc = base + 4 ∧
      xd.flags = some (subFlags (x.regs Reg.rsp) (x.regs Reg.r12 - L.rGap)) ∧ xd.mem = x.mem ∧
      (∀ r, r ≠ rax → r ≠ rcx → xd.regs r = x.regs r) ∧
      code[base + 4]? = some (.jcc .ae (base + 4 + 2)) ∧ code[base + 4 + 1]? = some .exitOvf := by
  obtain ⟨h1, h2, h3, h4, h5, h6, _⟩ := hat
  let xa := x.mov rax (x.regs r12)
  have hst1 : step code x = .next xa := by rw [xstep_of_fetch (by rw [hpc]; exact h1)]; rfl
  have hxa_pc : xa.pc = base + 1 := by simp [xa, M.mov, M.setReg, M.adv, hpc]
  let xb := xa.mov rcx L.rGap
  have hst2 : step code xa = .next xb := by
    rw [xstep_of_fetch (m := xa) (by rw [hxa_pc]; exact h2)]; rfl
  have hxb_pc : xb.pc = base + 2 := by simp [xb, M.mov, M.setReg, M.adv, hxa_pc]
  let xc := xb.arith rax (xb.regs rax - xb.regs rcx)
  have hst3 : step code xb = .next xc := by
    rw [xstep_of_fetch (m := xb) (by rw [hxb_pc]; exact h3)]; rfl
  have hxc_pc : xc.pc = base + 3 := by simp [xc, M.arith, M.setReg, hxb_pc]
  let xd : M := { xc.adv with flags := some (subFlags (xc.regs rsp) (xc.regs rax)) }
  have hst4 : step code xc = .next xd := by
    rw [xstep_of_fetch (m := xc) (by rw [hxc_pc]; exact h4)]; rfl
  refine ⟨xd, (((XSteps.single hst1).trans (XSteps.single hst2)).trans (XSteps.single hst3)).trans
    (XSteps.single hst4), by simp [xd, M.adv, hxc_pc], ?_, ?_, ?_,
    fetch_cast h5 (by omega), fetch_cast h6 (by omega)⟩
  · simp [xd, xc, xb, xa, M.arith, M.mov, M.setReg, M.adv]
  · simp [xd, xc, xb, xa, M.arith, M.mov, M.setReg, M.adv]
  · intro r hr hr'; simp [xd, xc, xb, xa, M.arith, M.mov, M.setReg, M.adv, hr, hr']

/-- Room for one more return address: the guard falls through to `base + 6`. -/
theorem ovfR_pass (hg : Geom c) (hs : Rel0 c p s x) (hLr : L.rGap = ofN (8 * c.rcap - 16))
    (hfit : s.rstack.length + 2 ≤ c.rcap) (hpc : x.pc = base) (hat : XAt code base (ovfR L base)) :
    ∃ x1, XSteps code x x1 ∧ Rel0 c p s x1 ∧ x1.pc = base + 6 ∧ x1.mem = x.mem := by
  obtain ⟨xd, hsd, hpcd, hfd, hmd, hrd, hj, _⟩ := ovfR_run hpc hat
  have hholds : Cc.ae.holds (subFlags (x.regs Reg.rsp) (x.regs Reg.r12 - L.rGap)) = true := by
    rw [ovfR_flags hg hs hLr]; simpa using hfit
  refine ⟨{ xd with pc := base + 4 + 2 }, hsd.trans (ovf_jcc_pass hj hpcd hfd hholds), ?_, rfl, hmd⟩
  refine hs.congr hmd ?_ ?_ ?_ ?_ ?_ ?_ <;> exact hrd _ (by decide) (by decide)

/-- Return stack full: the guard exits with `overflow`. -/
theorem ovfR_trap (hg : Geom c) (hs : Rel0 c p s x) (hLr : L.rGap = ofN (8 * c.rcap - 16))
    (h : ¬ s.rstack.length + 2 ≤ c.rcap) (hpc : x.pc = base) (hat : XAt code base (ovfR L base)) :
    XExec code x .overflow := by
  obtain ⟨xd, hsd, hpcd, hfd, _, _, hj, he⟩ := ovfR_run hpc hat
  have hholds : Cc.ae.holds (subFlags (x.regs Reg.rsp) (x.regs Reg.r12 - L.rGap)) = false := by
    rw [ovfR_flags hg hs hLr]; simpa using h
  exact XExec.of_steps hsd (ovf_jcc_trap hj he hpcd hfd hholds)

end Ovf

end X86
end WordDialect
