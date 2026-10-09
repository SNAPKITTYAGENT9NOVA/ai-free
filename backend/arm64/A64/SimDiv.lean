import A64.SimMemOps

/-!
# A64.SimDiv

`select`, `div`, `sdiv`: the three-operand select, and the divisions with their zero guard
(`divideByZero` trap). AArch64 `udiv` and `sdiv` are `BitVec.udiv` and `BitVec.sdiv` exactly
(no fault, `sdiv` of the most negative number by `-1` wraps), so after the guard the division is
one instruction.
-/

namespace WordDialect
namespace A64

open Reg

section Div

variable {c : Cfg} {p : Prog 64} {s : State 64} {x : M} {code : List (Instr Nat)}
  {L : Layout} {base : Nat} {off : Nat → Nat}

/-- `Rel0` ignores scratch registers. -/
theorem rel0_scratch (hs : Rel0 c p s x) {x' : M} (hm : x'.mem = x.mem)
    (hr : ∀ r, r ≠ x9 → r ≠ x10 → r ≠ x11 → r ≠ x12 → x'.regs r = x.regs r) : Rel0 c p s x' :=
  hs.congr hm (hr _ (by decide) (by decide) (by decide) (by decide))
    (hr _ (by decide) (by decide) (by decide) (by decide))
    (hr _ (by decide) (by decide) (by decide) (by decide))
    (hr _ (by decide) (by decide) (by decide) (by decide))
    (hr _ (by decide) (by decide) (by decide) (by decide))
    (hr _ (by decide) (by decide) (by decide) (by decide))

theorem zg_pass (hs : Rel0 c p s x) {b : W} (hb : x.regs x10 = b) (hne : b ≠ 0#64) {t : Nat}
    (ht : t = x.pc + 3)
    (hat : AAt code x.pc [.test x10 x10, .jcc .ne t, .exitTrap .divideByZero]) :
    ∃ x', ASteps code x x' ∧ Rel0 c p s x' ∧ x'.pc = x.pc + 3 ∧ x'.regs = x.regs ∧
      x'.mem = x.mem := by
  obtain ⟨f0, f1, f2, _⟩ := hat
  let x1 : M := { x.adv with flags := some (logicFlags (x.regs x10 &&& x.regs x10)) }
  have hst1 : step code x = .next x1 := by rw [astep_of_fetch f0]; rfl
  have hpc1 : x1.pc = x.pc + 1 := by simp [x1, M.adv]
  have hfl : x1.flags = some (logicFlags (b &&& b)) := by simp [x1, hb]
  have hhold : Cc.ne.holds (logicFlags (b &&& b)) = true := by simp [Cc.holds, logicFlags, hne]
  have e : x.pc + 1 + 2 = t := by omega
  have hg := guard_pass (code := code) (pc := x.pc + 1) (m := x1) (c := .ne) (t := .divideByZero)
    (f := logicFlags (b &&& b)) (by rw [e]; exact ⟨f1, f2, trivial⟩) hpc1 hfl hhold
  refine ⟨{ x1 with pc := x.pc + 1 + 2 }, (ASteps.single hst1).trans hg, ?_, by simp, rfl, rfl⟩
  exact hs.congr rfl rfl rfl rfl rfl rfl rfl

theorem zg_trap (hs : Rel0 c p s x) (hb : x.regs x10 = 0#64) {t : Nat}
    (hat : AAt code x.pc [.test x10 x10, .jcc .ne t, .exitTrap .divideByZero]) (ht : t = x.pc + 3) :
    AExec code x (.trapped .divideByZero) := by
  obtain ⟨f0, f1, f2, _⟩ := hat
  let x1 : M := { x.adv with flags := some (logicFlags (x.regs x10 &&& x.regs x10)) }
  have hst1 : step code x = .next x1 := by rw [astep_of_fetch f0]; rfl
  have hpc1 : x1.pc = x.pc + 1 := by simp [x1, M.adv]
  have hfl : x1.flags = some (logicFlags (0#64 &&& 0#64)) := by simp [x1, hb]
  have hhold : Cc.ne.holds (logicFlags (0#64 &&& 0#64)) = false := by simp [Cc.holds, logicFlags]
  have e : x.pc + 1 + 2 = t := by omega
  exact AExec.of_steps (ASteps.single hst1)
    (guard_trap (code := code) (pc := x.pc + 1) (m := x1) (c := .ne) (t := .divideByZero)
      (f := logicFlags (0#64 &&& 0#64)) (by rw [e]; exact ⟨f1, f2, trivial⟩) hpc1 hfl hhold)

/-- The division instruction after the zero guard: `x9 := f x9 x10`. -/
theorem divop_step {i : Instr Nat} (f : W → W → W)
    (hi : ∀ m : M, exec i m = .next (m.arith x9 (f (m.regs x9) (m.regs x10))))
    (hf : code[x.pc]? = some i) {a b : W} (ha : x.regs x9 = a) (hb : x.regs x10 = b) :
    ∃ x', step code x = .next x' ∧ x'.regs x9 = f a b ∧ x'.pc = x.pc + 1 ∧
      x'.mem = x.mem ∧ (∀ r, r ≠ x9 → x'.regs r = x.regs r) := by
  refine ⟨x.arith x9 (f (x.regs x9) (x.regs x10)), by rw [astep_of_fetch hf, hi], ?_,
    by simp [M.arith], by simp [M.arith, M.setReg], ?_⟩
  · simp [M.arith, M.setReg, ha, hb]
  · intro r h; simp [M.arith, M.setReg, h]

/-- `div` and `sdiv` share their lowering shape: load both operands, trap on a zero divisor,
divide into `x9`, store and pop. -/
theorem sim_divop_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x)
    (hpc : x.pc = base) (i : Instr Nat) (f : W → W → W)
    (hi : ∀ m : M, exec i m = .next (m.arith x9 (f (m.regs x9) (m.regs x10))))
    (hat : AAt code base (uf L 2 base ++ [.load x10 Reg.x19 0, .load x9 Reg.x19 8, .test x10 x10,
      .jcc .ne (base + ufSize 2 + 5), .exitTrap .divideByZero, i, .store Reg.x19 8 x9,
      .addImm Reg.x19 8]))
    {a b : W} {d : List W} (hd : s.dstack = b :: a :: d) (hb : b ≠ 0#64) :
    ∃ x', ASteps code x x' ∧ Rel0 c p { s with dstack := f a b :: d } x' ∧
      x'.pc = base + (ufSize 2 + 8) := by
  obtain ⟨hatuf, hatr⟩ := aat_append.mp hat
  have hufl : (uf L 2 base).length = 4 := by simp [uf]
  rw [hufl] at hatr
  obtain ⟨f0, f1, f2, f3, f4, f5, f6, f7, _⟩ := hatr
  have hk : 2 ≤ s.dstack.length := by simp [hd]
  obtain ⟨x1, hs1, hr1, hpc1, hm1, _⟩ := uf_pass hg hs hL (by decide) (by decide) hk hpc hatuf
  obtain ⟨x2, hs2, hr2, hpc2, hv2, ho2, _⟩ := ld_step (code := code) hr1 (j := 0) (v := b)
    (by simp [hd]) (rd := x10) (by simp) (disp := 0) (by simp) (fetch_cast f0 (by omega))
  obtain ⟨x3, hs3, hr3, hpc3, hv3, ho3, _⟩ := ld_step (code := code) hr2 (j := 1) (v := a)
    (by simp [hd]) (rd := x9) (by simp) (disp := 8) (by simp) (fetch_cast f1 (by omega))
  have hcx3 : x3.regs x10 = b := by rw [ho3 x10 (by decide), hv2]
  obtain ⟨x4, hs4, hr4, hpc4, hreg4, hm4⟩ := zg_pass (code := code) hr3 hcx3 hb
    (t := base + ufSize 2 + 5) (by simp [ufSize]; omega)
    ⟨fetch_cast f2 (by omega), fetch_cast f3 (by omega), fetch_cast f4 (by omega), trivial⟩
  have hax4 : x4.regs x9 = a := by rw [hreg4, hv3]
  have hcx4 : x4.regs x10 = b := by rw [hreg4, hcx3]
  obtain ⟨x5, hst5, hax5, hpc5, hm5, ho5⟩ := divop_step (code := code) (x := x4) f hi
    (fetch_cast f5 (by omega)) hax4 hcx4
  have hr5 : Rel0 c p s x5 := rel0_scratch hr4 hm5 (fun r h1 _ _ _ => ho5 r h1)
  obtain ⟨x6, hs6, hr6, hpc6, _⟩ := st_step (code := code) hg hr5 (j := 1) (by simp [hd])
    (rs := x9) (disp := 8) (by simp) (fetch_cast f6 (by omega))
  have hlen : 1 ≤ ({ s with dstack := s.dstack.set 1 (x5.regs x9) } : State 64).dstack.length := by
    simp [hd]
  obtain ⟨x7, hs7, hr7, hpc7, _⟩ := adj_step (code := code) hg hr6 (n := 1) hlen (δ := 8) (by simp)
    (fetch_cast f7 (by omega))
  have hr7' : Rel0 c p { s with dstack := (s.dstack.set 1 (x5.regs x9)).drop 1 } x7 := hr7
  have e : (s.dstack.set 1 (x5.regs x9)).drop 1 = f a b :: d := by simp [hd, hax5]
  rw [e] at hr7'
  exact ⟨x7, ((((hs1.trans hs2).trans hs3).trans hs4).trans
    ((ASteps.single hst5).trans (hs6.trans hs7))), hr7', by simp [ufSize]; omega⟩

theorem sim_divop_zero (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x)
    (hpc : x.pc = base) (rest : List (Instr Nat))
    (hat : AAt code base (uf L 2 base ++ ([.load x10 Reg.x19 0, .load x9 Reg.x19 8, .test x10 x10,
      .jcc .ne (base + ufSize 2 + 5), .exitTrap .divideByZero] ++ rest)))
    {a : W} {d : List W} (hd : s.dstack = 0#64 :: a :: d) : AExec code x (.trapped .divideByZero) := by
  obtain ⟨hatuf, hatr⟩ := aat_append.mp hat
  have hufl : (uf L 2 base).length = 4 := by simp [uf]
  rw [hufl] at hatr
  obtain ⟨f0, f1, f2, f3, f4, _⟩ := hatr
  have hk : 2 ≤ s.dstack.length := by simp [hd]
  obtain ⟨x1, hs1, hr1, hpc1, hm1, _⟩ := uf_pass hg hs hL (by decide) (by decide) hk hpc hatuf
  obtain ⟨x2, hs2, hr2, hpc2, hv2, ho2, _⟩ := ld_step (code := code) hr1 (j := 0) (v := 0#64)
    (by simp [hd]) (rd := x10) (by simp) (disp := 0) (by simp) (fetch_cast f0 (by omega))
  obtain ⟨x3, hs3, hr3, hpc3, hv3, ho3, _⟩ := ld_step (code := code) hr2 (j := 1) (v := a)
    (by simp [hd]) (rd := x9) (by simp) (disp := 8) (by simp) (fetch_cast f1 (by omega))
  have hcx3 : x3.regs x10 = 0#64 := by rw [ho3 x10 (by decide), hv2]
  exact ASteps.trans hs1 (hs2.trans hs3) |> fun h => AExec.of_steps h (zg_trap (code := code) hr3 hcx3
    ⟨fetch_cast f2 (by omega), fetch_cast f3 (by omega), fetch_cast f4 (by omega), trivial⟩
    (t := base + ufSize 2 + 5) (by simp [ufSize]; omega))

theorem sim_div_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : AAt code base (lowerInstr L base off .div)) {a b : W} {d : List W}
    (hd : s.dstack = b :: a :: d) (hb : b ≠ 0#64) :
    ∃ x', ASteps code x x' ∧ Rel0 c p { s with dstack := a.udiv b :: d } x' ∧
      x'.pc = base + isize (.div : WordDialect.Instr 64) :=
  sim_divop_ok hg hL hs hpc (.udiv x9 x9 x10) BitVec.udiv (fun _ => rfl) hat hd hb

theorem sim_div_zero (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x)
    (hpc : x.pc = base) (hat : AAt code base (lowerInstr L base off .div)) {a : W} {d : List W}
    (hd : s.dstack = 0#64 :: a :: d) : AExec code x (.trapped .divideByZero) :=
  sim_divop_zero hg hL hs hpc [.udiv x9 x9 x10, .store Reg.x19 8 x9, .addImm Reg.x19 8] hat hd

theorem sim_sdiv_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : AAt code base (lowerInstr L base off .sdiv)) {a b : W} {d : List W}
    (hd : s.dstack = b :: a :: d) (hb : b ≠ 0#64) :
    ∃ x', ASteps code x x' ∧ Rel0 c p { s with dstack := a.sdiv b :: d } x' ∧
      x'.pc = base + isize (.sdiv : WordDialect.Instr 64) :=
  sim_divop_ok hg hL hs hpc (.sdiv x9 x9 x10) BitVec.sdiv (fun _ => rfl) hat hd hb

theorem sim_sdiv_zero (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x)
    (hpc : x.pc = base) (hat : AAt code base (lowerInstr L base off .sdiv)) {a : W} {d : List W}
    (hd : s.dstack = 0#64 :: a :: d) : AExec code x (.trapped .divideByZero) :=
  sim_divop_zero hg hL hs hpc [.sdiv x9 x9 x10, .store Reg.x19 8 x9, .addImm Reg.x19 8] hat hd

theorem cmov_ne_step (hf : code[x.pc]? = some (.cmov .ne x9 x12)) {cc : W}
    (hfl : x.flags = some (logicFlags (cc &&& cc))) :
    ∃ x', step code x = .next x' ∧ x'.pc = x.pc + 1 ∧ x'.mem = x.mem ∧
      x'.regs x9 = (if cc = 0#64 then x.regs x9 else x.regs x12) ∧
      (∀ r, r ≠ x9 → x'.regs r = x.regs r) := by
  by_cases hc : cc = 0#64
  · subst hc
    refine ⟨x.adv, ?_, by simp [M.adv], by simp [M.adv], by simp [M.adv], ?_⟩
    · rw [astep_of_fetch hf]; simp [exec, hfl, Cc.holds, logicFlags]
    · intro r _; simp [M.adv]
  · refine ⟨x.mov x9 (x.regs x12), ?_, by simp [M.mov, M.setReg, M.adv],
      by simp [M.mov, M.setReg, M.adv], by simp [M.mov, M.setReg, M.adv, hc], ?_⟩
    · rw [astep_of_fetch hf]; simp [exec, hfl, Cc.holds, logicFlags, hc]
    · intro r h; simp [M.mov, M.setReg, M.adv, h]

theorem sim_select_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x)
    (hpc : x.pc = base) (hat : AAt code base (lowerInstr L base off .select)) {cc y v : W}
    {d : List W} (hd : s.dstack = cc :: y :: v :: d) :
    ∃ x', ASteps code x x' ∧
      Rel0 c p { s with dstack := (if Word.isTrue cc then v else y) :: d } x' ∧
      x'.pc = base + isize (.select : WordDialect.Instr 64) := by
  have hat' : AAt code base (uf L 3 base ++ [.load x10 Reg.x19 0, .load x9 Reg.x19 8,
      .load x12 Reg.x19 16, .test x10 x10, .cmov .ne x9 x12, .store Reg.x19 16 x9,
      .addImm Reg.x19 16]) := hat
  obtain ⟨hatuf, hatr⟩ := aat_append.mp hat'
  have hufl : (uf L 3 base).length = 4 := by simp [uf]
  rw [hufl] at hatr
  obtain ⟨f0, f1, f2, f3, f4, f5, f6, _⟩ := hatr
  have hk : 3 ≤ s.dstack.length := by simp [hd]
  obtain ⟨x1, hs1, hr1, hpc1, hm1, _⟩ := uf_pass hg hs hL (by decide) (by decide) hk hpc hatuf
  obtain ⟨x2, hs2, hr2, hpc2, hv2, ho2, _⟩ := ld_step (code := code) hr1 (j := 0) (v := cc)
    (by simp [hd]) (rd := x10) (by simp) (disp := 0) (by simp) (fetch_cast f0 (by omega))
  obtain ⟨x3, hs3, hr3, hpc3, hv3, ho3, _⟩ := ld_step (code := code) hr2 (j := 1) (v := y)
    (by simp [hd]) (rd := x9) (by simp) (disp := 8) (by simp) (fetch_cast f1 (by omega))
  obtain ⟨x4, hs4, hr4, hpc4, hv4, ho4, _⟩ := ld_step (code := code) hr3 (j := 2) (v := v)
    (by simp [hd]) (rd := x12) (by simp) (disp := 16) (by simp) (fetch_cast f2 (by omega))
  have hcx4 : x4.regs x10 = cc := by rw [ho4 x10 (by decide), ho3 x10 (by decide), hv2]
  have hax4 : x4.regs x9 = y := by rw [ho4 x9 (by decide), hv3]
  -- test x10, x10
  let x5 : M := { x4.adv with flags := some (logicFlags (x4.regs x10 &&& x4.regs x10)) }
  have hst5 : step code x4 = .next x5 := by
    rw [astep_of_fetch (m := x4) (fetch_cast f3 (by omega))]; rfl
  have hr5 : Rel0 c p s x5 := hr4.congr rfl rfl rfl rfl rfl rfl rfl
  have hpc5 : x5.pc = base + 4 + 4 := by simp [x5, M.adv]; omega
  have hfl5 : x5.flags = some (logicFlags (cc &&& cc)) := by simp [x5, hcx4]
  have hax5 : x5.regs x9 = y := by simpa [x5, M.adv] using hax4
  have hbx5 : x5.regs x12 = v := by simpa [x5, M.adv] using hv4
  obtain ⟨x6, hst6, hpc6, hm6, hax6, ho6⟩ := cmov_ne_step (code := code) (x := x5)
    (fetch_cast f4 (by omega)) hfl5
  have hr6 : Rel0 c p s x6 := rel0_scratch hr5 hm6 (fun r h1 h2 h3 h4 => ho6 r h1)
  have hval : x6.regs x9 = (if Word.isTrue cc then v else y) := by
    rw [hax6, hax5, hbx5]
    by_cases hc : cc = 0#64 <;> simp [Word.isTrue, hc]
  obtain ⟨x7, hs7, hr7, hpc7, _⟩ := st_step (code := code) hg hr6 (j := 2) (by simp [hd])
    (rs := x9) (disp := 16) (by simp) (fetch_cast f5 (by omega))
  have hlen : 2 ≤ ({ s with dstack := s.dstack.set 2 (x6.regs x9) } : State 64).dstack.length := by
    simp [hd]
  obtain ⟨x8, hs8, hr8, hpc8, _⟩ := adj_step (code := code) hg hr7 (n := 2) hlen (δ := 16) (by simp)
    (fetch_cast f6 (by omega))
  have hr8' : Rel0 c p { s with dstack := (s.dstack.set 2 (x6.regs x9)).drop 2 } x8 := hr8
  have e : (s.dstack.set 2 (x6.regs x9)).drop 2 = (if Word.isTrue cc then v else y) :: d := by
    simp [hd, hval]
  rw [e] at hr8'
  exact ⟨x8, (((((((hs1.trans hs2).trans hs3).trans hs4).trans (ASteps.single hst5)).trans
    (ASteps.single hst6)).trans hs7).trans hs8), hr8', by simp [isize, ufSize]; omega⟩

end Div

end A64
end WordDialect
