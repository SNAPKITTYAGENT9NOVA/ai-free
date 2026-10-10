import CM.SimMem

/-!
# CM.SimMemOps

The address bounds guard `movImm rt, memSize; bltu r0, rt, ok; exitTrap badAddress`, and the
simulation theorems for `push`, `pop`, `load`, `store`. `load` and `store` compute the cell's
address with `lsl r0, r0, #2; add r0, r0, r6` (`idx_steps`).
-/

namespace WordDialect
namespace CM

open Reg

section Ops

variable {c : Cfg} {p : Prog 32} {s : State 32} {x : M} {code : List (Instr Nat)}
  {L : Layout} {base : Nat} {off : Nat → Nat}

theorem ult_memSize {a : W} {n : Nat} (hn : n < 2 ^ 32) :
    a.ult (BitVec.ofNat 32 n) = decide (a.toNat < n) := by
  simp [BitVec.ult_eq_decide, BitVec.toNat_ofNat, Nat.mod_eq_of_lt hn]

/-- The bounds guard, passing case. -/
theorem addr_pass (hs : Rel0 c p s x) {rt : Reg} (hrt : rt = r1 ∨ rt = r2) {n : Nat}
    (hn : n < 2 ^ 32) {t : Nat} (ht : t = x.pc + 3) {a : W} (hrax : x.regs r0 = a) (ha : a.toNat < n)
    (hat : RAt code x.pc [.movImm rt (BitVec.ofNat 32 n), .bcc .ult r0 rt t,
      .exitTrap .badAddress]) :
    ∃ x', RSteps code x x' ∧ Rel0 c p s x' ∧ x'.pc = x.pc + 3 ∧ x'.regs r0 = a ∧
      (∀ r, r ≠ rt → x'.regs r = x.regs r) ∧ x'.mem = x.mem := by
  subst ht
  obtain ⟨f0, f1, f2, _⟩ := hat
  have hrt' : rt = r0 ∨ rt = r1 ∨ rt = r2 ∨ rt = r3 := by rcases hrt with h | h <;> simp [h]
  have hne : r0 ≠ rt := by rcases hrt with h | h <;> simp [h]
  obtain ⟨x1, hs1, hr1, hpc1, hv1, ho1, hm1⟩ := movimm_step (code := code) hs (rd := rt) hrt'
    (v := BitVec.ofNat 32 n) f0
  have hax1 : x1.regs r0 = a := by rw [ho1 r0 hne, hrax]
  have hhold : Cond.eval .ult (x1.regs r0) (x1.regs rt) = true := by
    simp only [Cond.eval, hax1, hv1]; rw [ult_memSize hn]; simpa using ha
  have hg := guard_pass (code := code) (pc := x.pc + 1) (m := x1) (t := .badAddress)
    ⟨fetch_cast f1 (by omega), fetch_cast f2 (by omega), trivial⟩ hpc1 hhold
  refine ⟨{ x1 with pc := x.pc + 1 + 2 }, hs1.trans hg, hr1.congr rfl rfl rfl rfl rfl rfl rfl,
    by simp, by simp [hax1], ?_, by simp [hm1]⟩
  intro r hr; simp [ho1 r hr]

/-- The bounds guard, failing case. -/
theorem addr_trap (hs : Rel0 c p s x) {rt : Reg} (hrt : rt = r1 ∨ rt = r2) {n : Nat}
    (hn : n < 2 ^ 32) {t : Nat} (ht : t = x.pc + 3) {a : W} (hrax : x.regs r0 = a) (ha : ¬ a.toNat < n)
    (hat : RAt code x.pc [.movImm rt (BitVec.ofNat 32 n), .bcc .ult r0 rt t,
      .exitTrap .badAddress]) :
    RExec code x (.trapped .badAddress) := by
  subst ht
  obtain ⟨f0, f1, f2, _⟩ := hat
  have hrt' : rt = r0 ∨ rt = r1 ∨ rt = r2 ∨ rt = r3 := by rcases hrt with h | h <;> simp [h]
  have hne : r0 ≠ rt := by rcases hrt with h | h <;> simp [h]
  obtain ⟨x1, hs1, hr1, hpc1, hv1, ho1, hm1⟩ := movimm_step (code := code) hs (rd := rt) hrt'
    (v := BitVec.ofNat 32 n) f0
  have hax1 : x1.regs r0 = a := by rw [ho1 r0 hne, hrax]
  have hhold : Cond.eval .ult (x1.regs r0) (x1.regs rt) = false := by
    simp only [Cond.eval, hax1, hv1]; rw [ult_memSize hn]; simpa using ha
  exact RExec.of_steps hs1
    (guard_trap (code := code) (pc := x.pc + 1) (m := x1) (t := .badAddress)
      ⟨fetch_cast f1 (by omega), fetch_cast f2 (by omega), trivial⟩ hpc1 hhold)

theorem sim_push_ok (hg : Geom c) (hs : Rel0 c p s x) (hpc : x.pc = base) {r : Nat}
    (hr : r < c.nregs) (hLd : L.dLim = ofN (c.dBase + 4))
    (hat : RAt code base (lowerInstr L base off (.push r)))
    (hfit : c.dBase + 4 * (s.dstack.length + 1) ≤ c.dEnd) :
    ∃ x', RSteps code x x' ∧ Rel0 c p { s with dstack := s.regs r :: s.dstack } x' ∧
      x'.pc = base + isize (.push r : WordDialect.Instr 32) := by
  obtain ⟨hato, f0, f1, f2⟩ := xat_ovf3 (L := L) (by exact hat)
  obtain ⟨x0, hs0, hr0, hpc0, _, _⟩ := ovfD_pass hg hs hLd hfit hpc hato
  have hst : step code x0 = .next (x0.mov r0 (s.regs r)) := by
    rw [rstep_of_fetch (by rw [hpc0]; exact f0), ld_reg hr0 hr r0 rfl]
  have hr1 : Rel0 c p s (x0.mov r0 (s.regs r)) := mov_rel0 hr0 r0 (scratch_ne r0 (by simp)) _
  have hpc1 : (x0.mov r0 (s.regs r)).pc = base + 3 + 1 := by simp [M.mov, M.setReg, M.adv, hpc0]
  obtain ⟨x2, hs2, hr2, hpc2, _⟩ := push_pair hg hr1 r0 (by decide) hfit
    ⟨fetch_cast f1 (by omega), fetch_cast f2 (by omega), trivial⟩
  have hv : (x0.mov r0 (s.regs r)).regs r0 = s.regs r := by simp [M.mov, M.setReg, M.adv]
  rw [hv] at hr2
  exact ⟨x2, (hs0.trans (RSteps.single hst)).trans hs2, hr2, by simp [isize]; omega⟩

theorem sim_push_ovf (hg : Geom c) (hs : Rel0 c p s x) (hpc : x.pc = base) {r : Nat}
    (hLd : L.dLim = ofN (c.dBase + 4)) (hat : RAt code base (lowerInstr L base off (.push r)))
    (h : ¬ c.dBase + 4 * (s.dstack.length + 1) ≤ c.dEnd) : RExec code x .overflow := by
  obtain ⟨hato, _⟩ := xat_ovf3 (L := L) (by exact hat)
  exact ovfD_trap hg hs hLd h hpc hato

theorem sim_pop_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    {r : Nat} (hr : r < c.nregs) (hat : RAt code base (lowerInstr L base off (.pop r)))
    {a : W} {d : List W} (hd : s.dstack = a :: d) :
    ∃ x', RSteps code x x' ∧
      Rel0 c p { s with dstack := d, regs := State.setReg s.regs r a } x' ∧
      x'.pc = base + isize (.pop r : WordDialect.Instr 32) := by
  have hat' : RAt code base (uf L 1 base ++ [.load r0 Reg.r4 0, .addImm Reg.r4 4,
      .store Reg.r5 (4 * (r : Int)) r0]) := hat
  obtain ⟨hatuf, hatr⟩ := rat_append.mp hat'
  have hufl : (uf L 1 base).length = 3 := by simp [uf]
  rw [hufl] at hatr
  obtain ⟨f0, f1, f2, _⟩ := hatr
  have hk : 1 ≤ s.dstack.length := by simp [hd]
  obtain ⟨x1, hs1, hr1, hpc1, hm1, _⟩ := uf_pass hg hs hL (by decide) (by decide) hk hpc hatuf
  obtain ⟨x2, hs2, hr2, hpc2, hv2, _, _⟩ := ld_step (code := code) hr1 (j := 0) (v := a)
    (by simp [hd]) (rd := r0) (by simp) (disp := 0) (by simp) (fetch_cast f0 (by omega))
  obtain ⟨x3, hs3, hr3, hpc3, ho3⟩ := adj_step (code := code) hg hr2 (n := 1) (by simp [hd])
    (δ := 4) (by simp) (fetch_cast f1 (by omega))
  have hax3 : x3.regs r0 = a := by rw [ho3 r0 (by decide), hv2]
  obtain ⟨mem', e4, hr4⟩ := st_reg hg hr3 hr r0 (disp := 4 * (r : Int)) rfl
  have hst4 : step code x3 = .next { x3.adv with mem := mem' } := by
    rw [rstep_of_fetch (fetch_cast f2 (by omega)), e4]
  have hr4' : Rel0 c p { s with dstack := s.dstack.drop 1, regs := State.setReg s.regs r (x3.regs r0) }
      { x3.adv with mem := mem' } := hr4
  have e : s.dstack.drop 1 = d := by simp [hd]
  rw [e, hax3] at hr4'
  exact ⟨_, ((hs1.trans hs2).trans hs3).trans (RSteps.single hst4), hr4',
    by simp [M.adv, isize, ufSize]; omega⟩

theorem sim_load_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hMs : L.memSize = c.M)
    (hs : Rel0 c p s x) (hpc : x.pc = base) (hat : RAt code base (lowerInstr L base off .load))
    {a v : W} {d : List W} (hd : s.dstack = a :: d) (hv : s.mem.read? a = some v) :
    ∃ x', RSteps code x x' ∧ Rel0 c p { s with dstack := v :: d } x' ∧
      x'.pc = base + isize (.load : WordDialect.Instr 32) := by
  have hat' : RAt code base (uf L 1 base ++ [.load r0 Reg.r4 0, .movImm r1 (BitVec.ofNat 32 L.memSize),
      .bcc .ult r0 r1 (base + ufSize 1 + 4), .exitTrap .badAddress, .shlImm r0 2, .add r0 Reg.r6,
      .load r0 r0 0, .store Reg.r4 0 r0]) := hat
  obtain ⟨hatuf, hatr⟩ := rat_append.mp hat'
  have hufl : (uf L 1 base).length = 3 := by simp [uf]
  rw [hufl] at hatr
  obtain ⟨f0, f1, f2, f3, f4, f5, f6, f7, _⟩ := hatr
  have hk : 1 ≤ s.dstack.length := by simp [hd]
  have hMlt : c.M < 2 ^ 32 := by have := hg.mb_lt; omega
  have hlt : a.toNat < c.M := by
    obtain ⟨hvv, _⟩ := Memory.read?_some hv
    have := hs.irvalid a
    rw [hvv] at this
    simpa using this.symm
  obtain ⟨x1, hs1, hr1, hpc1, hm1, _⟩ := uf_pass hg hs hL (by decide) (by decide) hk hpc hatuf
  obtain ⟨x2, hs2, hr2, hpc2, hv2, ho2, hm2⟩ := ld_step (code := code) hr1 (j := 0) (v := a)
    (by simp [hd]) (rd := r0) (by simp) (disp := 0) (by simp) (fetch_cast f0 (by omega))
  obtain ⟨x3, hs3, hr3, hpc3, hax3, ho3, hm3⟩ := addr_pass (code := code) hr2 (rt := r1) (by simp)
    (n := c.M) hMlt (t := base + ufSize 1 + 4) (by simp [ufSize]; omega) hv2 hlt (by
      rw [← hMs]
      refine ⟨fetch_cast f1 (by omega), fetch_cast f2 (by omega), fetch_cast f3 (by omega), trivial⟩)
  obtain ⟨x4, hs4, hr4, hpc4, hax4, _, _⟩ := idx_steps hr3 hax3
    ⟨fetch_cast f4 (by omega), fetch_cast f5 (by omega), trivial⟩
  have hst5 : step code x4 = .next (x4.mov r0 v) := by
    rw [rstep_of_fetch (fetch_cast f6 (by omega)), ld_mem hr4 hv hax4]
  have hr5 : Rel0 c p s (x4.mov r0 v) := mov_rel0 hr4 r0 (scratch_ne r0 (by simp)) v
  obtain ⟨x6, hs6, hr6, hpc6, _⟩ := st_step (code := code) hg hr5 (j := 0) (by simp [hd])
    (rs := r0) (disp := 0) (by simp) (fetch_cast f7 (by simp [M.mov, M.setReg, M.adv]; omega))
  have e : s.dstack.set 0 ((x4.mov r0 v).regs r0) = v :: d := by
    simp [hd, M.mov, M.setReg, M.adv]
  rw [e] at hr6
  exact ⟨x6, ((((hs1.trans hs2).trans hs3).trans hs4).trans (RSteps.single hst5)).trans hs6, hr6,
    by simp [M.mov, M.setReg, M.adv, isize, ufSize] at *; omega⟩

