import CM.SimCtl

/-!
# CM.SimAux

The auxiliary data stack (`tor fromr rfetch`). It lives in its own region `[aBase, aEnd)`, grows
downward from `aEnd`, and its pointer is `r9`, related by `AuxRel`; the model's `call`/`ret` never
touch it. This file has the step lemmas for `r9` (load the top, push, drop), the two guards
(`ovfA`: room for one more word, else exit 6; `emptyA`: nonempty, else trap `returnUnderflow`) and
the simulation theorems for the three instructions, for every outcome.
-/

namespace WordDialect
namespace CM

open Reg

section Steps

variable {c : Cfg} {p : Prog 32} {s : State 32} {x : M} {code : List (Instr Nat)}

/-- A write inside the auxiliary-stack region leaves the data-stack, register-file, IR-memory and
return-stack views unchanged. -/
theorem aux_region_write (hg : Geom c) (hs : Rel0 c p s x) {A : Nat} {v : W} {mem' : Memory 32}
    (hA1 : c.aBase ≤ A) (hA2 : A < c.aEnd) (hw : x.mem.write? (ofN A) v = some mem') :
    StackRel c mem' s.dstack ∧ RegRel c mem' s.regs ∧ MemRel c mem' s.mem ∧
      RsRel c p mem' s.rstack := by
  have haE := hg.aEnd_lt
  have hAlt : A < 2 ^ 32 := by omega
  have hcap := hs.capD
  have hdE := hg.dEnd_lt
  have hcapR := hs.capR
  have hrc := hg.rcap_le
  have hsp := hg.sp0_lt
  refine ⟨?_, ?_, ?_, ?_⟩
  · intro i w hi
    have hik : i < s.dstack.length := by
      by_cases hh : i < s.dstack.length
      · exact hh
      · rw [List.getElem?_eq_none (by omega)] at hi; simp at hi
    have hB : c.dEnd - 4 * s.dstack.length + 4 * i < 2 ^ 32 := by omega
    have hne : A ≠ c.dEnd - 4 * s.dstack.length + 4 * i := by
      rcases hg.dS_A with h | h <;> omega
    rw [read_write_nat hw hAlt hB]
    simp only [hne, ite_false]
    exact hs.stack i w hi
  · intro r hr
    have hrf := hg.rf_lt
    have hne : A ≠ c.rf + 4 * r := by rcases hg.dA_F with h | h <;> omega
    rw [read_write_nat hw hAlt (by omega)]
    simp only [hne, ite_false]
    exact hs.regs r hr
  · intro a ha
    have hmb := hg.mb_lt
    have hne : A ≠ c.mb + 4 * a := by rcases hg.dA_M with h | h <;> omega
    rw [read_write_nat hw hAlt (by omega)]
    simp only [hne, ite_false]
    exact hs.mem a ha
  · intro i a hi
    have hi' : i < s.rstack.length := by
      by_cases hh : i < s.rstack.length
      · exact hh
      · rw [List.getElem?_eq_none (by omega)] at hi; simp at hi
    have hkr : 4 * s.rstack.length ≤ c.sp0 := by omega
    have hB : c.sp0 - 4 * s.rstack.length + 4 * i < 2 ^ 32 := by omega
    have hne : A ≠ c.sp0 - 4 * s.rstack.length + 4 * i := by
      rcases hg.dA_K with h | h <;> omega
    rw [read_write_nat hw hAlt hB]
    simp only [hne, ite_false]
    exact hs.rs i a hi

/-- Load the auxiliary-stack top into a scratch register. -/
theorem ld_aux_step (hs : Rel0 c p s x) {a : W} {as : List W} (hd : s.astack = a :: as) {rd : Reg}
    (hrd : rd = r0 ∨ rd = r1 ∨ rd = r2 ∨ rd = r3)
    (hf : code[x.pc]? = some (.load rd Reg.r9 0)) :
    ∃ x', RSteps code x x' ∧ Rel0 c p s x' ∧ x'.pc = x.pc + 1 ∧ x'.regs rd = a ∧
      (∀ r, r ≠ rd → x'.regs r = x.regs r) ∧ x'.mem = x.mem := by
  have hread := hs.aux 0 a (by simp [hd])
  have e : exec (.load rd Reg.r9 0) x = .next (x.mov rd a) := by
    simp only [exec, M.ea, hs.r9]
    have h0 : ofN (c.aEnd - 4 * s.astack.length) + BitVec.ofInt 32 0 =
        ofN (c.aEnd - 4 * s.astack.length + 4 * 0) := by simp
    rw [h0, hread]
  refine ⟨x.mov rd a, RSteps.single (by rw [rstep_of_fetch hf, e]),
    mov_rel0 hs rd (scratch_ne rd hrd) a, ?_, ?_, ?_, ?_⟩
  · simp [M.mov, M.setReg, M.adv]
  · simp [M.mov, M.setReg, M.adv]
  · intro r hr; simp [M.mov, M.setReg, M.adv, hr]
  · simp [M.mov, M.setReg, M.adv]

/-- `addImm r9, 4` drops the auxiliary-stack top. -/
theorem aux_drop (hs : Rel0 c p s x) {a : W} {as : List W} (hd : s.astack = a :: as)
    (hf : code[x.pc]? = some (.addImm Reg.r9 4)) :
    ∃ x', RSteps code x x' ∧ Rel0 c p { s with astack := as } x' ∧ x'.pc = x.pc + 1 ∧
      (∀ r, r ≠ Reg.r9 → x'.regs r = x.regs r) := by
  have hcap := hs.capA
  rw [hd] at hcap
  simp only [List.length_cons] at hcap
  have hval : x.regs Reg.r9 + BitVec.ofInt 32 4 = ofN (c.aEnd - 4 * as.length) := by
    rw [hs.r9, show (4 : Int) = 4 * ((1 : Nat) : Int) by simp, ea_nat, hd]
    congr 1
    simp only [List.length_cons]
    omega
  refine ⟨x.arith Reg.r9 (ofN (c.aEnd - 4 * as.length)),
    RSteps.single (by rw [rstep_of_fetch hf]; simp only [exec, hval]), ?_, by simp [M.arith],
    by intro r hr; simp [M.arith, M.setReg, hr]⟩
  refine { r4 := ?_, r5 := ?_, r6 := ?_, r7 := ?_, r8 := ?_, r9 := ?_, stack := hs.stack,
           regs := hs.regs, mem := hs.mem, rs := hs.rs, aux := ?_, irvalid := hs.irvalid,
           xvalid := hs.xvalid, capD := hs.capD, capR := hs.capR, capA := ?_ }
  · simpa [M.arith, M.setReg] using hs.r4
  · simpa [M.arith, M.setReg] using hs.r5
  · simpa [M.arith, M.setReg] using hs.r6
  · simpa [M.arith, M.setReg] using hs.r7
  · simpa [M.arith, M.setReg] using hs.r8
  · simp [M.arith, M.setReg]
  · intro i w hi
    have hi' : as[i]? = some w := hi
    have h := hs.aux (i + 1) w (by rw [hd]; simpa using hi')
    rw [hd] at h
    simp only [List.length_cons] at h
    have e : c.aEnd - 4 * (as.length + 1) + 4 * (i + 1) = c.aEnd - 4 * as.length + 4 * i := by
      omega
    rw [e] at h
    exact h
  · show c.aBase + 4 * as.length ≤ c.aEnd
    omega

/-- `addImm r9, -4; store [r9], rs` pushes the value of `rs` onto the auxiliary stack. -/
theorem aux_push (hg : Geom c) (hs : Rel0 c p s x) (rs : Reg) (hrs : rs ≠ r9)
    (hfit : c.aBase + 4 * (s.astack.length + 1) ≤ c.aEnd)
    (hat : RAt code x.pc [.addImm Reg.r9 (-4), .store Reg.r9 0 rs]) :
    ∃ x', RSteps code x x' ∧
      Rel0 c p { s with astack := x.regs rs :: s.astack } x' ∧ x'.pc = x.pc + 2 ∧
      (∀ r, r ≠ r9 → x'.regs r = x.regs r) := by
  obtain ⟨h1, h2, _⟩ := hat
  have hcap := hs.capA
  have haE := hg.aEnd_lt
  have hA1 : c.aBase ≤ c.aEnd - 4 * (s.astack.length + 1) := by omega
  have hA2 : c.aEnd - 4 * (s.astack.length + 1) < c.aEnd := by omega
  have hAlt : c.aEnd - 4 * (s.astack.length + 1) < 2 ^ 32 := by omega
  have hval : x.regs Reg.r9 + BitVec.ofInt 32 (-4) = ofN (c.aEnd - 4 * (s.astack.length + 1)) := by
    rw [hs.r9, ea_neg8 (by omega)]
    congr 1
  obtain ⟨x1, hx1⟩ : ∃ x1, x1 = x.arith Reg.r9 (ofN (c.aEnd - 4 * (s.astack.length + 1))) :=
    ⟨_, rfl⟩
  have e1 : exec (.addImm Reg.r9 (-4)) x = .next x1 := by rw [hx1]; simp only [exec, hval]
  have hst1 : step code x = .next x1 := by rw [rstep_of_fetch h1, e1]
  have hbp1 : x1.regs Reg.r9 = ofN (c.aEnd - 4 * (s.astack.length + 1)) := by
    simp [hx1, M.arith, M.setReg]
  have hrsv : x1.regs rs = x.regs rs := by simp [hx1, M.arith, M.setReg, hrs]
  have hm1 : x1.mem = x.mem := by simp [hx1, M.arith, M.setReg]
  have hvalid := hs.xvalid.2.2.2.2 _ hA1 hA2
  obtain ⟨mem', hw⟩ : ∃ m', x.mem.write? (ofN (c.aEnd - 4 * (s.astack.length + 1))) (x.regs rs)
      = some m' := by simp [Memory.write?, hvalid]
  have e2 : exec (.store Reg.r9 0 rs) x1 = .next { x1.adv with mem := mem' } := by
    simp only [exec, M.ea, hbp1, hrsv, hm1]
    have h0 : ofN (c.aEnd - 4 * (s.astack.length + 1)) + BitVec.ofInt 32 0 =
        ofN (c.aEnd - 4 * (s.astack.length + 1)) := by simp
    rw [h0, hw]
  have hpc1 : x1.pc = x.pc + 1 := by simp [hx1, M.arith, M.setReg]
  have hst2 : step code x1 = .next { x1.adv with mem := mem' } := by
    rw [rstep_of_fetch (m := x1) (by rw [hpc1]; exact h2), e2]
  refine ⟨{ x1.adv with mem := mem' }, (RSteps.single hst1).trans (RSteps.single hst2), ?_,
    by simp [M.adv, hpc1], by intro r hr; simp [M.adv, hx1, M.arith, M.setReg, hr]⟩
  obtain ⟨hst, hrg, hmm, hrr⟩ := aux_region_write hg hs hA1 hA2 hw
  refine { r4 := ?_, r5 := ?_, r6 := ?_, r7 := ?_, r8 := ?_, r9 := ?_, stack := hst,
           regs := hrg, mem := hmm, rs := hrr, aux := ?_, irvalid := hs.irvalid, xvalid := ?_,
           capD := hs.capD, capR := hs.capR, capA := ?_ }
  · simpa [M.adv, hx1, M.arith, M.setReg] using hs.r4
  · simpa [M.adv, hx1, M.arith, M.setReg] using hs.r5
  · simpa [M.adv, hx1, M.arith, M.setReg] using hs.r6
  · simpa [M.adv, hx1, M.arith, M.setReg] using hs.r7
  · simpa [M.adv, hx1, M.arith, M.setReg] using hs.r8
  · simp [M.adv, hx1, M.arith, M.setReg]
  · intro i w hi
    show mem'.read? _ = some w
    simp only [List.length_cons]
    cases i with
    | zero =>
      simp at hi; subst hi
      rw [show c.aEnd - 4 * (s.astack.length + 1) + 4 * 0 = c.aEnd - 4 * (s.astack.length + 1) by
        omega, read_write_nat hw hAlt hAlt]
      simp
    | succ i =>
      simp only [List.getElem?_cons_succ] at hi
      have hik : i < s.astack.length := by
        have := (List.getElem?_eq_some_iff.mp hi).1; simpa using this
      have hB : c.aEnd - 4 * (s.astack.length + 1) + 4 * (i + 1) < 2 ^ 32 := by omega
      have hne : c.aEnd - 4 * (s.astack.length + 1) ≠
          c.aEnd - 4 * (s.astack.length + 1) + 4 * (i + 1) := by omega
      rw [read_write_nat hw hAlt hB]
      simp only [hne, ite_false]
      have e : c.aEnd - 4 * (s.astack.length + 1) + 4 * (i + 1) =
          c.aEnd - 4 * s.astack.length + 4 * i := by omega
      rw [e]; exact hs.aux i w hi
  · have := Memory.write?_valid hw
    show RegionsValid c mem'.valid
    rw [this]; exact hs.xvalid
  · simpa using hfit

end Steps

section Guards

variable {c : Cfg} {p : Prog 32} {s : State 32} {x : M} {code : List (Instr Nat)} {L : Layout}
  {base : Nat}

/-- The auxiliary-stack guard's comparison, in terms of its depth. -/
theorem ovfA_cond (hg : Geom c) (hs : Rel0 c p s x) (hLal : L.aLim = ofN (c.aBase + 4)) :
    Cond.eval .uge (x.regs Reg.r9) L.aLim =
      decide (c.aBase + 4 * (s.astack.length + 1) ≤ c.aEnd) := by
  have hcap := hs.capA
  have haE := hg.aEnd_lt
  have h8 := hg.aBase_8
  simp only [Cond.eval]
  rw [hs.r9, hLal, ule_ofN (by omega) (by omega)]
  by_cases h : c.aBase + 4 * (s.astack.length + 1) ≤ c.aEnd
  · simp [h]; omega
  · simp [h]; omega

theorem ovfA_run (hpc : x.pc = base) (hat : RAt code base (ovfA L base)) :
    ∃ xa : M, RSteps code x xa ∧ xa.pc = base + 1 ∧ xa.regs r0 = L.aLim ∧ xa.mem = x.mem ∧
      (∀ r, r ≠ r0 → xa.regs r = x.regs r) ∧
      code[base + 1]? = some (.bcc .uge r9 r0 (base + 1 + 2)) ∧ code[base + 1 + 1]? = some .exitOvf := by
  obtain ⟨h1, h2, h3, _⟩ := hat
  let xa := x.mov r0 L.aLim
  have hst1 : step code x = .next xa := by rw [rstep_of_fetch (by rw [hpc]; exact h1)]; rfl
  refine ⟨xa, RSteps.single hst1, by simp [xa, M.mov, M.setReg, M.adv, hpc],
    by simp [xa, M.mov, M.setReg, M.adv], by simp [xa, M.adv, M.mov, M.setReg], ?_,
    fetch_cast h2 (by omega), fetch_cast h3 (by omega)⟩
  intro r hr; simp [xa, M.adv, M.mov, M.setReg, hr]

/-- Room for one more auxiliary word: the guard falls through to `base + 3`. -/
theorem ovfA_pass (hg : Geom c) (hs : Rel0 c p s x) (hLal : L.aLim = ofN (c.aBase + 4))
    (hfit : c.aBase + 4 * (s.astack.length + 1) ≤ c.aEnd) (hpc : x.pc = base)
    (hat : RAt code base (ovfA L base)) :
    ∃ x1, RSteps code x x1 ∧ Rel0 c p s x1 ∧ x1.pc = base + 3 ∧ x1.mem = x.mem ∧
      (∀ r, r ≠ r0 → x1.regs r = x.regs r) := by
  obtain ⟨xa, hsa, hpca, hta, hma, hra, hj, _⟩ := ovfA_run hpc hat
  have hholds : Cond.eval .uge (xa.regs r9) (xa.regs r0) = true := by
    rw [hra r9 (by decide), hta, ovfA_cond hg hs hLal]; simpa using hfit
  refine ⟨{ xa with pc := base + 1 + 2 }, hsa.trans (ovf_pass hj hpca hholds), ?_, rfl, hma, hra⟩
  refine hs.congr hma ?_ ?_ ?_ ?_ ?_ ?_ <;> exact hra _ (by decide)

/-- Auxiliary stack full: the guard exits with `overflow`. -/
theorem ovfA_trap (hg : Geom c) (hs : Rel0 c p s x) (hLal : L.aLim = ofN (c.aBase + 4))
    (h : ¬ c.aBase + 4 * (s.astack.length + 1) ≤ c.aEnd) (hpc : x.pc = base)
    (hat : RAt code base (ovfA L base)) : RExec code x .overflow := by
  obtain ⟨xa, hsa, hpca, hta, _, hra, hj, he⟩ := ovfA_run hpc hat
  have hholds : Cond.eval .uge (xa.regs r9) (xa.regs r0) = false := by
    rw [hra r9 (by decide), hta, ovfA_cond hg hs hLal]; simpa using h
  exact RExec.of_steps hsa (ovf_trap hj he hpca hholds)

/-- The emptiness check's comparison: `r9 ≠ aEnd` exactly when the auxiliary stack is nonempty. -/
theorem emptyA_cond (hg : Geom c) (hs : Rel0 c p s x) (hLa : L.aEnd = ofN c.aEnd) :
    Cond.eval .ne (x.regs Reg.r9) L.aEnd = decide (s.astack ≠ []) := by
  have hcap := hs.capA
  have haE := hg.aEnd_lt
  simp only [Cond.eval]
  rw [hs.r9, hLa]
  by_cases h : s.astack = []
  · simp [h]
  · have hlen : 1 ≤ s.astack.length := by
      cases hh : s.astack with
      | nil => exact absurd hh h
      | cons a as => simp
    have hne : ofN (c.aEnd - 4 * s.astack.length) ≠ ofN c.aEnd := by
      intro e; have := ofN_inj (by omega) haE e; omega
    simp [hne, h]

theorem emptyA_run (hpc : x.pc = base) (hat : RAt code base (emptyA L base)) :
    ∃ xa : M, RSteps code x xa ∧ xa.pc = base + 1 ∧ xa.regs r0 = L.aEnd ∧ xa.mem = x.mem ∧
      (∀ r, r ≠ r0 → xa.regs r = x.regs r) ∧
      RAt code (base + 1) [.bcc .ne r9 r0 (base + 1 + 2), .exitTrap .returnUnderflow] := by
  obtain ⟨h1, h2, h3, _⟩ := hat
  let xa := x.mov r0 L.aEnd
  have hst1 : step code x = .next xa := by rw [rstep_of_fetch (by rw [hpc]; exact h1)]; rfl
  refine ⟨xa, RSteps.single hst1, by simp [xa, M.mov, M.setReg, M.adv, hpc],
    by simp [xa, M.mov, M.setReg, M.adv], by simp [xa, M.adv, M.mov, M.setReg], ?_,
    fetch_cast h2 (by omega), fetch_cast h3 (by omega), trivial⟩
  intro r hr; simp [xa, M.adv, M.mov, M.setReg, hr]

/-- Nonempty auxiliary stack: the check falls through to `base + 3`. -/
theorem emptyA_pass (hg : Geom c) (hs : Rel0 c p s x) (hLa : L.aEnd = ofN c.aEnd)
    (hne : s.astack ≠ []) (hpc : x.pc = base) (hat : RAt code base (emptyA L base)) :
    ∃ x1, RSteps code x x1 ∧ Rel0 c p s x1 ∧ x1.pc = base + 3 ∧ x1.mem = x.mem ∧
      (∀ r, r ≠ r0 → x1.regs r = x.regs r) := by
  obtain ⟨xa, hsa, hpca, hta, hma, hra, hj⟩ := emptyA_run hpc hat
  have hholds : Cond.eval .ne (xa.regs r9) (xa.regs r0) = true := by
    rw [hra r9 (by decide), hta, emptyA_cond hg hs hLa]; simpa using hne
  refine ⟨{ xa with pc := base + 1 + 2 }, hsa.trans (guard_pass hj hpca hholds), ?_, rfl, hma, hra⟩
  refine hs.congr hma ?_ ?_ ?_ ?_ ?_ ?_ <;> exact hra _ (by decide)

/-- Empty auxiliary stack: the check traps `returnUnderflow`. -/
theorem emptyA_trap (hg : Geom c) (hs : Rel0 c p s x) (hLa : L.aEnd = ofN c.aEnd)
    (he : s.astack = []) (hpc : x.pc = base) (hat : RAt code base (emptyA L base)) :
    RExec code x (.trapped .returnUnderflow) := by
  obtain ⟨xa, hsa, hpca, hta, _, hra, hj⟩ := emptyA_run hpc hat
  have hholds : Cond.eval .ne (xa.regs r9) (xa.regs r0) = false := by
    rw [hra r9 (by decide), hta, emptyA_cond hg hs hLa]; simp [he]
  exact RExec.of_steps hsa (guard_trap hj hpca hholds)

end Guards

section Ops

variable {c : Cfg} {p : Prog 32} {s : State 32} {x : M} {code : List (Instr Nat)}
  {L : Layout} {base : Nat} {off : Nat → Nat}

/-- Placement of the `tor` code. -/
theorem xat_tor (hat : RAt code base (lowerInstr L base off .tor)) :
    RAt code base (uf L 1 base) ∧ RAt code (base + 3) (ovfA L (base + 3)) ∧
      RAt code (base + 6) [.load r0 Reg.r4 0, .addImm Reg.r4 4, .addImm Reg.r9 (-4),
        .store Reg.r9 0 r0] := by
  have hat' : RAt code base (uf L 1 base ++ ovfA L (base + 3) ++
      [.load r0 Reg.r4 0, .addImm Reg.r4 4, .addImm Reg.r9 (-4), .store Reg.r9 0 r0]) := hat
  obtain ⟨hatuo, hatr⟩ := rat_append.mp hat'
  obtain ⟨hatuf, hato⟩ := rat_append.mp hatuo
  have hufl : (uf L 1 base).length = 3 := by simp [uf]
  rw [hufl] at hato
  have hl : (uf L 1 base ++ ovfA L (base + 3)).length = 6 := by simp [hufl, ovfA]
  rw [hl] at hatr
  exact ⟨hatuf, hato, hatr⟩

theorem sim_tor_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hLal : L.aLim = ofN (c.aBase + 4))
    (hs : Rel0 c p s x) (hpc : x.pc = base) (hat : RAt code base (lowerInstr L base off .tor))
    {a : W} {d : List W} (hd : s.dstack = a :: d)
    (hfit : c.aBase + 4 * (s.astack.length + 1) ≤ c.aEnd) :
    ∃ x', RSteps code x x' ∧ Rel0 c p { s with dstack := d, astack := a :: s.astack } x' ∧
      x'.pc = base + isize (.tor : WordDialect.Instr 32) := by
  obtain ⟨hatuf, hato, f0, f1, f2, f3, _⟩ := xat_tor hat
  have hk : 1 ≤ s.dstack.length := by simp [hd]
  obtain ⟨x1, hs1, hr1, hpc1, _, _⟩ := uf_pass hg hs hL (by decide) (by decide) hk hpc hatuf
  obtain ⟨x1', hs1', hr1', hpc1', _, _⟩ := ovfA_pass hg hr1 hLal hfit hpc1 hato
  obtain ⟨x2, hs2, hr2, hpc2, hv2, _, _⟩ := ld_step (code := code) hr1' (j := 0) (v := a)
    (by simp [hd]) (rd := r0) (by simp) (disp := 0) (by simp) (fetch_cast f0 (by omega))
  obtain ⟨x3, hs3, hr3, hpc3, ho3⟩ := adj_step (code := code) hg hr2 (n := 1) (by simp [hd])
    (δ := 4) (by simp) (fetch_cast f1 (by omega))
  have hax3 : x3.regs r0 = a := by rw [ho3 r0 (by decide), hv2]
  have e : s.dstack.drop 1 = d := by simp [hd]
  rw [e] at hr3
  obtain ⟨x4, hs4, hr4, hpc4, _⟩ := aux_push hg hr3 r0 (by decide) hfit
    ⟨fetch_cast f2 (by omega), fetch_cast f3 (by omega), trivial⟩
  rw [hax3] at hr4
  exact ⟨x4, (((hs1.trans hs1').trans hs2).trans hs3).trans hs4, hr4,
    by simp [isize, ufSize]; omega⟩

theorem sim_tor_ovf (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hLal : L.aLim = ofN (c.aBase + 4))
    (hs : Rel0 c p s x) (hpc : x.pc = base) (hat : RAt code base (lowerInstr L base off .tor))
    (hk : 1 ≤ s.dstack.length) (h : ¬ c.aBase + 4 * (s.astack.length + 1) ≤ c.aEnd) :
    RExec code x .overflow := by
  obtain ⟨hatuf, hato, _⟩ := xat_tor hat
  obtain ⟨x1, hs1, hr1, hpc1, _, _⟩ := uf_pass hg hs hL (by decide) (by decide) hk hpc hatuf
  exact RExec.of_steps hs1 (ovfA_trap hg hr1 hLal h hpc1 hato)

/-- Placement of `emptyA L base ++ ovfD L (base + 3) ++ rest`. -/
theorem xat_take {rest : List (Instr Nat)}
    (hat : RAt code base (emptyA L base ++ ovfD L (base + 3) ++ rest)) :
    RAt code base (emptyA L base) ∧ RAt code (base + 3) (ovfD L (base + 3)) ∧
      RAt code (base + 6) rest := by
  obtain ⟨hatuo, hatr⟩ := rat_append.mp hat
  obtain ⟨hate, hato⟩ := rat_append.mp hatuo
  have hel : (emptyA L base).length = 3 := rfl
  rw [hel] at hato
  have hl : (emptyA L base ++ ovfD L (base + 3)).length = 6 := rfl
  rw [hl] at hatr
  exact ⟨hate, hato, hatr⟩

theorem sim_fromr_ok (hg : Geom c) (hLa : L.aEnd = ofN c.aEnd) (hLd : L.dLim = ofN (c.dBase + 4))
    (hs : Rel0 c p s x) (hpc : x.pc = base) (hat : RAt code base (lowerInstr L base off .fromr))
    {a : W} {as : List W} (hd : s.astack = a :: as)
    (hfit : c.dBase + 4 * (s.dstack.length + 1) ≤ c.dEnd) :
    ∃ x', RSteps code x x' ∧ Rel0 c p { s with dstack := a :: s.dstack, astack := as } x' ∧
      x'.pc = base + isize (.fromr : WordDialect.Instr 32) := by
  obtain ⟨hate, hato, f0, f1, f2, f3, _⟩ := xat_take (L := L) (rest := [.load r0 Reg.r9 0,
    .addImm Reg.r9 4, .addImm Reg.r4 (-4), .store Reg.r4 0 r0]) hat
  obtain ⟨x1, hs1, hr1, hpc1, _, _⟩ := emptyA_pass hg hs hLa (by simp [hd]) hpc hate
  obtain ⟨x1', hs1', hr1', hpc1', _, _⟩ := ovfD_pass hg hr1 hLd hfit hpc1 hato
  obtain ⟨x2, hs2, hr2, hpc2, hv2, _, _⟩ := ld_aux_step (code := code) hr1' hd (rd := r0)
    (by simp) (fetch_cast f0 (by omega))
  obtain ⟨x3, hs3, hr3, hpc3, ho3⟩ := aux_drop (code := code) hr2 hd (fetch_cast f1 (by omega))
  have hax3 : x3.regs r0 = a := by rw [ho3 r0 (by decide), hv2]
  obtain ⟨x4, hs4, hr4, hpc4, _⟩ := push_pair hg hr3 r0 (by decide) hfit
    ⟨fetch_cast f2 (by omega), fetch_cast f3 (by omega), trivial⟩
  rw [hax3] at hr4
  exact ⟨x4, (((hs1.trans hs1').trans hs2).trans hs3).trans hs4, hr4, by simp [isize]; omega⟩

theorem sim_fromr_trap (hg : Geom c) (hLa : L.aEnd = ofN c.aEnd) (hs : Rel0 c p s x)
    (hpc : x.pc = base) (hat : RAt code base (lowerInstr L base off .fromr)) (he : s.astack = []) :
    RExec code x (.trapped .returnUnderflow) :=
  emptyA_trap hg hs hLa he hpc (xat_take (L := L) (rest := [.load r0 Reg.r9 0,
    .addImm Reg.r9 4, .addImm Reg.r4 (-4), .store Reg.r4 0 r0]) hat).1

theorem sim_fromr_ovf (hg : Geom c) (hLa : L.aEnd = ofN c.aEnd) (hLd : L.dLim = ofN (c.dBase + 4))
    (hs : Rel0 c p s x) (hpc : x.pc = base) (hat : RAt code base (lowerInstr L base off .fromr))
    (hne : s.astack ≠ []) (h : ¬ c.dBase + 4 * (s.dstack.length + 1) ≤ c.dEnd) :
    RExec code x .overflow := by
  obtain ⟨hate, hato, _⟩ := xat_take (L := L) (rest := [.load r0 Reg.r9 0,
    .addImm Reg.r9 4, .addImm Reg.r4 (-4), .store Reg.r4 0 r0]) hat
  obtain ⟨x1, hs1, hr1, hpc1, _, _⟩ := emptyA_pass hg hs hLa hne hpc hate
  exact RExec.of_steps hs1 (ovfD_trap hg hr1 hLd h hpc1 hato)

theorem sim_rfetch_ok (hg : Geom c) (hLa : L.aEnd = ofN c.aEnd) (hLd : L.dLim = ofN (c.dBase + 4))
    (hs : Rel0 c p s x) (hpc : x.pc = base) (hat : RAt code base (lowerInstr L base off .rfetch))
    {a : W} {as : List W} (hd : s.astack = a :: as)
    (hfit : c.dBase + 4 * (s.dstack.length + 1) ≤ c.dEnd) :
    ∃ x', RSteps code x x' ∧ Rel0 c p { s with dstack := a :: s.dstack } x' ∧
      x'.pc = base + isize (.rfetch : WordDialect.Instr 32) := by
  obtain ⟨hate, hato, f0, f1, f2, _⟩ := xat_take (L := L) (rest := [.load r0 Reg.r9 0,
    .addImm Reg.r4 (-4), .store Reg.r4 0 r0]) hat
  obtain ⟨x1, hs1, hr1, hpc1, _, _⟩ := emptyA_pass hg hs hLa (by simp [hd]) hpc hate
  obtain ⟨x1', hs1', hr1', hpc1', _, _⟩ := ovfD_pass hg hr1 hLd hfit hpc1 hato
  obtain ⟨x2, hs2, hr2, hpc2, hv2, _, _⟩ := ld_aux_step (code := code) hr1' hd (rd := r0)
    (by simp) (fetch_cast f0 (by omega))
  obtain ⟨x3, hs3, hr3, hpc3, _⟩ := push_pair hg hr2 r0 (by decide) hfit
    ⟨fetch_cast f1 (by omega), fetch_cast f2 (by omega), trivial⟩
  rw [hv2] at hr3
  exact ⟨x3, ((hs1.trans hs1').trans hs2).trans hs3, hr3, by simp [isize]; omega⟩

theorem sim_rfetch_trap (hg : Geom c) (hLa : L.aEnd = ofN c.aEnd) (hs : Rel0 c p s x)
    (hpc : x.pc = base) (hat : RAt code base (lowerInstr L base off .rfetch)) (he : s.astack = []) :
    RExec code x (.trapped .returnUnderflow) :=
  emptyA_trap hg hs hLa he hpc (xat_take (L := L) (rest := [.load r0 Reg.r9 0,
    .addImm Reg.r4 (-4), .store Reg.r4 0 r0]) hat).1

theorem sim_rfetch_ovf (hg : Geom c) (hLa : L.aEnd = ofN c.aEnd) (hLd : L.dLim = ofN (c.dBase + 4))
    (hs : Rel0 c p s x) (hpc : x.pc = base) (hat : RAt code base (lowerInstr L base off .rfetch))
    (hne : s.astack ≠ []) (h : ¬ c.dBase + 4 * (s.dstack.length + 1) ≤ c.dEnd) :
    RExec code x .overflow := by
  obtain ⟨hate, hato, _⟩ := xat_take (L := L) (rest := [.load r0 Reg.r9 0,
    .addImm Reg.r4 (-4), .store Reg.r4 0 r0]) hat
  obtain ⟨x1, hs1, hr1, hpc1, _, _⟩ := emptyA_pass hg hs hLa hne hpc hate
  exact RExec.of_steps hs1 (ovfD_trap hg hr1 hLd h hpc1 hato)

end Ops

end CM
end WordDialect
