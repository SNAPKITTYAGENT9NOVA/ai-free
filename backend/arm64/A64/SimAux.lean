import A64.SimCtl

/-!
# A64.SimAux

The auxiliary data stack (`tor fromr rfetch`). It lives in its own region `[aBase, aEnd)`, grows
downward from `aEnd`, and its pointer is `x24`, related by `AuxRel`; the model's `call`/`ret` never
touch it. This file has the step lemmas for `x24` (load the top, push, drop), the two guards
(`ovfA`: room for one more word, else exit 6; `emptyA`: nonempty, else trap `returnUnderflow`) and
the simulation theorems for the three instructions, for every outcome.
-/

namespace WordDialect
namespace A64

open Reg

section Steps

variable {c : Cfg} {p : Prog 64} {s : State 64} {x : M} {code : List (Instr Nat)}

/-- A write inside the auxiliary-stack region leaves the data-stack, register-file, IR-memory and
return-stack views unchanged. -/
theorem aux_region_write (hg : Geom c) (hs : Rel0 c p s x) {A : Nat} {v : W} {mem' : Memory 64}
    (hA1 : c.aBase ≤ A) (hA2 : A < c.aEnd) (hw : x.mem.write? (ofN A) v = some mem') :
    StackRel c mem' s.dstack ∧ RegRel c mem' s.regs ∧ MemRel c mem' s.mem ∧
      RsRel c p mem' s.rstack := by
  have haE := hg.aEnd_lt
  have hAlt : A < 2 ^ 64 := by omega
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
    have hB : c.dEnd - 8 * s.dstack.length + 8 * i < 2 ^ 64 := by omega
    have hne : A ≠ c.dEnd - 8 * s.dstack.length + 8 * i := by
      rcases hg.dS_A with h | h <;> omega
    rw [read_write_nat hw hAlt hB]
    simp only [hne, ite_false]
    exact hs.stack i w hi
  · intro r hr
    have hrf := hg.rf_lt
    have hne : A ≠ c.rf + 8 * r := by rcases hg.dA_F with h | h <;> omega
    rw [read_write_nat hw hAlt (by omega)]
    simp only [hne, ite_false]
    exact hs.regs r hr
  · intro a ha
    have hmb := hg.mb_lt
    have hne : A ≠ c.mb + 8 * a := by rcases hg.dA_M with h | h <;> omega
    rw [read_write_nat hw hAlt (by omega)]
    simp only [hne, ite_false]
    exact hs.mem a ha
  · intro i a hi
    have hi' : i < s.rstack.length := by
      by_cases hh : i < s.rstack.length
      · exact hh
      · rw [List.getElem?_eq_none (by omega)] at hi; simp at hi
    have hkr : 8 * s.rstack.length ≤ c.sp0 := by omega
    have hB : c.sp0 - 8 * s.rstack.length + 8 * i < 2 ^ 64 := by omega
    have hne : A ≠ c.sp0 - 8 * s.rstack.length + 8 * i := by
      rcases hg.dA_K with h | h <;> omega
    rw [read_write_nat hw hAlt hB]
    simp only [hne, ite_false]
    exact hs.rs i a hi

/-- Load the auxiliary-stack top into a scratch register. -/
theorem ld_aux_step (hs : Rel0 c p s x) {a : W} {as : List W} (hd : s.astack = a :: as) {rd : Reg}
    (hrd : rd = x9 ∨ rd = x10 ∨ rd = x11 ∨ rd = x12)
    (hf : code[x.pc]? = some (.load rd Reg.x24 0)) :
    ∃ x', ASteps code x x' ∧ Rel0 c p s x' ∧ x'.pc = x.pc + 1 ∧ x'.regs rd = a ∧
      (∀ r, r ≠ rd → x'.regs r = x.regs r) ∧ x'.mem = x.mem := by
  have hread := hs.aux 0 a (by simp [hd])
  have e : exec (.load rd Reg.x24 0) x = .next (x.mov rd a) := by
    simp only [exec, M.ea, hs.x24]
    have h0 : ofN (c.aEnd - 8 * s.astack.length) + BitVec.ofInt 64 0 =
        ofN (c.aEnd - 8 * s.astack.length + 8 * 0) := by simp
    rw [h0, hread]
  refine ⟨x.mov rd a, ASteps.single (by rw [astep_of_fetch hf, e]),
    mov_rel0 hs rd (scratch_ne rd hrd) a, ?_, ?_, ?_, ?_⟩
  · simp [M.mov, M.setReg, M.adv]
  · simp [M.mov, M.setReg, M.adv]
  · intro r hr; simp [M.mov, M.setReg, M.adv, hr]
  · simp [M.mov, M.setReg, M.adv]

/-- `addImm x24, 8` drops the auxiliary-stack top. -/
theorem aux_drop (hs : Rel0 c p s x) {a : W} {as : List W} (hd : s.astack = a :: as)
    (hf : code[x.pc]? = some (.addImm Reg.x24 8)) :
    ∃ x', ASteps code x x' ∧ Rel0 c p { s with astack := as } x' ∧ x'.pc = x.pc + 1 ∧
      (∀ r, r ≠ Reg.x24 → x'.regs r = x.regs r) := by
  have hcap := hs.capA
  rw [hd] at hcap
  simp only [List.length_cons] at hcap
  have hval : x.regs Reg.x24 + BitVec.ofInt 64 8 = ofN (c.aEnd - 8 * as.length) := by
    rw [hs.x24, show (8 : Int) = 8 * ((1 : Nat) : Int) by simp, ea_nat, hd]
    congr 1
    simp only [List.length_cons]
    omega
  refine ⟨x.arith Reg.x24 (ofN (c.aEnd - 8 * as.length)),
    ASteps.single (by rw [astep_of_fetch hf]; simp only [exec, hval]), ?_, by simp [M.arith],
    by intro r hr; simp [M.arith, M.setReg, hr]⟩
  refine { x19 := ?_, x20 := ?_, x21 := ?_, x22 := ?_, x23 := ?_, x24 := ?_, stack := hs.stack,
           regs := hs.regs, mem := hs.mem, rs := hs.rs, aux := ?_, irvalid := hs.irvalid,
           xvalid := hs.xvalid, capD := hs.capD, capR := hs.capR, capA := ?_ }
  · simpa [M.arith, M.setReg] using hs.x19
  · simpa [M.arith, M.setReg] using hs.x20
  · simpa [M.arith, M.setReg] using hs.x21
  · simpa [M.arith, M.setReg] using hs.x22
  · simpa [M.arith, M.setReg] using hs.x23
  · simp [M.arith, M.setReg]
  · intro i w hi
    have hi' : as[i]? = some w := hi
    have h := hs.aux (i + 1) w (by rw [hd]; simpa using hi')
    rw [hd] at h
    simp only [List.length_cons] at h
    have e : c.aEnd - 8 * (as.length + 1) + 8 * (i + 1) = c.aEnd - 8 * as.length + 8 * i := by
      omega
    rw [e] at h
    exact h
  · show c.aBase + 8 * as.length ≤ c.aEnd
    omega

/-- `addImm x24, -8; store [x24], rs` pushes the value of `rs` onto the auxiliary stack. -/
theorem aux_push (hg : Geom c) (hs : Rel0 c p s x) (rs : Reg) (hrs : rs ≠ x24)
    (hfit : c.aBase + 8 * (s.astack.length + 1) ≤ c.aEnd)
    (hat : AAt code x.pc [.addImm Reg.x24 (-8), .store Reg.x24 0 rs]) :
    ∃ x', ASteps code x x' ∧
      Rel0 c p { s with astack := x.regs rs :: s.astack } x' ∧ x'.pc = x.pc + 2 ∧
      (∀ r, r ≠ x24 → x'.regs r = x.regs r) := by
  obtain ⟨h1, h2, _⟩ := hat
  have hcap := hs.capA
  have haE := hg.aEnd_lt
  have hA1 : c.aBase ≤ c.aEnd - 8 * (s.astack.length + 1) := by omega
  have hA2 : c.aEnd - 8 * (s.astack.length + 1) < c.aEnd := by omega
  have hAlt : c.aEnd - 8 * (s.astack.length + 1) < 2 ^ 64 := by omega
  have hval : x.regs Reg.x24 + BitVec.ofInt 64 (-8) = ofN (c.aEnd - 8 * (s.astack.length + 1)) := by
    rw [hs.x24, ea_neg8 (by omega)]
    congr 1
  obtain ⟨x1, hx1⟩ : ∃ x1, x1 = x.arith Reg.x24 (ofN (c.aEnd - 8 * (s.astack.length + 1))) :=
    ⟨_, rfl⟩
  have e1 : exec (.addImm Reg.x24 (-8)) x = .next x1 := by rw [hx1]; simp only [exec, hval]
  have hst1 : step code x = .next x1 := by rw [astep_of_fetch h1, e1]
  have hbp1 : x1.regs Reg.x24 = ofN (c.aEnd - 8 * (s.astack.length + 1)) := by
    simp [hx1, M.arith, M.setReg]
  have hrsv : x1.regs rs = x.regs rs := by simp [hx1, M.arith, M.setReg, hrs]
  have hm1 : x1.mem = x.mem := by simp [hx1, M.arith, M.setReg]
  have hvalid := hs.xvalid.2.2.2.2 _ hA1 hA2
  obtain ⟨mem', hw⟩ : ∃ m', x.mem.write? (ofN (c.aEnd - 8 * (s.astack.length + 1))) (x.regs rs)
      = some m' := by simp [Memory.write?, hvalid]
  have e2 : exec (.store Reg.x24 0 rs) x1 = .next { x1.adv with mem := mem' } := by
    simp only [exec, M.ea, hbp1, hrsv, hm1]
    have h0 : ofN (c.aEnd - 8 * (s.astack.length + 1)) + BitVec.ofInt 64 0 =
        ofN (c.aEnd - 8 * (s.astack.length + 1)) := by simp
    rw [h0, hw]
  have hpc1 : x1.pc = x.pc + 1 := by simp [hx1, M.arith, M.setReg]
  have hst2 : step code x1 = .next { x1.adv with mem := mem' } := by
    rw [astep_of_fetch (m := x1) (by rw [hpc1]; exact h2), e2]
  refine ⟨{ x1.adv with mem := mem' }, (ASteps.single hst1).trans (ASteps.single hst2), ?_,
    by simp [M.adv, hpc1], by intro r hr; simp [M.adv, hx1, M.arith, M.setReg, hr]⟩
  obtain ⟨hst, hrg, hmm, hrr⟩ := aux_region_write hg hs hA1 hA2 hw
  refine { x19 := ?_, x20 := ?_, x21 := ?_, x22 := ?_, x23 := ?_, x24 := ?_, stack := hst,
           regs := hrg, mem := hmm, rs := hrr, aux := ?_, irvalid := hs.irvalid, xvalid := ?_,
           capD := hs.capD, capR := hs.capR, capA := ?_ }
  · simpa [M.adv, hx1, M.arith, M.setReg] using hs.x19
  · simpa [M.adv, hx1, M.arith, M.setReg] using hs.x20
  · simpa [M.adv, hx1, M.arith, M.setReg] using hs.x21
  · simpa [M.adv, hx1, M.arith, M.setReg] using hs.x22
  · simpa [M.adv, hx1, M.arith, M.setReg] using hs.x23
  · simp [M.adv, hx1, M.arith, M.setReg]
  · intro i w hi
    show mem'.read? _ = some w
    simp only [List.length_cons]
    cases i with
    | zero =>
      simp at hi; subst hi
      rw [show c.aEnd - 8 * (s.astack.length + 1) + 8 * 0 = c.aEnd - 8 * (s.astack.length + 1) by
        omega, read_write_nat hw hAlt hAlt]
      simp
    | succ i =>
      simp only [List.getElem?_cons_succ] at hi
      have hik : i < s.astack.length := by
        have := (List.getElem?_eq_some_iff.mp hi).1; simpa using this
      have hB : c.aEnd - 8 * (s.astack.length + 1) + 8 * (i + 1) < 2 ^ 64 := by omega
      have hne : c.aEnd - 8 * (s.astack.length + 1) ≠
          c.aEnd - 8 * (s.astack.length + 1) + 8 * (i + 1) := by omega
      rw [read_write_nat hw hAlt hB]
      simp only [hne, ite_false]
      have e : c.aEnd - 8 * (s.astack.length + 1) + 8 * (i + 1) =
          c.aEnd - 8 * s.astack.length + 8 * i := by omega
      rw [e]; exact hs.aux i w hi
  · have := Memory.write?_valid hw
    show RegionsValid c mem'.valid
    rw [this]; exact hs.xvalid
  · simpa using hfit

end Steps

section Guards

variable {c : Cfg} {p : Prog 64} {s : State 64} {x : M} {code : List (Instr Nat)} {L : Layout}
  {base : Nat}

/-- The auxiliary-stack guard's comparison, in terms of its depth. -/
theorem ovfA_flags (hg : Geom c) (hs : Rel0 c p s x) (hLal : L.aLim = ofN (c.aBase + 8)) :
    Cc.ae.holds (subFlags (x.regs Reg.x24) L.aLim) =
      decide (c.aBase + 8 * (s.astack.length + 1) ≤ c.aEnd) := by
  have hcap := hs.capA
  have haE := hg.aEnd_lt
  have h8 := hg.aBase_8
  rw [holds_ae, hs.x24, hLal, ule_ofN (by omega) (by omega)]
  by_cases h : c.aBase + 8 * (s.astack.length + 1) ≤ c.aEnd
  · simp [h]; omega
  · simp [h]; omega

theorem ovfA_run (hpc : x.pc = base) (hat : AAt code base (ovfA L base)) :
    ∃ xb : M, ASteps code x xb ∧ xb.pc = base + 2 ∧
      xb.flags = some (subFlags (x.regs Reg.x24) L.aLim) ∧ xb.mem = x.mem ∧
      (∀ r, r ≠ x9 → xb.regs r = x.regs r) ∧
      code[base + 2]? = some (.jcc .ae (base + 2 + 2)) ∧ code[base + 2 + 1]? = some .exitOvf := by
  obtain ⟨h1, h2, h3, h4, _⟩ := hat
  let xa := x.mov x9 L.aLim
  have hst1 : step code x = .next xa := by rw [astep_of_fetch (by rw [hpc]; exact h1)]; rfl
  have hxa_pc : xa.pc = base + 1 := by simp [xa, M.mov, M.setReg, M.adv, hpc]
  let xb : M := { xa.adv with flags := some (subFlags (xa.regs x24) (xa.regs x9)) }
  have hst2 : step code xa = .next xb := by
    rw [astep_of_fetch (m := xa) (by rw [hxa_pc]; exact h2)]; rfl
  refine ⟨xb, (ASteps.single hst1).trans (ASteps.single hst2), by simp [xb, M.adv, hxa_pc],
    by simp [xb, xa, M.mov, M.setReg, M.adv], by simp [xb, xa, M.adv, M.mov, M.setReg], ?_,
    fetch_cast h3 (by omega), fetch_cast h4 (by omega)⟩
  intro r hr; simp [xb, xa, M.adv, M.mov, M.setReg, hr]

/-- Room for one more auxiliary word: the guard falls through to `base + 4`. -/
theorem ovfA_pass (hg : Geom c) (hs : Rel0 c p s x) (hLal : L.aLim = ofN (c.aBase + 8))
    (hfit : c.aBase + 8 * (s.astack.length + 1) ≤ c.aEnd) (hpc : x.pc = base)
    (hat : AAt code base (ovfA L base)) :
    ∃ x1, ASteps code x x1 ∧ Rel0 c p s x1 ∧ x1.pc = base + 4 ∧ x1.mem = x.mem ∧
      (∀ r, r ≠ x9 → x1.regs r = x.regs r) := by
  obtain ⟨xb, hsb, hpcb, hfb, hmb, hrb, hj, _⟩ := ovfA_run hpc hat
  have hholds : Cc.ae.holds (subFlags (x.regs Reg.x24) L.aLim) = true := by
    rw [ovfA_flags hg hs hLal]; simpa using hfit
  refine ⟨{ xb with pc := base + 2 + 2 }, hsb.trans (ovf_jcc_pass hj hpcb hfb hholds), ?_, rfl, hmb,
    hrb⟩
  refine hs.congr hmb ?_ ?_ ?_ ?_ ?_ ?_ <;> exact hrb _ (by decide)

/-- Auxiliary stack full: the guard exits with `overflow`. -/
theorem ovfA_trap (hg : Geom c) (hs : Rel0 c p s x) (hLal : L.aLim = ofN (c.aBase + 8))
    (h : ¬ c.aBase + 8 * (s.astack.length + 1) ≤ c.aEnd) (hpc : x.pc = base)
    (hat : AAt code base (ovfA L base)) : AExec code x .overflow := by
  obtain ⟨xb, hsb, hpcb, hfb, _, _, hj, he⟩ := ovfA_run hpc hat
  have hholds : Cc.ae.holds (subFlags (x.regs Reg.x24) L.aLim) = false := by
    rw [ovfA_flags hg hs hLal]; simpa using h
  exact AExec.of_steps hsb (ovf_jcc_trap hj he hpcb hfb hholds)

/-- The emptiness check's comparison: `x24 ≠ aEnd` exactly when the auxiliary stack is nonempty. -/
theorem emptyA_flags (hg : Geom c) (hs : Rel0 c p s x) (hLa : L.aEnd = ofN c.aEnd) :
    Cc.ne.holds (subFlags (x.regs Reg.x24) L.aEnd) = decide (s.astack ≠ []) := by
  have hcap := hs.capA
  have haE := hg.aEnd_lt
  rw [holds_ne, hs.x24, hLa]
  by_cases h : s.astack = []
  · simp [h]
  · have hlen : 1 ≤ s.astack.length := by
      cases hh : s.astack with
      | nil => exact absurd hh h
      | cons a as => simp
    have hne : ofN (c.aEnd - 8 * s.astack.length) ≠ ofN c.aEnd := by
      intro e; have := ofN_inj (by omega) haE e; omega
    simp [hne, h]

theorem emptyA_run (hpc : x.pc = base) (hat : AAt code base (emptyA L base)) :
    ∃ xb : M, ASteps code x xb ∧ xb.pc = base + 2 ∧
      xb.flags = some (subFlags (x.regs Reg.x24) L.aEnd) ∧ xb.mem = x.mem ∧
      (∀ r, r ≠ x9 → xb.regs r = x.regs r) ∧
      AAt code (base + 2) [.jcc .ne (base + 2 + 2), .exitTrap .returnUnderflow] := by
  obtain ⟨h1, h2, h3, h4, _⟩ := hat
  let xa := x.mov x9 L.aEnd
  have hst1 : step code x = .next xa := by rw [astep_of_fetch (by rw [hpc]; exact h1)]; rfl
  have hxa_pc : xa.pc = base + 1 := by simp [xa, M.mov, M.setReg, M.adv, hpc]
  let xb : M := { xa.adv with flags := some (subFlags (xa.regs x24) (xa.regs x9)) }
  have hst2 : step code xa = .next xb := by
    rw [astep_of_fetch (m := xa) (by rw [hxa_pc]; exact h2)]; rfl
  refine ⟨xb, (ASteps.single hst1).trans (ASteps.single hst2), by simp [xb, M.adv, hxa_pc],
    by simp [xb, xa, M.mov, M.setReg, M.adv], by simp [xb, xa, M.adv, M.mov, M.setReg], ?_,
    fetch_cast h3 (by omega), fetch_cast h4 (by omega), trivial⟩
  intro r hr; simp [xb, xa, M.adv, M.mov, M.setReg, hr]

/-- Nonempty auxiliary stack: the check falls through to `base + 4`. -/
theorem emptyA_pass (hg : Geom c) (hs : Rel0 c p s x) (hLa : L.aEnd = ofN c.aEnd)
    (hne : s.astack ≠ []) (hpc : x.pc = base) (hat : AAt code base (emptyA L base)) :
    ∃ x1, ASteps code x x1 ∧ Rel0 c p s x1 ∧ x1.pc = base + 4 ∧ x1.mem = x.mem ∧
      (∀ r, r ≠ x9 → x1.regs r = x.regs r) := by
  obtain ⟨xb, hsb, hpcb, hfb, hmb, hrb, hj⟩ := emptyA_run hpc hat
  have hholds : Cc.ne.holds (subFlags (x.regs Reg.x24) L.aEnd) = true := by
    rw [emptyA_flags hg hs hLa]; simpa using hne
  refine ⟨{ xb with pc := base + 2 + 2 }, hsb.trans (guard_pass hj hpcb hfb hholds), ?_, rfl, hmb,
    hrb⟩
  refine hs.congr hmb ?_ ?_ ?_ ?_ ?_ ?_ <;> exact hrb _ (by decide)

/-- Empty auxiliary stack: the check traps `returnUnderflow`. -/
theorem emptyA_trap (hg : Geom c) (hs : Rel0 c p s x) (hLa : L.aEnd = ofN c.aEnd)
    (he : s.astack = []) (hpc : x.pc = base) (hat : AAt code base (emptyA L base)) :
    AExec code x (.trapped .returnUnderflow) := by
  obtain ⟨xb, hsb, hpcb, hfb, _, _, hj⟩ := emptyA_run hpc hat
  have hholds : Cc.ne.holds (subFlags (x.regs Reg.x24) L.aEnd) = false := by
    rw [emptyA_flags hg hs hLa]; simp [he]
  exact AExec.of_steps hsb (guard_trap hj hpcb hfb hholds)

end Guards

section Ops

variable {c : Cfg} {p : Prog 64} {s : State 64} {x : M} {code : List (Instr Nat)}
  {L : Layout} {base : Nat} {off : Nat → Nat}

/-- Placement of the `tor` code. -/
theorem xat_tor (hat : AAt code base (lowerInstr L base off .tor)) :
    AAt code base (uf L 1 base) ∧ AAt code (base + 4) (ovfA L (base + 4)) ∧
      AAt code (base + 8) [.load x9 Reg.x19 0, .addImm Reg.x19 8, .addImm Reg.x24 (-8),
        .store Reg.x24 0 x9] := by
  have hat' : AAt code base (uf L 1 base ++ ovfA L (base + 4) ++
      [.load x9 Reg.x19 0, .addImm Reg.x19 8, .addImm Reg.x24 (-8), .store Reg.x24 0 x9]) := hat
  obtain ⟨hatuo, hatr⟩ := aat_append.mp hat'
  obtain ⟨hatuf, hato⟩ := aat_append.mp hatuo
  have hufl : (uf L 1 base).length = 4 := by simp [uf]
  rw [hufl] at hato
  have hl : (uf L 1 base ++ ovfA L (base + 4)).length = 8 := by simp [hufl, ovfA]
  rw [hl] at hatr
  exact ⟨hatuf, hato, hatr⟩

theorem sim_tor_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hLal : L.aLim = ofN (c.aBase + 8))
    (hs : Rel0 c p s x) (hpc : x.pc = base) (hat : AAt code base (lowerInstr L base off .tor))
    {a : W} {d : List W} (hd : s.dstack = a :: d)
    (hfit : c.aBase + 8 * (s.astack.length + 1) ≤ c.aEnd) :
    ∃ x', ASteps code x x' ∧ Rel0 c p { s with dstack := d, astack := a :: s.astack } x' ∧
      x'.pc = base + isize (.tor : WordDialect.Instr 64) := by
  obtain ⟨hatuf, hato, f0, f1, f2, f3, _⟩ := xat_tor hat
  have hk : 1 ≤ s.dstack.length := by simp [hd]
  obtain ⟨x1, hs1, hr1, hpc1, _, _⟩ := uf_pass hg hs hL (by decide) (by decide) hk hpc hatuf
  obtain ⟨x1', hs1', hr1', hpc1', _, _⟩ := ovfA_pass hg hr1 hLal hfit hpc1 hato
  obtain ⟨x2, hs2, hr2, hpc2, hv2, _, _⟩ := ld_step (code := code) hr1' (j := 0) (v := a)
    (by simp [hd]) (rd := x9) (by simp) (disp := 0) (by simp) (fetch_cast f0 (by omega))
  obtain ⟨x3, hs3, hr3, hpc3, ho3⟩ := adj_step (code := code) hg hr2 (n := 1) (by simp [hd])
    (δ := 8) (by simp) (fetch_cast f1 (by omega))
  have hax3 : x3.regs x9 = a := by rw [ho3 x9 (by decide), hv2]
  have e : s.dstack.drop 1 = d := by simp [hd]
  rw [e] at hr3
  obtain ⟨x4, hs4, hr4, hpc4, _⟩ := aux_push hg hr3 x9 (by decide) hfit
    ⟨fetch_cast f2 (by omega), fetch_cast f3 (by omega), trivial⟩
  rw [hax3] at hr4
  exact ⟨x4, (((hs1.trans hs1').trans hs2).trans hs3).trans hs4, hr4,
    by simp [isize, ufSize]; omega⟩

theorem sim_tor_ovf (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hLal : L.aLim = ofN (c.aBase + 8))
    (hs : Rel0 c p s x) (hpc : x.pc = base) (hat : AAt code base (lowerInstr L base off .tor))
    (hk : 1 ≤ s.dstack.length) (h : ¬ c.aBase + 8 * (s.astack.length + 1) ≤ c.aEnd) :
    AExec code x .overflow := by
  obtain ⟨hatuf, hato, _⟩ := xat_tor hat
  obtain ⟨x1, hs1, hr1, hpc1, _, _⟩ := uf_pass hg hs hL (by decide) (by decide) hk hpc hatuf
  exact AExec.of_steps hs1 (ovfA_trap hg hr1 hLal h hpc1 hato)

/-- Placement of `emptyA L base ++ ovfD L (base + 4) ++ rest`. -/
theorem xat_take {rest : List (Instr Nat)}
    (hat : AAt code base (emptyA L base ++ ovfD L (base + 4) ++ rest)) :
    AAt code base (emptyA L base) ∧ AAt code (base + 4) (ovfD L (base + 4)) ∧
      AAt code (base + 8) rest := by
  obtain ⟨hatuo, hatr⟩ := aat_append.mp hat
  obtain ⟨hate, hato⟩ := aat_append.mp hatuo
  have hel : (emptyA L base).length = 4 := rfl
  rw [hel] at hato
  have hl : (emptyA L base ++ ovfD L (base + 4)).length = 8 := rfl
  rw [hl] at hatr
  exact ⟨hate, hato, hatr⟩

theorem sim_fromr_ok (hg : Geom c) (hLa : L.aEnd = ofN c.aEnd) (hLd : L.dLim = ofN (c.dBase + 8))
    (hs : Rel0 c p s x) (hpc : x.pc = base) (hat : AAt code base (lowerInstr L base off .fromr))
    {a : W} {as : List W} (hd : s.astack = a :: as)
    (hfit : c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd) :
    ∃ x', ASteps code x x' ∧ Rel0 c p { s with dstack := a :: s.dstack, astack := as } x' ∧
      x'.pc = base + isize (.fromr : WordDialect.Instr 64) := by
  obtain ⟨hate, hato, f0, f1, f2, f3, _⟩ := xat_take (L := L) (rest := [.load x9 Reg.x24 0,
    .addImm Reg.x24 8, .addImm Reg.x19 (-8), .store Reg.x19 0 x9]) hat
  obtain ⟨x1, hs1, hr1, hpc1, _, _⟩ := emptyA_pass hg hs hLa (by simp [hd]) hpc hate
  obtain ⟨x1', hs1', hr1', hpc1', _, _⟩ := ovfD_pass hg hr1 hLd hfit hpc1 hato
  obtain ⟨x2, hs2, hr2, hpc2, hv2, _, _⟩ := ld_aux_step (code := code) hr1' hd (rd := x9)
    (by simp) (fetch_cast f0 (by omega))
  obtain ⟨x3, hs3, hr3, hpc3, ho3⟩ := aux_drop (code := code) hr2 hd (fetch_cast f1 (by omega))
  have hax3 : x3.regs x9 = a := by rw [ho3 x9 (by decide), hv2]
  obtain ⟨x4, hs4, hr4, hpc4, _⟩ := push_pair hg hr3 x9 (by decide) hfit
    ⟨fetch_cast f2 (by omega), fetch_cast f3 (by omega), trivial⟩
  rw [hax3] at hr4
  exact ⟨x4, (((hs1.trans hs1').trans hs2).trans hs3).trans hs4, hr4, by simp [isize]; omega⟩

theorem sim_fromr_trap (hg : Geom c) (hLa : L.aEnd = ofN c.aEnd) (hs : Rel0 c p s x)
    (hpc : x.pc = base) (hat : AAt code base (lowerInstr L base off .fromr)) (he : s.astack = []) :
    AExec code x (.trapped .returnUnderflow) :=
  emptyA_trap hg hs hLa he hpc (xat_take (L := L) (rest := [.load x9 Reg.x24 0,
    .addImm Reg.x24 8, .addImm Reg.x19 (-8), .store Reg.x19 0 x9]) hat).1

theorem sim_fromr_ovf (hg : Geom c) (hLa : L.aEnd = ofN c.aEnd) (hLd : L.dLim = ofN (c.dBase + 8))
    (hs : Rel0 c p s x) (hpc : x.pc = base) (hat : AAt code base (lowerInstr L base off .fromr))
    (hne : s.astack ≠ []) (h : ¬ c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd) :
    AExec code x .overflow := by
  obtain ⟨hate, hato, _⟩ := xat_take (L := L) (rest := [.load x9 Reg.x24 0,
    .addImm Reg.x24 8, .addImm Reg.x19 (-8), .store Reg.x19 0 x9]) hat
  obtain ⟨x1, hs1, hr1, hpc1, _, _⟩ := emptyA_pass hg hs hLa hne hpc hate
  exact AExec.of_steps hs1 (ovfD_trap hg hr1 hLd h hpc1 hato)

theorem sim_rfetch_ok (hg : Geom c) (hLa : L.aEnd = ofN c.aEnd) (hLd : L.dLim = ofN (c.dBase + 8))
    (hs : Rel0 c p s x) (hpc : x.pc = base) (hat : AAt code base (lowerInstr L base off .rfetch))
    {a : W} {as : List W} (hd : s.astack = a :: as)
    (hfit : c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd) :
    ∃ x', ASteps code x x' ∧ Rel0 c p { s with dstack := a :: s.dstack } x' ∧
      x'.pc = base + isize (.rfetch : WordDialect.Instr 64) := by
  obtain ⟨hate, hato, f0, f1, f2, _⟩ := xat_take (L := L) (rest := [.load x9 Reg.x24 0,
    .addImm Reg.x19 (-8), .store Reg.x19 0 x9]) hat
  obtain ⟨x1, hs1, hr1, hpc1, _, _⟩ := emptyA_pass hg hs hLa (by simp [hd]) hpc hate
  obtain ⟨x1', hs1', hr1', hpc1', _, _⟩ := ovfD_pass hg hr1 hLd hfit hpc1 hato
  obtain ⟨x2, hs2, hr2, hpc2, hv2, _, _⟩ := ld_aux_step (code := code) hr1' hd (rd := x9)
    (by simp) (fetch_cast f0 (by omega))
  obtain ⟨x3, hs3, hr3, hpc3, _⟩ := push_pair hg hr2 x9 (by decide) hfit
    ⟨fetch_cast f1 (by omega), fetch_cast f2 (by omega), trivial⟩
  rw [hv2] at hr3
  exact ⟨x3, ((hs1.trans hs1').trans hs2).trans hs3, hr3, by simp [isize]; omega⟩

theorem sim_rfetch_trap (hg : Geom c) (hLa : L.aEnd = ofN c.aEnd) (hs : Rel0 c p s x)
    (hpc : x.pc = base) (hat : AAt code base (lowerInstr L base off .rfetch)) (he : s.astack = []) :
    AExec code x (.trapped .returnUnderflow) :=
  emptyA_trap hg hs hLa he hpc (xat_take (L := L) (rest := [.load x9 Reg.x24 0,
    .addImm Reg.x19 (-8), .store Reg.x19 0 x9]) hat).1

theorem sim_rfetch_ovf (hg : Geom c) (hLa : L.aEnd = ofN c.aEnd) (hLd : L.dLim = ofN (c.dBase + 8))
    (hs : Rel0 c p s x) (hpc : x.pc = base) (hat : AAt code base (lowerInstr L base off .rfetch))
    (hne : s.astack ≠ []) (h : ¬ c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd) :
    AExec code x .overflow := by
  obtain ⟨hate, hato, _⟩ := xat_take (L := L) (rest := [.load x9 Reg.x24 0,
    .addImm Reg.x19 (-8), .store Reg.x19 0 x9]) hat
  obtain ⟨x1, hs1, hr1, hpc1, _, _⟩ := emptyA_pass hg hs hLa hne hpc hate
  exact AExec.of_steps hs1 (ovfD_trap hg hr1 hLd h hpc1 hato)

end Ops

end A64
end WordDialect