theorem sim_load_trap (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hMs : L.memSize = c.M)
    (hs : Rel0 c p s x) (hpc : x.pc = base) (hat : RAt code base (lowerInstr L base off .load))
    {a : W} {d : List W} (hd : s.dstack = a :: d) (hv : s.mem.read? a = none) :
    RExec code x (.trapped .badAddress) := by
  have hat' : RAt code base (uf L 1 base ++ [.load r0 Reg.r4 0, .movImm r1 (BitVec.ofNat 32 L.memSize),
      .bcc .ult r0 r1 (base + ufSize 1 + 4), .exitTrap .badAddress, .shlImm r0 2, .add r0 Reg.r6,
      .load r0 r0 0, .store Reg.r4 0 r0]) := hat
  obtain ⟨hatuf, hatr⟩ := rat_append.mp hat'
  have hufl : (uf L 1 base).length = 3 := by simp [uf]
  rw [hufl] at hatr
  obtain ⟨f0, f1, f2, f3, _⟩ := hatr
  have hk : 1 ≤ s.dstack.length := by simp [hd]
  have hMlt : c.M < 2 ^ 32 := by have := hg.mb_lt; omega
  have hge : ¬ a.toNat < c.M := by
    have hvv := (Memory.read?_none_iff s.mem a).mp hv
    have := hs.irvalid a
    rw [hvv] at this
    simpa using this
  obtain ⟨x1, hs1, hr1, hpc1, hm1, _⟩ := uf_pass hg hs hL (by decide) (by decide) hk hpc hatuf
  obtain ⟨x2, hs2, hr2, hpc2, hv2, ho2, hm2⟩ := ld_step (code := code) hr1 (j := 0) (v := a)
    (by simp [hd]) (rd := r0) (by simp) (disp := 0) (by simp) (fetch_cast f0 (by omega))
  exact RExec.of_steps (hs1.trans hs2) (addr_trap (code := code) hr2 (rt := r1) (by simp)
    (n := c.M) hMlt (t := base + ufSize 1 + 4) (by simp [ufSize]; omega) hv2 hge (by
      rw [← hMs]
      refine ⟨fetch_cast f1 (by omega), fetch_cast f2 (by omega), fetch_cast f3 (by omega), trivial⟩))

