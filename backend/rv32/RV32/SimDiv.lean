import RV32.SimMemOps

/-!
# RV32.SimDiv

`select`, `cmp`, `div`, `sdiv`: the instructions whose lowering branches inside the instruction.
`select` skips a `mv` with `beqz`; `cmp` sets `1`, then skips the `0` with `bcc` on the IR's own
condition. The divisions guard the zero divisor with `bnez`; after it RISC-V `divu`/`div` are
`BitVec.udiv`/`BitVec.sdiv` exactly (`div` of the most negative number by `-1` wraps), so the
division is one instruction.
-/

namespace WordDialect
namespace RV32

open Reg

section Div

variable {c : Cfg} {p : Prog 32} {s : State 32} {x : M} {code : List (Instr Nat)}
  {L : Layout} {base : Nat} {off : Nat → Nat}

/-- `Rel0` ignores scratch registers. -/
theorem rel0_scratch (hs : Rel0 c p s x) {x' : M} (hm : x'.mem = x.mem)
    (hr : ∀ r, r ≠ t0 → r ≠ t1 → r ≠ t2 → r ≠ t3 → x'.regs r = x.regs r) : Rel0 c p s x' :=
  hs.congr hm (hr _ (by decide) (by decide) (by decide) (by decide))
    (hr _ (by decide) (by decide) (by decide) (by decide))
    (hr _ (by decide) (by decide) (by decide) (by decide))
    (hr _ (by decide) (by decide) (by decide) (by decide))
    (hr _ (by decide) (by decide) (by decide) (by decide))
    (hr _ (by decide) (by decide) (by decide) (by decide))

theorem zg_pass (hs : Rel0 c p s x) {b : W} (hb : x.regs t1 = b) (hne : b ≠ 0#32) {t : Nat}
    (ht : t = x.pc + 2) (hat : RAt code x.pc [.bnez t1 t, .exitTrap .divideByZero]) :
    ∃ x', RSteps code x x' ∧ Rel0 c p s x' ∧ x'.pc = x.pc + 2 ∧ x'.regs = x.regs ∧
      x'.mem = x.mem := by
  obtain ⟨f0, _⟩ := hat
  have hst : step code x = .next { x with pc := t } := by
    rw [rstep_of_fetch f0]; simp [exec, hb, hne]
  exact ⟨{ x with pc := t }, RSteps.single hst, hs.congr rfl rfl rfl rfl rfl rfl rfl, ht, rfl, rfl⟩

theorem zg_trap (hb : x.regs t1 = 0#32) {t : Nat}
    (hat : RAt code x.pc [.bnez t1 t, .exitTrap .divideByZero]) :
    RExec code x (.trapped .divideByZero) := by
  obtain ⟨f0, f1, _⟩ := hat
  refine .next (m1 := x.adv) ?_ (.trap ?_)
  · rw [rstep_of_fetch f0]; simp [exec, hb]
  · rw [rstep_of_fetch (m := x.adv) (by simpa [M.adv] using f1)]; simp [exec]

/-- `div` and `sdiv` share their lowering shape: load both operands, trap on a zero divisor,
divide into `t0`, store and pop. `g` is the RISC-V division (defined at zero), `f` the IR's. -/
theorem sim_divop_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x)
    (hpc : x.pc = base) (i : Instr Nat) (g f : W → W → W)
    (hi : ∀ m : M, exec i m = .next (m.arith t0 (g (m.regs t0) (m.regs t1))))
    (hfg : ∀ a b, b ≠ 0#32 → g a b = f a b)
    (hat : RAt code base (uf L 2 base ++ [.load t1 Reg.s1 0, .load t0 Reg.s1 4,
      .bnez t1 (base + ufSize 2 + 4), .exitTrap .divideByZero, i, .store Reg.s1 4 t0,
      .addImm Reg.s1 4]))
    {a b : W} {d : List W} (hd : s.dstack = b :: a :: d) (hb : b ≠ 0#32) :
    ∃ x', RSteps code x x' ∧ Rel0 c p { s with dstack := f a b :: d } x' ∧
      x'.pc = base + (ufSize 2 + 7) := by
  obtain ⟨hatuf, hatr⟩ := rat_append.mp hat
  have hufl : (uf L 2 base).length = 3 := by simp [uf]
  rw [hufl] at hatr
  obtain ⟨f0, f1, f2, f3, f4, f5, f6, _⟩ := hatr
  have hk : 2 ≤ s.dstack.length := by simp [hd]
  obtain ⟨x1, hs1, hr1, hpc1, hm1, _⟩ := uf_pass hg hs hL (by decide) (by decide) hk hpc hatuf
  obtain ⟨x2, hs2, hr2, hpc2, hv2, ho2, _⟩ := ld_step (code := code) hr1 (j := 0) (v := b)
    (by simp [hd]) (rd := t1) (by simp) (disp := 0) (by simp) (fetch_cast f0 (by omega))
  obtain ⟨x3, hs3, hr3, hpc3, hv3, ho3, _⟩ := ld_step (code := code) hr2 (j := 1) (v := a)
    (by simp [hd]) (rd := t0) (by simp) (disp := 4) (by simp) (fetch_cast f1 (by omega))
  have hcx3 : x3.regs t1 = b := by rw [ho3 t1 (by decide), hv2]
  obtain ⟨x4, hs4, hr4, hpc4, hreg4, hm4⟩ := zg_pass (code := code) hr3 hcx3 hb
    (t := base + ufSize 2 + 4) (by simp [ufSize]; omega)
    ⟨fetch_cast f2 (by omega), fetch_cast f3 (by omega), trivial⟩
  have hax4 : x4.regs t0 = a := by rw [hreg4, hv3]
  have hcx4 : x4.regs t1 = b := by rw [hreg4, hcx3]
  let x5 := x4.arith t0 (g (x4.regs t0) (x4.regs t1))
  have hst5 : step code x4 = .next x5 := by rw [rstep_of_fetch (fetch_cast f4 (by omega)), hi]
  have hr5 : Rel0 c p s x5 := arith_rel0 hr4 t0 (scratch_ne t0 (by simp)) _
  have hax5 : x5.regs t0 = f a b := by simp [x5, M.arith, M.setReg, hax4, hcx4, hfg a b hb]
  obtain ⟨x6, hs6, hr6, hpc6, _⟩ := st_step (code := code) hg hr5 (j := 1) (by simp [hd])
    (rs := t0) (disp := 4) (by simp) (fetch_cast f5 (by simp [x5, M.arith]; omega))
  have hlen : 1 ≤ ({ s with dstack := s.dstack.set 1 (x5.regs t0) } : State 32).dstack.length := by
    simp [hd]
  obtain ⟨x7, hs7, hr7, hpc7, _⟩ := adj_step (code := code) hg hr6 (n := 1) hlen (δ := 4) (by simp)
    (fetch_cast f6 (by simp [x5, M.arith] at hpc6 ⊢; omega))
  have hr7' : Rel0 c p { s with dstack := (s.dstack.set 1 (x5.regs t0)).drop 1 } x7 := hr7
  have e : (s.dstack.set 1 (x5.regs t0)).drop 1 = f a b :: d := by simp [hd, hax5]
  rw [e] at hr7'
  exact ⟨x7, ((((hs1.trans hs2).trans hs3).trans hs4).trans
    ((RSteps.single hst5).trans (hs6.trans hs7))), hr7', by
      simp [x5, M.arith, ufSize] at hpc7 hpc6 ⊢; omega⟩

theorem sim_divop_zero (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x)
    (hpc : x.pc = base) (rest : List (Instr Nat))
    (hat : RAt code base (uf L 2 base ++ ([.load t1 Reg.s1 0, .load t0 Reg.s1 4,
      .bnez t1 (base + ufSize 2 + 4), .exitTrap .divideByZero] ++ rest)))
    {a : W} {d : List W} (hd : s.dstack = 0#32 :: a :: d) : RExec code x (.trapped .divideByZero) := by
  obtain ⟨hatuf, hatr⟩ := rat_append.mp hat
  have hufl : (uf L 2 base).length = 3 := by simp [uf]
  rw [hufl] at hatr
  obtain ⟨f0, f1, f2, f3, _⟩ := hatr
  have hk : 2 ≤ s.dstack.length := by simp [hd]
  obtain ⟨x1, hs1, hr1, hpc1, hm1, _⟩ := uf_pass hg hs hL (by decide) (by decide) hk hpc hatuf
  obtain ⟨x2, hs2, hr2, hpc2, hv2, ho2, _⟩ := ld_step (code := code) hr1 (j := 0) (v := 0#32)
    (by simp [hd]) (rd := t1) (by simp) (disp := 0) (by simp) (fetch_cast f0 (by omega))
  obtain ⟨x3, hs3, hr3, hpc3, hv3, ho3, _⟩ := ld_step (code := code) hr2 (j := 1) (v := a)
    (by simp [hd]) (rd := t0) (by simp) (disp := 4) (by simp) (fetch_cast f1 (by omega))
  have hcx3 : x3.regs t1 = 0#32 := by rw [ho3 t1 (by decide), hv2]
  exact RExec.of_steps ((hs1.trans hs2).trans hs3) (zg_trap (code := code) hcx3
    ⟨fetch_cast f2 (by omega), fetch_cast f3 (by omega), trivial⟩)

theorem sim_div_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : RAt code base (lowerInstr L base off .div)) {a b : W} {d : List W}
    (hd : s.dstack = b :: a :: d) (hb : b ≠ 0#32) :
    ∃ x', RSteps code x x' ∧ Rel0 c p { s with dstack := a.udiv b :: d } x' ∧
      x'.pc = base + isize (.div : WordDialect.Instr 32) :=
  sim_divop_ok hg hL hs hpc (.divu t0 t0 t1) divu BitVec.udiv (fun _ => rfl)
    (fun a b h => by simp [divu, h]) hat hd hb

theorem sim_div_zero (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x)
    (hpc : x.pc = base) (hat : RAt code base (lowerInstr L base off .div)) {a : W} {d : List W}
    (hd : s.dstack = 0#32 :: a :: d) : RExec code x (.trapped .divideByZero) :=
  sim_divop_zero hg hL hs hpc [.divu t0 t0 t1, .store Reg.s1 4 t0, .addImm Reg.s1 4] hat hd

theorem sim_sdiv_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : RAt code base (lowerInstr L base off .sdiv)) {a b : W} {d : List W}
    (hd : s.dstack = b :: a :: d) (hb : b ≠ 0#32) :
    ∃ x', RSteps code x x' ∧ Rel0 c p { s with dstack := a.sdiv b :: d } x' ∧
      x'.pc = base + isize (.sdiv : WordDialect.Instr 32) :=
  sim_divop_ok hg hL hs hpc (.div t0 t0 t1) divs BitVec.sdiv (fun _ => rfl)
    (fun a b h => by simp [divs, h]) hat hd hb

theorem sim_sdiv_zero (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x)
    (hpc : x.pc = base) (hat : RAt code base (lowerInstr L base off .sdiv)) {a : W} {d : List W}
    (hd : s.dstack = 0#32 :: a :: d) : RExec code x (.trapped .divideByZero) :=
  sim_divop_zero hg hL hs hpc [.div t0 t0 t1, .store Reg.s1 4 t0, .addImm Reg.s1 4] hat hd

theorem sim_select_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x)
    (hpc : x.pc = base) (hat : RAt code base (lowerInstr L base off .select)) {cc y v : W}
    {d : List W} (hd : s.dstack = cc :: y :: v :: d) :
    ∃ x', RSteps code x x' ∧
      Rel0 c p { s with dstack := (if Word.isTrue cc then v else y) :: d } x' ∧
      x'.pc = base + isize (.select : WordDialect.Instr 32) := by
  have hat' : RAt code base (uf L 3 base ++ [.load t1 Reg.s1 0, .load t0 Reg.s1 4,
      .load t3 Reg.s1 8, .beqz t1 (base + ufSize 3 + 5), .movRR t0 t3, .store Reg.s1 8 t0,
      .addImm Reg.s1 8]) := hat
  obtain ⟨hatuf, hatr⟩ := rat_append.mp hat'
  have hufl : (uf L 3 base).length = 3 := by simp [uf]
  rw [hufl] at hatr
  obtain ⟨f0, f1, f2, f3, f4, f5, f6, _⟩ := hatr
  have hk : 3 ≤ s.dstack.length := by simp [hd]
  obtain ⟨x1, hs1, hr1, hpc1, hm1, _⟩ := uf_pass hg hs hL (by decide) (by decide) hk hpc hatuf
  obtain ⟨x2, hs2, hr2, hpc2, hv2, ho2, _⟩ := ld_step (code := code) hr1 (j := 0) (v := cc)
    (by simp [hd]) (rd := t1) (by simp) (disp := 0) (by simp) (fetch_cast f0 (by omega))
  obtain ⟨x3, hs3, hr3, hpc3, hv3, ho3, _⟩ := ld_step (code := code) hr2 (j := 1) (v := y)
    (by simp [hd]) (rd := t0) (by simp) (disp := 4) (by simp) (fetch_cast f1 (by omega))
  obtain ⟨x4, hs4, hr4, hpc4, hv4, ho4, _⟩ := ld_step (code := code) hr3 (j := 2) (v := v)
    (by simp [hd]) (rd := t3) (by simp) (disp := 8) (by simp) (fetch_cast f2 (by omega))
  have hcx4 : x4.regs t1 = cc := by rw [ho4 t1 (by decide), ho3 t1 (by decide), hv2]
  have hax4 : x4.regs t0 = y := by rw [ho4 t0 (by decide), hv3]
  -- after the branch (and the `mv` when `cc ≠ 0`), `t0` holds the result at `base + 3 + 5`
  obtain ⟨x6, hs6, hr6, hpc6, hval⟩ : ∃ x6, RSteps code x4 x6 ∧ Rel0 c p s x6 ∧
      x6.pc = base + 3 + 5 ∧ x6.regs t0 = (if Word.isTrue cc then v else y) := by
    by_cases hc : cc = 0#32
    · have hst : step code x4 = .next { x4 with pc := base + ufSize 3 + 5 } := by
        rw [rstep_of_fetch (m := x4) (fetch_cast f3 (by omega))]; simp [exec, hcx4, hc]
      refine ⟨_, RSteps.single hst, hr4.congr rfl rfl rfl rfl rfl rfl rfl, by simp [ufSize], ?_⟩
      simp [hax4, Word.isTrue, hc]
    · have hst : step code x4 = .next x4.adv := by
        rw [rstep_of_fetch (m := x4) (fetch_cast f3 (by omega))]; simp [exec, hcx4, hc]
      let x5 := x4.adv.mov t0 (x4.adv.regs t3)
      have hst5 : step code x4.adv = .next x5 := by
        rw [rstep_of_fetch (m := x4.adv) (fetch_cast f4 (by simp [M.adv]; omega))]; rfl
      refine ⟨x5, (RSteps.single hst).trans (RSteps.single hst5),
        mov_rel0 (hr4.congr rfl rfl rfl rfl rfl rfl rfl : Rel0 c p s x4.adv) t0
          (scratch_ne t0 (by simp)) _,
        by simp [x5, M.mov, M.setReg, M.adv]; omega, ?_⟩
      simp [x5, M.mov, M.setReg, M.adv, Word.isTrue, hc, hv4]
  obtain ⟨x7, hs7, hr7, hpc7, _⟩ := st_step (code := code) hg hr6 (j := 2) (by simp [hd])
    (rs := t0) (disp := 8) (by simp) (fetch_cast f5 (by omega))
  have hlen : 2 ≤ ({ s with dstack := s.dstack.set 2 (x6.regs t0) } : State 32).dstack.length := by
    simp [hd]
  obtain ⟨x8, hs8, hr8, hpc8, _⟩ := adj_step (code := code) hg hr7 (n := 2) hlen (δ := 8) (by simp)
    (fetch_cast f6 (by omega))
  have hr8' : Rel0 c p { s with dstack := (s.dstack.set 2 (x6.regs t0)).drop 2 } x8 := hr8
  have e : (s.dstack.set 2 (x6.regs t0)).drop 2 = (if Word.isTrue cc then v else y) :: d := by
    simp [hd, hval]
  rw [e] at hr8'
  exact ⟨x8, (((((hs1.trans hs2).trans hs3).trans hs4).trans hs6).trans hs7).trans hs8, hr8',
    by simp [isize, ufSize]; omega⟩

/-- `cmp c`: `t2 := 1`, then `bcc c` skips `t2 := 0` exactly when the IR comparison holds. -/
theorem sim_cmp_ok (cd : WordDialect.Cond) (hg : Geom c) (hL : L.dEnd = ofN c.dEnd)
    (hs : Rel0 c p s x) (hpc : x.pc = base) (hat : RAt code base (lowerInstr L base off (.cmp cd)))
    {b a : W} {d : List W} (hd : s.dstack = b :: a :: d) :
    ∃ x', RSteps code x x' ∧
      Rel0 c p { s with dstack := Word.ofBool (cd.eval a b) :: d } x' ∧
      x'.pc = base + isize (.cmp cd : WordDialect.Instr 32) := by
  have hat' : RAt code base (uf L 2 base ++ [.load t1 Reg.s1 0, .load t0 Reg.s1 4,
      .movImm t2 1#32, .bcc cd t0 t1 (base + ufSize 2 + 5), .movImm t2 0#32, .store Reg.s1 4 t2,
      .addImm Reg.s1 4]) := hat
  obtain ⟨hatuf, hatr⟩ := rat_append.mp hat'
  have hufl : (uf L 2 base).length = 3 := by simp [uf]
  rw [hufl] at hatr
  obtain ⟨f0, f1, f2, f3, f4, f5, f6, _⟩ := hatr
  have hk : 2 ≤ s.dstack.length := by simp [hd]
  obtain ⟨x1, hs1, hr1, hpc1, hm1, _⟩ := uf_pass hg hs hL (by decide) (by decide) hk hpc hatuf
  obtain ⟨x2, hs2, hr2, hpc2, hv2, ho2, _⟩ := ld_step (code := code) hr1 (j := 0) (v := b)
    (by simp [hd]) (rd := t1) (by simp) (disp := 0) (by simp) (fetch_cast f0 (by omega))
  obtain ⟨x3, hs3, hr3, hpc3, hv3, ho3, _⟩ := ld_step (code := code) hr2 (j := 1) (v := a)
    (by simp [hd]) (rd := t0) (by simp) (disp := 4) (by simp) (fetch_cast f1 (by omega))
  have hcx3 : x3.regs t1 = b := by rw [ho3 t1 (by decide), hv2]
  obtain ⟨x4, hs4, hr4, hpc4, hv4, ho4, _⟩ := movimm_step (code := code) hr3 (rd := t2) (by simp)
    (v := 1#32) (fetch_cast f2 (by omega))
  have hax4 : x4.regs t0 = a := by rw [ho4 t0 (by decide), hv3]
  have hcx4 : x4.regs t1 = b := by rw [ho4 t1 (by decide), hcx3]
  obtain ⟨x6, hs6, hr6, hpc6, hval⟩ : ∃ x6, RSteps code x4 x6 ∧ Rel0 c p s x6 ∧
      x6.pc = base + 3 + 5 ∧ x6.regs t2 = Word.ofBool (cd.eval a b) := by
    by_cases hc : cd.eval a b = true
    · have hst : step code x4 = .next { x4 with pc := base + ufSize 2 + 5 } := by
        rw [rstep_of_fetch (m := x4) (fetch_cast f3 (by omega))]; simp [exec, hax4, hcx4, hc]
      refine ⟨_, RSteps.single hst, hr4.congr rfl rfl rfl rfl rfl rfl rfl, by simp [ufSize], ?_⟩
      simp [hv4, hc, Word.ofBool]
    · have hc' : cd.eval a b = false := by simpa using hc
      have hst : step code x4 = .next x4.adv := by
        rw [rstep_of_fetch (m := x4) (fetch_cast f3 (by omega))]; simp [exec, hax4, hcx4, hc']
      obtain ⟨x5, hs5, hr5, hpc5, hv5, _, _⟩ := movimm_step (code := code)
        (hr4.congr rfl rfl rfl rfl rfl rfl rfl : Rel0 c p s x4.adv) (rd := t2) (by simp)
        (v := 0#32) (fetch_cast f4 (by simp [M.adv]; omega))
      refine ⟨x5, (RSteps.single hst).trans hs5, hr5, by simp [M.adv] at hpc5; omega, ?_⟩
      simp [hv5, hc', Word.ofBool]
  obtain ⟨x7, hs7, hr7, hpc7, _⟩ := st_step (code := code) hg hr6 (j := 1) (by simp [hd])
    (rs := t2) (disp := 4) (by simp) (fetch_cast f5 (by omega))
  have hlen : 1 ≤ ({ s with dstack := s.dstack.set 1 (x6.regs t2) } : State 32).dstack.length := by
    simp [hd]
  obtain ⟨x8, hs8, hr8, hpc8, _⟩ := adj_step (code := code) hg hr7 (n := 1) hlen (δ := 4) (by simp)
    (fetch_cast f6 (by omega))
  have hr8' : Rel0 c p { s with dstack := (s.dstack.set 1 (x6.regs t2)).drop 1 } x8 := hr8
  have e : (s.dstack.set 1 (x6.regs t2)).drop 1 = Word.ofBool (cd.eval a b) :: d := by
    simp [hd, hval]
  rw [e] at hr8'
  exact ⟨x8, (((((hs1.trans hs2).trans hs3).trans hs4).trans hs6).trans hs7).trans hs8, hr8',
    by simp [isize, ufSize]; omega⟩

end Div

end RV32
end WordDialect
