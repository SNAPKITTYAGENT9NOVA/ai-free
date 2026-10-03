import X86.SimMemOps

/-!
# X86.SimDiv

`select`, `div`, `sdiv`: the three-operand select, and the divisions with their zero guard
(`divideByZero` trap), the `-1` special case of `sdiv` (avoiding the hardware overflow fault), and
the relation between `idiv` and `BitVec.sdiv`.
-/

namespace WordDialect
namespace X86

open Reg

section Div

variable {c : Cfg} {p : Prog 64} {s : State 64} {x : M} {code : List (Instr Nat)}
  {L : Layout} {base : Nat} {off : Nat → Nat}

/-- `Rel0` ignores scratch registers. -/
theorem rel0_scratch (hs : Rel0 c p s x) {x' : M} (hm : x'.mem = x.mem)
    (hr : ∀ r, r ≠ rax → r ≠ rcx → r ≠ rdx → r ≠ rbx → x'.regs r = x.regs r) : Rel0 c p s x' :=
  hs.congr hm (hr _ (by decide) (by decide) (by decide) (by decide))
    (hr _ (by decide) (by decide) (by decide) (by decide))
    (hr _ (by decide) (by decide) (by decide) (by decide))
    (hr _ (by decide) (by decide) (by decide) (by decide))
    (hr _ (by decide) (by decide) (by decide) (by decide))

theorem zg_pass (hs : Rel0 c p s x) {b : W} (hb : x.regs rcx = b) (hne : b ≠ 0#64) {t : Nat}
    (ht : t = x.pc + 3)
    (hat : XAt code x.pc [.test rcx rcx, .jcc .ne t, .exitTrap .divideByZero]) :
    ∃ x', XSteps code x x' ∧ Rel0 c p s x' ∧ x'.pc = x.pc + 3 ∧ x'.regs = x.regs ∧
      x'.mem = x.mem := by
  obtain ⟨f0, f1, f2, _⟩ := hat
  let x1 : M := { x.adv with flags := some (logicFlags (x.regs rcx &&& x.regs rcx)) }
  have hst1 : step code x = .next x1 := by rw [xstep_of_fetch f0]; rfl
  have hpc1 : x1.pc = x.pc + 1 := by simp [x1, M.adv]
  have hfl : x1.flags = some (logicFlags (b &&& b)) := by simp [x1, hb]
  have hhold : Cc.ne.holds (logicFlags (b &&& b)) = true := by simp [Cc.holds, logicFlags, hne]
  have e : x.pc + 1 + 2 = t := by omega
  have hg := guard_pass (code := code) (pc := x.pc + 1) (m := x1) (c := .ne) (t := .divideByZero)
    (f := logicFlags (b &&& b)) (by rw [e]; exact ⟨f1, f2, trivial⟩) hpc1 hfl hhold
  refine ⟨{ x1 with pc := x.pc + 1 + 2 }, (XSteps.single hst1).trans hg, ?_, by simp, rfl, rfl⟩
  exact hs.congr rfl rfl rfl rfl rfl rfl

theorem zg_trap (hs : Rel0 c p s x) (hb : x.regs rcx = 0#64) {t : Nat}
    (hat : XAt code x.pc [.test rcx rcx, .jcc .ne t, .exitTrap .divideByZero]) (ht : t = x.pc + 3) :
    XExec code x (.trapped .divideByZero) := by
  obtain ⟨f0, f1, f2, _⟩ := hat
  let x1 : M := { x.adv with flags := some (logicFlags (x.regs rcx &&& x.regs rcx)) }
  have hst1 : step code x = .next x1 := by rw [xstep_of_fetch f0]; rfl
  have hpc1 : x1.pc = x.pc + 1 := by simp [x1, M.adv]
  have hfl : x1.flags = some (logicFlags (0#64 &&& 0#64)) := by simp [x1, hb]
  have hhold : Cc.ne.holds (logicFlags (0#64 &&& 0#64)) = false := by simp [Cc.holds, logicFlags]
  have e : x.pc + 1 + 2 = t := by omega
  exact XExec.of_steps (XSteps.single hst1)
    (guard_trap (code := code) (pc := x.pc + 1) (m := x1) (c := .ne) (t := .divideByZero)
      (f := logicFlags (0#64 &&& 0#64)) (by rw [e]; exact ⟨f1, f2, trivial⟩) hpc1 hfl hhold)

theorem div_step (hf : code[x.pc]? = some (.div rcx)) {a b : W} (ha : x.regs rax = a)
    (hb : x.regs rcx = b) (hd : x.regs rdx = 0#64) (hne : b ≠ 0#64) :
    ∃ x', step code x = .next x' ∧ x'.regs rax = a.udiv b ∧ x'.pc = x.pc + 1 ∧
      x'.mem = x.mem ∧ (∀ r, r ≠ rax → r ≠ rdx → x'.regs r = x.regs r) := by
  have hq : a.toNat / b.toNat < 2 ^ 64 := Nat.lt_of_le_of_lt (Nat.div_le_self _ _) a.isLt
  have e : step code x = .next { ((x.setReg rax (BitVec.ofNat 64 (a.toNat / b.toNat))).setReg rdx
      (BitVec.ofNat 64 (a.toNat % b.toNat))) with flags := none, pc := x.pc + 1 } := by
    rw [xstep_of_fetch hf]
    simp [exec, hb, hd, ha, hne, hq]
  refine ⟨_, e, ?_, rfl, rfl, ?_⟩
  · simp [M.setReg, BitVec.udiv_def]
  · intro r h1 h2; simp [M.setReg, h1, h2]

theorem sim_div_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : XAt code base (lowerInstr L base off .div)) {a b : W} {d : List W}
    (hd : s.dstack = b :: a :: d) (hb : b ≠ 0#64) :
    ∃ x', XSteps code x x' ∧ Rel0 c p { s with dstack := a.udiv b :: d } x' ∧
      x'.pc = base + isize (.div : WordDialect.Instr 64) := by
  have hat' : XAt code base (uf L 2 base ++ [.load rcx Reg.r15 0, .load rax Reg.r15 8, .test rcx rcx,
      .jcc .ne (base + ufSize 2 + 5), .exitTrap .divideByZero, .movImm rdx 0#64, .div rcx,
      .store Reg.r15 8 rax, .addImm Reg.r15 8]) := hat
  obtain ⟨hatuf, hatr⟩ := xat_append.mp hat'
  have hufl : (uf L 2 base).length = 4 := by simp [uf]
  rw [hufl] at hatr
  obtain ⟨f0, f1, f2, f3, f4, f5, f6, f7, f8, _⟩ := hatr
  have hk : 2 ≤ s.dstack.length := by simp [hd]
  obtain ⟨x1, hs1, hr1, hpc1, hm1, _⟩ := uf_pass hg hs hL (by decide) (by decide) hk hpc hatuf
  obtain ⟨x2, hs2, hr2, hpc2, hv2, ho2, _⟩ := ld_step (code := code) hr1 (j := 0) (v := b)
    (by simp [hd]) (rd := rcx) (by simp) (disp := 0) (by simp) (fetch_cast f0 (by omega))
  obtain ⟨x3, hs3, hr3, hpc3, hv3, ho3, _⟩ := ld_step (code := code) hr2 (j := 1) (v := a)
    (by simp [hd]) (rd := rax) (by simp) (disp := 8) (by simp) (fetch_cast f1 (by omega))
  have hcx3 : x3.regs rcx = b := by rw [ho3 rcx (by decide), hv2]
  obtain ⟨x4, hs4, hr4, hpc4, hreg4, _⟩ := zg_pass (code := code) hr3 hcx3 hb
    (t := base + ufSize 2 + 5) (by simp [ufSize]; omega)
    ⟨fetch_cast f2 (by omega), fetch_cast f3 (by omega), fetch_cast f4 (by omega), trivial⟩
  obtain ⟨x5, hs5, hr5, hpc5, hv5, ho5, hm5⟩ := movimm_step (code := code) hr4 (rd := rdx) (by simp)
    (v := 0#64) (fetch_cast f5 (by omega))
  have hax5 : x5.regs rax = a := by rw [ho5 rax (by decide), hreg4, hv3]
  have hcx5 : x5.regs rcx = b := by rw [ho5 rcx (by decide), hreg4, hcx3]
  obtain ⟨x6, hst6, hax6, hpc6, hm6, ho6⟩ := div_step (code := code) (x := x5)
    (fetch_cast f6 (by omega)) hax5 hcx5 hv5 hb
  have hr6 : Rel0 c p s x6 := rel0_scratch hr5 hm6 (fun r h1 h2 h3 h4 => ho6 r h1 h3)
  obtain ⟨x7, hs7, hr7, hpc7, hreg7⟩ := st_step (code := code) hg hr6 (j := 1) (by simp [hd])
    (rs := rax) (disp := 8) (by simp) (fetch_cast f7 (by omega))
  have hlen : 1 ≤ ({ s with dstack := s.dstack.set 1 (x6.regs rax) } : State 64).dstack.length := by
    simp [hd]
  obtain ⟨x8, hs8, hr8, hpc8, _⟩ := adj_step (code := code) hg hr7 (n := 1) hlen (δ := 8) (by simp)
    (fetch_cast f8 (by omega))
  have hr8' : Rel0 c p { s with dstack := (s.dstack.set 1 (x6.regs rax)).drop 1 } x8 := hr8
  have e : (s.dstack.set 1 (x6.regs rax)).drop 1 = a.udiv b :: d := by simp [hd, hax6]
  rw [e] at hr8'
  exact ⟨x8, ((((hs1.trans hs2).trans hs3).trans hs4).trans hs5).trans
    ((XSteps.single hst6).trans (hs7.trans hs8)), hr8', by simp [isize, ufSize]; omega⟩

theorem sim_div_zero (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x)
    (hpc : x.pc = base) (hat : XAt code base (lowerInstr L base off .div)) {a : W} {d : List W}
    (hd : s.dstack = 0#64 :: a :: d) : XExec code x (.trapped .divideByZero) := by
  have hat' : XAt code base (uf L 2 base ++ [.load rcx Reg.r15 0, .load rax Reg.r15 8, .test rcx rcx,
      .jcc .ne (base + ufSize 2 + 5), .exitTrap .divideByZero, .movImm rdx 0#64, .div rcx,
      .store Reg.r15 8 rax, .addImm Reg.r15 8]) := hat
  obtain ⟨hatuf, hatr⟩ := xat_append.mp hat'
  have hufl : (uf L 2 base).length = 4 := by simp [uf]
  rw [hufl] at hatr
  obtain ⟨f0, f1, f2, f3, f4, _⟩ := hatr
  have hk : 2 ≤ s.dstack.length := by simp [hd]
  obtain ⟨x1, hs1, hr1, hpc1, hm1, _⟩ := uf_pass hg hs hL (by decide) (by decide) hk hpc hatuf
  obtain ⟨x2, hs2, hr2, hpc2, hv2, ho2, _⟩ := ld_step (code := code) hr1 (j := 0) (v := 0#64)
    (by simp [hd]) (rd := rcx) (by simp) (disp := 0) (by simp) (fetch_cast f0 (by omega))
  obtain ⟨x3, hs3, hr3, hpc3, hv3, ho3, _⟩ := ld_step (code := code) hr2 (j := 1) (v := a)
    (by simp [hd]) (rd := rax) (by simp) (disp := 8) (by simp) (fetch_cast f1 (by omega))
  have hcx3 : x3.regs rcx = 0#64 := by rw [ho3 rcx (by decide), hv2]
  exact XExec.of_steps (((hs1.trans hs2).trans hs3)) (zg_trap (code := code) hr3 hcx3
    ⟨fetch_cast f2 (by omega), fetch_cast f3 (by omega), fetch_cast f4 (by omega), trivial⟩
    (t := base + ufSize 2 + 5) (by simp [ufSize]; omega))

theorem ofInt_m1 : BitVec.ofInt 64 (-1) = -(1#64) := by decide

theorem sdiv_m1 (a : W) : a.sdiv (BitVec.ofInt 64 (-1)) = 0#64 - a := by
  rw [ofInt_m1, BitVec.sdiv_neg (by decide), BitVec.sdiv_one]; simp

theorem dividend_eq (a : W) :
    (if a.msb then BitVec.allOnes 64 else 0#64).toInt * 2 ^ 64 + (a.toNat : Int) = a.toInt := by
  rw [BitVec.toInt_eq_msb_cond a]
  cases h : a.msb <;> simp [h] <;> omega

theorem idiv_step (hf : code[x.pc]? = some (.idiv rcx)) {a b : W} (ha : x.regs rax = a)
    (hb : x.regs rcx = b) (hd : x.regs rdx = if a.msb then BitVec.allOnes 64 else 0#64)
    (hne : b ≠ 0#64) (hm1 : b ≠ -(1#64)) :
    ∃ x', step code x = .next x' ∧ x'.regs rax = a.sdiv b ∧ x'.pc = x.pc + 1 ∧
      x'.mem = x.mem ∧ (∀ r, r ≠ rax → r ≠ rdx → x'.regs r = x.regs r) := by
  have hq : (a.sdiv b).toInt = Int.tdiv a.toInt b.toInt :=
    BitVec.toInt_sdiv_of_ne_or_ne a b (Or.inr hm1)
  have hlo := BitVec.le_toInt (a.sdiv b)
  have hhi : (a.sdiv b).toInt < 2 ^ (64 - 1) := BitVec.toInt_lt
  rw [hq] at hlo hhi
  have hrange : -(2 ^ 63 : Int) ≤ Int.tdiv a.toInt b.toInt ∧ Int.tdiv a.toInt b.toInt < 2 ^ 63 := by
    constructor <;> simpa using ‹_›
  have hdiv : ((x.regs rdx).toInt * 2 ^ 64 + ((x.regs rax).toNat : Int)) = a.toInt := by
    rw [hd, ha]; exact dividend_eq a
  have hofq : BitVec.ofInt 64 (Int.tdiv a.toInt b.toInt) = a.sdiv b := by
    rw [← hq]; simp
  have e : step code x = .next { ((x.setReg rax (a.sdiv b)).setReg rdx
      (BitVec.ofInt 64 (Int.tmod a.toInt b.toInt))) with flags := none, pc := x.pc + 1 } := by
    rw [xstep_of_fetch hf]
    simp only [exec, hb, hne, ite_false, hdiv, hrange, and_self, ite_true, hofq]
  refine ⟨_, e, ?_, rfl, rfl, ?_⟩
  · simp [M.setReg]
  · intro r h1 h2; simp [M.setReg, h1, h2]

/-- Core of `sdiv`, from the `cmpImm rcx, -1` on: both branches end with `rax = a.sdiv b`. -/
theorem sdiv_core (hs : Rel0 c p s x) {a b : W} (ha : x.regs rax = a) (hb : x.regs rcx = b)
    (hne : b ≠ 0#64) {t1 t2 : Nat} (ht1 : t1 = x.pc + 4) (ht2 : t2 = x.pc + 6)
    (hat : XAt code x.pc [.cmpImm rcx (-1), .jcc .ne t1, .neg rax, .jmp t2, .cqo, .idiv rcx]) :
    ∃ x', XSteps code x x' ∧ Rel0 c p s x' ∧ x'.pc = x.pc + 6 ∧ x'.regs rax = a.sdiv b := by
  obtain ⟨f0, f1, f2, f3, f4, f5, _⟩ := hat
  let x1 : M := { x.adv with flags := some (subFlags (x.regs rcx) (BitVec.ofInt 64 (-1))) }
  have hst1 : step code x = .next x1 := by rw [xstep_of_fetch f0]; rfl
  have hpc1 : x1.pc = x.pc + 1 := by simp [x1, M.adv]
  have hfl : x1.flags = some (subFlags b (BitVec.ofInt 64 (-1))) := by simp [x1, hb]
  have hr1 : Rel0 c p s x1 := hs.congr rfl rfl rfl rfl rfl rfl
  have hax1 : x1.regs rax = a := by simpa [x1, M.adv] using ha
  have hcx1 : x1.regs rcx = b := by simpa [x1, M.adv] using hb
  by_cases hb1 : b = BitVec.ofInt 64 (-1)
  · -- b = -1: jcc falls through, neg rax, jmp to the join point
    have hst2 : step code x1 = .next x1.adv := by
      rw [xstep_of_fetch (m := x1) (fetch_cast f1 (by omega))]
      simp [exec, hfl, holds_ne, hb1, M.adv]
    have hpc2 : x1.adv.pc = x.pc + 2 := by simp [M.adv, hpc1]
    have hr2 : Rel0 c p s x1.adv := hr1.congr rfl rfl rfl rfl rfl rfl
    have hax2 : x1.adv.regs rax = a := by simpa [M.adv] using hax1
    let x3 := x1.adv.arith rax (0#64 - x1.adv.regs rax)
    have hst3 : step code x1.adv = .next x3 := by
      rw [xstep_of_fetch (m := x1.adv) (fetch_cast f2 (by omega))]; rfl
    have hpc3 : x3.pc = x.pc + 3 := by simp [x3, M.arith, M.setReg, hpc2]
    have hr3 : Rel0 c p s x3 := arith_rel0 hr2 rax (scratch_ne rax (by simp)) _
    have hst4 : step code x3 = .next { x3 with pc := t2 } := by
      rw [xstep_of_fetch (m := x3) (fetch_cast f3 (by omega))]; rfl
    refine ⟨{ x3 with pc := t2 }, (((XSteps.single hst1).trans (XSteps.single hst2)).trans
      (XSteps.single hst3)).trans (XSteps.single hst4), hr3.congr rfl rfl rfl rfl rfl rfl,
      by simp [ht2], ?_⟩
    have h3 : x3.regs rax = 0#64 - a := by simp [x3, M.arith, M.setReg, hax2]
    show x3.regs rax = a.sdiv b
    rw [h3, hb1, sdiv_m1]
  · -- b ≠ -1: jump to cqo; idiv
    have hbm : b ≠ -(1#64) := by rwa [← ofInt_m1]
    have hst2 : step code x1 = .next { x1 with pc := t1 } := by
      rw [xstep_of_fetch (m := x1) (fetch_cast f1 (by omega))]
      have hb1' : (b != BitVec.ofInt 64 (-1)) = true := by simpa using hb1
      simp only [exec, hfl, holds_ne, hb1', ite_true]
    have hr2 : Rel0 c p s { x1 with pc := t1 } := hr1.congr rfl rfl rfl rfl rfl rfl
    have hax2 : ({ x1 with pc := t1 } : M).regs rax = a := hax1
    have hcx2 : ({ x1 with pc := t1 } : M).regs rcx = b := hcx1
    let x3 : M := ({ x1 with pc := t1 } : M).mov rdx (if (({ x1 with pc := t1 } : M).regs rax).msb
      then BitVec.allOnes 64 else 0#64)
    have hst3 : step code { x1 with pc := t1 } = .next x3 := by
      rw [xstep_of_fetch (m := { x1 with pc := t1 }) (fetch_cast f4 (by simp; omega))]; rfl
    have hr3 : Rel0 c p s x3 := mov_rel0 hr2 rdx (scratch_ne rdx (by simp)) _
    have hpc3 : x3.pc = x.pc + 5 := by simp [x3, M.mov, M.setReg, M.adv]; omega
    have hax3 : x3.regs rax = a := by simp [x3, M.mov, M.setReg, M.adv]; exact hax2
    have hcx3 : x3.regs rcx = b := by simp [x3, M.mov, M.setReg, M.adv]; exact hcx2
    have hdx3 : x3.regs rdx = if a.msb then BitVec.allOnes 64 else 0#64 := by
      simp [x3, M.mov, M.setReg, M.adv]; rw [hax2]
    obtain ⟨x4, hst4, hax4, hpc4, hm4, ho4⟩ := idiv_step (code := code) (x := x3)
      (fetch_cast f5 (by omega)) hax3 hcx3 hdx3 hne hbm
    refine ⟨x4, (((XSteps.single hst1).trans (XSteps.single hst2)).trans (XSteps.single hst3)).trans
      (XSteps.single hst4), rel0_scratch hr3 hm4 (fun r h1 h2 h3 h4 => ho4 r h1 h3), by omega, hax4⟩

theorem sim_sdiv_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : XAt code base (lowerInstr L base off .sdiv)) {a b : W} {d : List W}
    (hd : s.dstack = b :: a :: d) (hb : b ≠ 0#64) :
    ∃ x', XSteps code x x' ∧ Rel0 c p { s with dstack := a.sdiv b :: d } x' ∧
      x'.pc = base + isize (.sdiv : WordDialect.Instr 64) := by
  have hat' : XAt code base (uf L 2 base ++ [.load rcx Reg.r15 0, .load rax Reg.r15 8, .test rcx rcx,
      .jcc .ne (base + ufSize 2 + 5), .exitTrap .divideByZero, .cmpImm rcx (-1),
      .jcc .ne (base + ufSize 2 + 9), .neg rax, .jmp (base + ufSize 2 + 11), .cqo, .idiv rcx,
      .store Reg.r15 8 rax, .addImm Reg.r15 8]) := hat
  obtain ⟨hatuf, hatr⟩ := xat_append.mp hat'
  have hufl : (uf L 2 base).length = 4 := by simp [uf]
  rw [hufl] at hatr
  obtain ⟨f0, f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12, _⟩ := hatr
  have hk : 2 ≤ s.dstack.length := by simp [hd]
  obtain ⟨x1, hs1, hr1, hpc1, hm1, _⟩ := uf_pass hg hs hL (by decide) (by decide) hk hpc hatuf
  obtain ⟨x2, hs2, hr2, hpc2, hv2, ho2, _⟩ := ld_step (code := code) hr1 (j := 0) (v := b)
    (by simp [hd]) (rd := rcx) (by simp) (disp := 0) (by simp) (fetch_cast f0 (by omega))
  obtain ⟨x3, hs3, hr3, hpc3, hv3, ho3, _⟩ := ld_step (code := code) hr2 (j := 1) (v := a)
    (by simp [hd]) (rd := rax) (by simp) (disp := 8) (by simp) (fetch_cast f1 (by omega))
  have hcx3 : x3.regs rcx = b := by rw [ho3 rcx (by decide), hv2]
  obtain ⟨x4, hs4, hr4, hpc4, hreg4, _⟩ := zg_pass (code := code) hr3 hcx3 hb
    (t := base + ufSize 2 + 5) (by simp [ufSize]; omega)
    ⟨fetch_cast f2 (by omega), fetch_cast f3 (by omega), fetch_cast f4 (by omega), trivial⟩
  have hax4 : x4.regs rax = a := by rw [hreg4, hv3]
  have hcx4 : x4.regs rcx = b := by rw [hreg4, hcx3]
  obtain ⟨x5, hs5, hr5, hpc5, hax5⟩ := sdiv_core (code := code) hr4 hax4 hcx4 hb
    (t1 := base + ufSize 2 + 9) (t2 := base + ufSize 2 + 11) (by simp [ufSize]; omega)
    (by simp [ufSize]; omega)
    ⟨fetch_cast f5 (by omega), fetch_cast f6 (by omega), fetch_cast f7 (by omega),
      fetch_cast f8 (by omega), fetch_cast f9 (by omega), fetch_cast f10 (by omega), trivial⟩
  obtain ⟨x6, hs6, hr6, hpc6, hreg6⟩ := st_step (code := code) hg hr5 (j := 1) (by simp [hd])
    (rs := rax) (disp := 8) (by simp) (fetch_cast f11 (by omega))
  have hlen : 1 ≤ ({ s with dstack := s.dstack.set 1 (x5.regs rax) } : State 64).dstack.length := by
    simp [hd]
  obtain ⟨x7, hs7, hr7, hpc7, _⟩ := adj_step (code := code) hg hr6 (n := 1) hlen (δ := 8) (by simp)
    (fetch_cast f12 (by omega))
  have hr7' : Rel0 c p { s with dstack := (s.dstack.set 1 (x5.regs rax)).drop 1 } x7 := hr7
  have e : (s.dstack.set 1 (x5.regs rax)).drop 1 = a.sdiv b :: d := by simp [hd, hax5]
  rw [e] at hr7'
  exact ⟨x7, (((((hs1.trans hs2).trans hs3).trans hs4).trans hs5).trans hs6).trans hs7, hr7',
    by simp [isize, ufSize]; omega⟩

theorem sim_sdiv_zero (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x)
    (hpc : x.pc = base) (hat : XAt code base (lowerInstr L base off .sdiv)) {a : W} {d : List W}
    (hd : s.dstack = 0#64 :: a :: d) : XExec code x (.trapped .divideByZero) := by
  have hat' : XAt code base (uf L 2 base ++ [.load rcx Reg.r15 0, .load rax Reg.r15 8, .test rcx rcx,
      .jcc .ne (base + ufSize 2 + 5), .exitTrap .divideByZero]) := by
    have h : XAt code base (uf L 2 base ++ [.load rcx Reg.r15 0, .load rax Reg.r15 8, .test rcx rcx,
      .jcc .ne (base + ufSize 2 + 5), .exitTrap .divideByZero, .cmpImm rcx (-1),
      .jcc .ne (base + ufSize 2 + 9), .neg rax, .jmp (base + ufSize 2 + 11), .cqo, .idiv rcx,
      .store Reg.r15 8 rax, .addImm Reg.r15 8]) := hat
    obtain ⟨h1, h2⟩ := xat_append.mp h
    refine xat_append.mpr ⟨h1, ?_⟩
    obtain ⟨g0, g1, g2, g3, g4, _⟩ := h2
    exact ⟨g0, g1, g2, g3, g4, trivial⟩
  obtain ⟨hatuf, hatr⟩ := xat_append.mp hat'
  have hufl : (uf L 2 base).length = 4 := by simp [uf]
  rw [hufl] at hatr
  obtain ⟨f0, f1, f2, f3, f4, _⟩ := hatr
  have hk : 2 ≤ s.dstack.length := by simp [hd]
  obtain ⟨x1, hs1, hr1, hpc1, hm1, _⟩ := uf_pass hg hs hL (by decide) (by decide) hk hpc hatuf
  obtain ⟨x2, hs2, hr2, hpc2, hv2, ho2, _⟩ := ld_step (code := code) hr1 (j := 0) (v := 0#64)
    (by simp [hd]) (rd := rcx) (by simp) (disp := 0) (by simp) (fetch_cast f0 (by omega))
  obtain ⟨x3, hs3, hr3, hpc3, hv3, ho3, _⟩ := ld_step (code := code) hr2 (j := 1) (v := a)
    (by simp [hd]) (rd := rax) (by simp) (disp := 8) (by simp) (fetch_cast f1 (by omega))
  have hcx3 : x3.regs rcx = 0#64 := by rw [ho3 rcx (by decide), hv2]
  exact XExec.of_steps (((hs1.trans hs2)).trans hs3) (zg_trap (code := code) hr3 hcx3
    ⟨fetch_cast f2 (by omega), fetch_cast f3 (by omega), fetch_cast f4 (by omega), trivial⟩
    (t := base + ufSize 2 + 5) (by simp [ufSize]; omega))

theorem cmov_ne_step (hf : code[x.pc]? = some (.cmov .ne rax rbx)) {cc : W}
    (hfl : x.flags = some (logicFlags (cc &&& cc))) :
    ∃ x', step code x = .next x' ∧ x'.pc = x.pc + 1 ∧ x'.mem = x.mem ∧
      x'.regs rax = (if cc = 0#64 then x.regs rax else x.regs rbx) ∧
      (∀ r, r ≠ rax → x'.regs r = x.regs r) := by
  by_cases hc : cc = 0#64
  · subst hc
    refine ⟨x.adv, ?_, by simp [M.adv], by simp [M.adv], by simp [M.adv], ?_⟩
    · rw [xstep_of_fetch hf]; simp [exec, hfl, Cc.holds, logicFlags]
    · intro r _; simp [M.adv]
  · refine ⟨x.mov rax (x.regs rbx), ?_, by simp [M.mov, M.setReg, M.adv],
      by simp [M.mov, M.setReg, M.adv], by simp [M.mov, M.setReg, M.adv, hc], ?_⟩
    · rw [xstep_of_fetch hf]; simp [exec, hfl, Cc.holds, logicFlags, hc]
    · intro r h; simp [M.mov, M.setReg, M.adv, h]

theorem sim_select_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x)
    (hpc : x.pc = base) (hat : XAt code base (lowerInstr L base off .select)) {cc y v : W}
    {d : List W} (hd : s.dstack = cc :: y :: v :: d) :
    ∃ x', XSteps code x x' ∧
      Rel0 c p { s with dstack := (if Word.isTrue cc then v else y) :: d } x' ∧
      x'.pc = base + isize (.select : WordDialect.Instr 64) := by
  have hat' : XAt code base (uf L 3 base ++ [.load rcx Reg.r15 0, .load rax Reg.r15 8,
      .load rbx Reg.r15 16, .test rcx rcx, .cmov .ne rax rbx, .store Reg.r15 16 rax,
      .addImm Reg.r15 16]) := hat
  obtain ⟨hatuf, hatr⟩ := xat_append.mp hat'
  have hufl : (uf L 3 base).length = 4 := by simp [uf]
  rw [hufl] at hatr
  obtain ⟨f0, f1, f2, f3, f4, f5, f6, _⟩ := hatr
  have hk : 3 ≤ s.dstack.length := by simp [hd]
  obtain ⟨x1, hs1, hr1, hpc1, hm1, _⟩ := uf_pass hg hs hL (by decide) (by decide) hk hpc hatuf
  obtain ⟨x2, hs2, hr2, hpc2, hv2, ho2, _⟩ := ld_step (code := code) hr1 (j := 0) (v := cc)
    (by simp [hd]) (rd := rcx) (by simp) (disp := 0) (by simp) (fetch_cast f0 (by omega))
  obtain ⟨x3, hs3, hr3, hpc3, hv3, ho3, _⟩ := ld_step (code := code) hr2 (j := 1) (v := y)
    (by simp [hd]) (rd := rax) (by simp) (disp := 8) (by simp) (fetch_cast f1 (by omega))
  obtain ⟨x4, hs4, hr4, hpc4, hv4, ho4, _⟩ := ld_step (code := code) hr3 (j := 2) (v := v)
    (by simp [hd]) (rd := rbx) (by simp) (disp := 16) (by simp) (fetch_cast f2 (by omega))
  have hcx4 : x4.regs rcx = cc := by rw [ho4 rcx (by decide), ho3 rcx (by decide), hv2]
  have hax4 : x4.regs rax = y := by rw [ho4 rax (by decide), hv3]
  -- test rcx, rcx
  let x5 : M := { x4.adv with flags := some (logicFlags (x4.regs rcx &&& x4.regs rcx)) }
  have hst5 : step code x4 = .next x5 := by
    rw [xstep_of_fetch (m := x4) (fetch_cast f3 (by omega))]; rfl
  have hr5 : Rel0 c p s x5 := hr4.congr rfl rfl rfl rfl rfl rfl
  have hpc5 : x5.pc = base + 4 + 4 := by simp [x5, M.adv]; omega
  have hfl5 : x5.flags = some (logicFlags (cc &&& cc)) := by simp [x5, hcx4]
  have hax5 : x5.regs rax = y := by simpa [x5, M.adv] using hax4
  have hbx5 : x5.regs rbx = v := by simpa [x5, M.adv] using hv4
  obtain ⟨x6, hst6, hpc6, hm6, hax6, ho6⟩ := cmov_ne_step (code := code) (x := x5)
    (fetch_cast f4 (by omega)) hfl5
  have hr6 : Rel0 c p s x6 := rel0_scratch hr5 hm6 (fun r h1 h2 h3 h4 => ho6 r h1)
  have hval : x6.regs rax = (if Word.isTrue cc then v else y) := by
    rw [hax6, hax5, hbx5]
    by_cases hc : cc = 0#64 <;> simp [Word.isTrue, hc]
  obtain ⟨x7, hs7, hr7, hpc7, _⟩ := st_step (code := code) hg hr6 (j := 2) (by simp [hd])
    (rs := rax) (disp := 16) (by simp) (fetch_cast f5 (by omega))
  have hlen : 2 ≤ ({ s with dstack := s.dstack.set 2 (x6.regs rax) } : State 64).dstack.length := by
    simp [hd]
  obtain ⟨x8, hs8, hr8, hpc8, _⟩ := adj_step (code := code) hg hr7 (n := 2) hlen (δ := 16) (by simp)
    (fetch_cast f6 (by omega))
  have hr8' : Rel0 c p { s with dstack := (s.dstack.set 2 (x6.regs rax)).drop 2 } x8 := hr8
  have e : (s.dstack.set 2 (x6.regs rax)).drop 2 = (if Word.isTrue cc then v else y) :: d := by
    simp [hd, hval]
  rw [e] at hr8'
  exact ⟨x8, (((((((hs1.trans hs2).trans hs3).trans hs4).trans (XSteps.single hst5)).trans
    (XSteps.single hst6)).trans hs7).trans hs8), hr8', by simp [isize, ufSize]; omega⟩

end Div

end X86
end WordDialect