theorem sim_store_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hMs : L.memSize = c.M)
    (hs : Rel0 c p s x) (hpc : x.pc = base) (hat : RAt code base (lowerInstr L base off .store))
    {a v : W} {d : List W} (hd : s.dstack = a :: v :: d) {m : Memory 32}
    (hw : s.mem.write? a v = some m) :
    ∃ x', RSteps code x x' ∧ Rel0 c p { s with dstack := d, mem := m } x' ∧
      x'.pc = base + isize (.store : WordDialect.Instr 32) := by
  have hat' : RAt code base (uf L 2 base ++ [.load r0 Reg.r4 0, .load r1 Reg.r4 4,
      .movImm r2 (BitVec.ofNat 32 L.memSize), .bcc .ult r0 r2 (base + ufSize 2 + 5),
      .exitTrap .badAddress, .shlImm r0 2, .add r0 Reg.r6, .store r0 0 r1, .addImm Reg.r4 8]) := hat
  obtain ⟨hatuf, hatr⟩ := rat_append.mp hat'
  have hufl : (uf L 2 base).length = 3 := by simp [uf]
  rw [hufl] at hatr
  obtain ⟨f0, f1, f2, f3, f4, f5, f6, f7, f8, _⟩ := hatr
  have hk : 2 ≤ s.dstack.length := by simp [hd]
  have hMlt : c.M < 2 ^ 32 := by have := hg.mb_lt; omega
  have hv : s.mem.valid a = true := by
    by_cases hh : s.mem.valid a = true
    · exact hh
    · have := (Memory.write?_none_iff s.mem a v).mpr (by simpa using hh); rw [hw] at this; simp at this
  have hlt : a.toNat < c.M := by
    have := hs.irvalid a
    rw [hv] at this
    simpa using this.symm
  obtain ⟨x1, hs1, hr1, hpc1, hm1, _⟩ := uf_pass hg hs hL (by decide) (by decide) hk hpc hatuf
  obtain ⟨x2, hs2, hr2, hpc2, hv2, ho2, hm2⟩ := ld_step (code := code) hr1 (j := 0) (v := a)
    (by simp [hd]) (rd := r0) (by simp) (disp := 0) (by simp) (fetch_cast f0 (by omega))
  obtain ⟨x3, hs3, hr3, hpc3, hv3, ho3, hm3⟩ := ld_step (code := code) hr2 (j := 1) (v := v)
    (by simp [hd]) (rd := r1) (by simp) (disp := 4) (by simp) (fetch_cast f1 (by omega))
  have hax3 : x3.regs r0 = a := by rw [ho3 r0 (by decide), hv2]
  obtain ⟨x4, hs4, hr4, hpc4, hax4, ho4, hm4⟩ := addr_pass (code := code) hr3 (rt := r2) (by simp)
    (n := c.M) hMlt (t := base + ufSize 2 + 5) (by simp [ufSize]; omega) hax3 hlt (by
      rw [← hMs]
      refine ⟨fetch_cast f2 (by omega), fetch_cast f3 (by omega), fetch_cast f4 (by omega), trivial⟩)
  have hcx4 : x4.regs r1 = v := by rw [ho4 r1 (by decide), hv3]
  obtain ⟨x5, hs5, hr5, hpc5, hax5, ho5, _⟩ := idx_steps hr4 hax4
    ⟨fetch_cast f5 (by omega), fetch_cast f6 (by omega), trivial⟩
  have hcx5 : x5.regs r1 = v := by rw [ho5 r1 (by decide), hcx4]
  obtain ⟨mem', e6, hr6⟩ := st_mem hg hr5 hw hax5 hcx5
  have hst6 : step code x5 = .next { x5.adv with mem := mem' } := by
    rw [rstep_of_fetch (fetch_cast f7 (by omega)), e6]
  have hlen : 2 ≤ ({ s with mem := m } : State 32).dstack.length := by simp [hd]
  obtain ⟨x7, hs7, hr7, hpc7, _⟩ := adj_step (code := code) hg hr6 (n := 2) hlen (δ := 8) (by simp)
    (fetch_cast f8 (by simp [M.adv]; omega))
  have hr7' : Rel0 c p { s with dstack := d, mem := m } x7 := by
    have : ({ { s with mem := m } with dstack := ({ s with mem := m } : State 32).dstack.drop 2 } : State 32)
        = { s with dstack := d, mem := m } := by simp [hd]
    rw [← this]; exact hr7
  exact ⟨x7, (((((hs1.trans hs2).trans hs3).trans hs4).trans hs5).trans (RSteps.single hst6)).trans hs7,
    hr7', by simp [M.adv, isize, ufSize] at *; omega⟩

theorem sim_store_trap (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hMs : L.memSize = c.M)
    (hs : Rel0 c p s x) (hpc : x.pc = base) (hat : RAt code base (lowerInstr L base off .store))
    {a v : W} {d : List W} (hd : s.dstack = a :: v :: d) (hw : s.mem.write? a v = none) :
    RExec code x (.trapped .badAddress) := by
  have hat' : RAt code base (uf L 2 base ++ [.load r0 Reg.r4 0, .load r1 Reg.r4 4,
      .movImm r2 (BitVec.ofNat 32 L.memSize), .bcc .ult r0 r2 (base + ufSize 2 + 5),
      .exitTrap .badAddress, .shlImm r0 2, .add r0 Reg.r6, .store r0 0 r1, .addImm Reg.r4 8]) := hat
  obtain ⟨hatuf, hatr⟩ := rat_append.mp hat'
  have hufl : (uf L 2 base).length = 3 := by simp [uf]
  rw [hufl] at hatr
  obtain ⟨f0, f1, f2, f3, f4, _⟩ := hatr
  have hk : 2 ≤ s.dstack.length := by simp [hd]
  have hMlt : c.M < 2 ^ 32 := by have := hg.mb_lt; omega
  have hge : ¬ a.toNat < c.M := by
    have hvv := (Memory.write?_none_iff s.mem a v).mp hw
    have := hs.irvalid a
    rw [hvv] at this
    simpa using this
  obtain ⟨x1, hs1, hr1, hpc1, hm1, _⟩ := uf_pass hg hs hL (by decide) (by decide) hk hpc hatuf
  obtain ⟨x2, hs2, hr2, hpc2, hv2, ho2, hm2⟩ := ld_step (code := code) hr1 (j := 0) (v := a)
    (by simp [hd]) (rd := r0) (by simp) (disp := 0) (by simp) (fetch_cast f0 (by omega))
  obtain ⟨x3, hs3, hr3, hpc3, hv3, ho3, hm3⟩ := ld_step (code := code) hr2 (j := 1) (v := v)
    (by simp [hd]) (rd := r1) (by simp) (disp := 4) (by simp) (fetch_cast f1 (by omega))
  have hax3 : x3.regs r0 = a := by rw [ho3 r0 (by decide), hv2]
  exact RExec.of_steps ((hs1.trans hs2).trans hs3) (addr_trap (code := code) hr3 (rt := r2)
    (by simp) (n := c.M) hMlt (t := base + ufSize 2 + 5) (by simp [ufSize]; omega) hax3 hge (by
      rw [← hMs]
      refine ⟨fetch_cast f2 (by omega), fetch_cast f3 (by omega), fetch_cast f4 (by omega), trivial⟩))

end Ops

end CM
end WordDialect
