import X86.SimMem

/-!
# X86.SimMemOps

The address bounds guard `movImm rt, memSize; cmp rax, rt; jb ok; exitTrap badAddress`, and the
simulation theorems for `push`, `pop`, `load`, `store`.
-/

namespace WordDialect
namespace X86

open Reg

section Ops

variable {c : Cfg} {p : Prog 64} {s : State 64} {x : M} {code : List (Instr Nat)}
  {L : Layout} {base : Nat} {off : Nat → Nat}

theorem ult_memSize {a : W} {n : Nat} (hn : n < 2 ^ 64) :
    a.ult (BitVec.ofNat 64 n) = decide (a.toNat < n) := by
  simp [BitVec.ult_eq_decide, BitVec.toNat_ofNat, Nat.mod_eq_of_lt hn]

/-- The bounds guard, passing case. -/
theorem addr_pass (hs : Rel0 c p s x) {rt : Reg} (hrt : rt = rcx ∨ rt = rdx) {n : Nat}
    (hn : n < 2 ^ 64) {t : Nat} (ht : t = x.pc + 4) {a : W} (hrax : x.regs rax = a) (ha : a.toNat < n)
    (hat : XAt code x.pc [.movImm rt (BitVec.ofNat 64 n), .cmp rax rt, .jcc .b t,
      .exitTrap .badAddress]) :
    ∃ x', XSteps code x x' ∧ Rel0 c p s x' ∧ x'.pc = x.pc + 4 ∧ x'.regs rax = a ∧
      (∀ r, r ≠ rt → x'.regs r = x.regs r) ∧ x'.mem = x.mem := by
  subst ht
  obtain ⟨f0, f1, f2, f3, _⟩ := hat
  have hrt' : rt = rax ∨ rt = rcx ∨ rt = rdx ∨ rt = rbx := by rcases hrt with h | h <;> simp [h]
  have hne : rax ≠ rt := by rcases hrt with h | h <;> simp [h]
  obtain ⟨x1, hs1, hr1, hpc1, hv1, ho1, hm1⟩ := movimm_step (code := code) hs (rd := rt) hrt'
    (v := BitVec.ofNat 64 n) f0
  have hax1 : x1.regs rax = a := by rw [ho1 rax hne, hrax]
  let x2 : M := { x1.adv with flags := some (subFlags (x1.regs rax) (x1.regs rt)) }
  have hst2 : step code x1 = .next x2 := by
    rw [xstep_of_fetch (m := x1) (fetch_cast f1 (by omega))]; rfl
  have hpc2 : x2.pc = x.pc + 2 := by simp [x2, M.adv, hpc1]
  have hr2 : Rel0 c p s x2 := hr1.congr (by simp [x2, M.adv]) (by simp [x2, M.adv]) (by simp [x2, M.adv])
    (by simp [x2, M.adv]) (by simp [x2, M.adv]) (by simp [x2, M.adv]) (by simp [x2, M.adv])
  have hfl : x2.flags = some (subFlags a (BitVec.ofNat 64 n)) := by simp [x2, hax1, hv1]
  have hhold : Cc.b.holds (subFlags a (BitVec.ofNat 64 n)) = true := by
    rw [holds_b, ult_memSize hn]; simpa using ha
  have hg := guard_pass (code := code) (pc := x.pc + 2) (m := x2) (c := .b) (t := .badAddress)
    (f := subFlags a (BitVec.ofNat 64 n))
    ⟨fetch_cast f2 (by omega), fetch_cast f3 (by omega), trivial⟩ hpc2 hfl hhold
  refine ⟨{ x2 with pc := x.pc + 2 + 2 }, (hs1.trans (XSteps.single hst2)).trans hg, ?_, by simp,
    by simp [x2, M.adv, hax1], ?_, by simp [x2, M.adv, hm1]⟩
  · exact hr2.congr rfl rfl rfl rfl rfl rfl rfl
  · intro r hr; simp [x2, M.adv, ho1 r hr]

/-- The bounds guard, failing case. -/
theorem addr_trap (hs : Rel0 c p s x) {rt : Reg} (hrt : rt = rcx ∨ rt = rdx) {n : Nat}
    (hn : n < 2 ^ 64) {t : Nat} (ht : t = x.pc + 4) {a : W} (hrax : x.regs rax = a) (ha : ¬ a.toNat < n)
    (hat : XAt code x.pc [.movImm rt (BitVec.ofNat 64 n), .cmp rax rt, .jcc .b t,
      .exitTrap .badAddress]) :
    XExec code x (.trapped .badAddress) := by
  subst ht
  obtain ⟨f0, f1, f2, f3, _⟩ := hat
  have hrt' : rt = rax ∨ rt = rcx ∨ rt = rdx ∨ rt = rbx := by rcases hrt with h | h <;> simp [h]
  have hne : rax ≠ rt := by rcases hrt with h | h <;> simp [h]
  obtain ⟨x1, hs1, hr1, hpc1, hv1, ho1, hm1⟩ := movimm_step (code := code) hs (rd := rt) hrt'
    (v := BitVec.ofNat 64 n) f0
  have hax1 : x1.regs rax = a := by rw [ho1 rax hne, hrax]
  let x2 : M := { x1.adv with flags := some (subFlags (x1.regs rax) (x1.regs rt)) }
  have hst2 : step code x1 = .next x2 := by
    rw [xstep_of_fetch (m := x1) (fetch_cast f1 (by omega))]; rfl
  have hpc2 : x2.pc = x.pc + 2 := by simp [x2, M.adv, hpc1]
  have hfl : x2.flags = some (subFlags a (BitVec.ofNat 64 n)) := by simp [x2, hax1, hv1]
  have hhold : Cc.b.holds (subFlags a (BitVec.ofNat 64 n)) = false := by
    rw [holds_b, ult_memSize hn]; simpa using ha
  exact XExec.of_steps (hs1.trans (XSteps.single hst2))
    (guard_trap (code := code) (pc := x.pc + 2) (m := x2) (c := .b) (t := .badAddress)
      (f := subFlags a (BitVec.ofNat 64 n))
      ⟨fetch_cast f2 (by omega), fetch_cast f3 (by omega), trivial⟩ hpc2 hfl hhold)

theorem sim_push_ok (hg : Geom c) (hs : Rel0 c p s x) (hpc : x.pc = base) {r : Nat}
    (hr : r < c.nregs) (hLd : L.dLim = ofN (c.dBase + 8))
    (hat : XAt code base (lowerInstr L base off (.push r)))
    (hfit : c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd) :
    ∃ x', XSteps code x x' ∧ Rel0 c p { s with dstack := s.regs r :: s.dstack } x' ∧
      x'.pc = base + isize (.push r : WordDialect.Instr 64) := by
  obtain ⟨hato, f0, f1, f2⟩ := xat_ovf3 (L := L) (by exact hat)
  obtain ⟨x0, hs0, hr0, hpc0, _, _⟩ := ovfD_pass hg hs hLd hfit hpc hato
  have hst : step code x0 = .next (x0.mov rax (s.regs r)) := by
    rw [xstep_of_fetch (by rw [hpc0]; exact f0), ld_reg hr0 hr rax rfl]
  have hr1 : Rel0 c p s (x0.mov rax (s.regs r)) := mov_rel0 hr0 rax (scratch_ne rax (by simp)) _
  have hpc1 : (x0.mov rax (s.regs r)).pc = base + 4 + 1 := by simp [M.mov, M.setReg, M.adv, hpc0]
  obtain ⟨x2, hs2, hr2, hpc2, _⟩ := push_pair hg hr1 rax (by decide) hfit
    ⟨fetch_cast f1 (by omega), fetch_cast f2 (by omega), trivial⟩
  have hv : (x0.mov rax (s.regs r)).regs rax = s.regs r := by simp [M.mov, M.setReg, M.adv]
  rw [hv] at hr2
  exact ⟨x2, (hs0.trans (XSteps.single hst)).trans hs2, hr2, by simp [isize]; omega⟩

theorem sim_push_ovf (hg : Geom c) (hs : Rel0 c p s x) (hpc : x.pc = base) {r : Nat}
    (hLd : L.dLim = ofN (c.dBase + 8)) (hat : XAt code base (lowerInstr L base off (.push r)))
    (h : ¬ c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd) : XExec code x .overflow := by
  obtain ⟨hato, _⟩ := xat_ovf3 (L := L) (by exact hat)
  exact ovfD_trap hg hs hLd h hpc hato

theorem sim_pop_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    {r : Nat} (hr : r < c.nregs) (hat : XAt code base (lowerInstr L base off (.pop r)))
    {a : W} {d : List W} (hd : s.dstack = a :: d) :
    ∃ x', XSteps code x x' ∧
      Rel0 c p { s with dstack := d, regs := State.setReg s.regs r a } x' ∧
      x'.pc = base + isize (.pop r : WordDialect.Instr 64) := by
  have hat' : XAt code base (uf L 1 base ++ [.load rax Reg.r15 0, .addImm Reg.r15 8,
      .store Reg.r14 (8 * (r : Int)) rax]) := hat
  obtain ⟨hatuf, hatr⟩ := xat_append.mp hat'
  have hufl : (uf L 1 base).length = 4 := by simp [uf]
  rw [hufl] at hatr
  obtain ⟨f0, f1, f2, _⟩ := hatr
  have hk : 1 ≤ s.dstack.length := by simp [hd]
  obtain ⟨x1, hs1, hr1, hpc1, hm1, _⟩ := uf_pass hg hs hL (by decide) (by decide) hk hpc hatuf
  obtain ⟨x2, hs2, hr2, hpc2, hv2, _, _⟩ := ld_step (code := code) hr1 (j := 0) (v := a)
    (by simp [hd]) (rd := rax) (by simp) (disp := 0) (by simp) (fetch_cast f0 (by omega))
  obtain ⟨x3, hs3, hr3, hpc3, ho3⟩ := adj_step (code := code) hg hr2 (n := 1) (by simp [hd])
    (δ := 8) (by simp) (fetch_cast f1 (by omega))
  have hax3 : x3.regs rax = a := by rw [ho3 rax (by decide), hv2]
  obtain ⟨mem', e4, hr4⟩ := st_reg hg hr3 hr rax (disp := 8 * (r : Int)) rfl
  have hst4 : step code x3 = .next { x3.adv with mem := mem' } := by
    rw [xstep_of_fetch (fetch_cast f2 (by omega)), e4]
  have hr4' : Rel0 c p { s with dstack := s.dstack.drop 1, regs := State.setReg s.regs r (x3.regs rax) }
      { x3.adv with mem := mem' } := hr4
  have e : s.dstack.drop 1 = d := by simp [hd]
  rw [e, hax3] at hr4'
  exact ⟨_, ((hs1.trans hs2).trans hs3).trans (XSteps.single hst4), hr4',
    by simp [M.adv, isize, ufSize]; omega⟩

theorem sim_load_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hMs : L.memSize = c.M)
    (hs : Rel0 c p s x) (hpc : x.pc = base) (hat : XAt code base (lowerInstr L base off .load))
    {a v : W} {d : List W} (hd : s.dstack = a :: d) (hv : s.mem.read? a = some v) :
    ∃ x', XSteps code x x' ∧ Rel0 c p { s with dstack := v :: d } x' ∧
      x'.pc = base + isize (.load : WordDialect.Instr 64) := by
  have hat' : XAt code base (uf L 1 base ++ [.load rax Reg.r15 0, .movImm rcx (BitVec.ofNat 64 L.memSize),
      .cmp rax rcx, .jcc .b (base + ufSize 1 + 5), .exitTrap .badAddress, .loadIdx rax Reg.r13 rax,
      .store Reg.r15 0 rax]) := hat
  obtain ⟨hatuf, hatr⟩ := xat_append.mp hat'
  have hufl : (uf L 1 base).length = 4 := by simp [uf]
  rw [hufl] at hatr
  obtain ⟨f0, f1, f2, f3, f4, f5, f6, _⟩ := hatr
  have hk : 1 ≤ s.dstack.length := by simp [hd]
  have hMlt : c.M < 2 ^ 64 := by have := hg.mb_lt; omega
  have hlt : a.toNat < c.M := by
    obtain ⟨hvv, _⟩ := Memory.read?_some hv
    have := hs.irvalid a
    rw [hvv] at this
    simpa using this.symm
  obtain ⟨x1, hs1, hr1, hpc1, hm1, _⟩ := uf_pass hg hs hL (by decide) (by decide) hk hpc hatuf
  obtain ⟨x2, hs2, hr2, hpc2, hv2, ho2, hm2⟩ := ld_step (code := code) hr1 (j := 0) (v := a)
    (by simp [hd]) (rd := rax) (by simp) (disp := 0) (by simp) (fetch_cast f0 (by omega))
  obtain ⟨x3, hs3, hr3, hpc3, hax3, ho3, hm3⟩ := addr_pass (code := code) hr2 (rt := rcx) (by simp)
    (n := c.M) hMlt (t := base + ufSize 1 + 5) (by simp [ufSize]; omega) hv2 hlt (by
      rw [← hMs]
      refine ⟨fetch_cast f1 (by omega), fetch_cast f2 (by omega), fetch_cast f3 (by omega),
        fetch_cast f4 (by omega), trivial⟩)
  have hst4 : step code x3 = .next (x3.mov rax v) := by
    rw [xstep_of_fetch (fetch_cast f5 (by omega)), ld_mem hr3 hv hax3]
  have hr4 : Rel0 c p s (x3.mov rax v) := mov_rel0 hr3 rax (scratch_ne rax (by simp)) v
  have hpc4 : (x3.mov rax v).pc = base + 4 + 1 + 4 + 1 := by simp [M.mov, M.setReg, M.adv]; omega
  obtain ⟨x5, hs5, hr5, hpc5, _⟩ := st_step (code := code) hg hr4 (j := 0) (by simp [hd])
    (rs := rax) (disp := 0) (by simp) (fetch_cast f6 (by omega))
  have e : s.dstack.set 0 ((x3.mov rax v).regs rax) = v :: d := by
    simp [hd, M.mov, M.setReg, M.adv]
  rw [e] at hr5
  exact ⟨x5, (((hs1.trans hs2).trans hs3).trans (XSteps.single hst4)).trans hs5, hr5,
    by simp [isize, ufSize]; omega⟩

theorem sim_load_trap (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hMs : L.memSize = c.M)
    (hs : Rel0 c p s x) (hpc : x.pc = base) (hat : XAt code base (lowerInstr L base off .load))
    {a : W} {d : List W} (hd : s.dstack = a :: d) (hv : s.mem.read? a = none) :
    XExec code x (.trapped .badAddress) := by
  have hat' : XAt code base (uf L 1 base ++ [.load rax Reg.r15 0, .movImm rcx (BitVec.ofNat 64 L.memSize),
      .cmp rax rcx, .jcc .b (base + ufSize 1 + 5), .exitTrap .badAddress, .loadIdx rax Reg.r13 rax,
      .store Reg.r15 0 rax]) := hat
  obtain ⟨hatuf, hatr⟩ := xat_append.mp hat'
  have hufl : (uf L 1 base).length = 4 := by simp [uf]
  rw [hufl] at hatr
  obtain ⟨f0, f1, f2, f3, f4, _⟩ := hatr
  have hk : 1 ≤ s.dstack.length := by simp [hd]
  have hMlt : c.M < 2 ^ 64 := by have := hg.mb_lt; omega
  have hge : ¬ a.toNat < c.M := by
    have hvv := (Memory.read?_none_iff s.mem a).mp hv
    have := hs.irvalid a
    rw [hvv] at this
    simpa using this
  obtain ⟨x1, hs1, hr1, hpc1, hm1, _⟩ := uf_pass hg hs hL (by decide) (by decide) hk hpc hatuf
  obtain ⟨x2, hs2, hr2, hpc2, hv2, ho2, hm2⟩ := ld_step (code := code) hr1 (j := 0) (v := a)
    (by simp [hd]) (rd := rax) (by simp) (disp := 0) (by simp) (fetch_cast f0 (by omega))
  exact XExec.of_steps (hs1.trans hs2) (addr_trap (code := code) hr2 (rt := rcx) (by simp)
    (n := c.M) hMlt (t := base + ufSize 1 + 5) (by simp [ufSize]; omega) hv2 hge (by
      rw [← hMs]
      refine ⟨fetch_cast f1 (by omega), fetch_cast f2 (by omega), fetch_cast f3 (by omega),
        fetch_cast f4 (by omega), trivial⟩))

theorem sim_store_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hMs : L.memSize = c.M)
    (hs : Rel0 c p s x) (hpc : x.pc = base) (hat : XAt code base (lowerInstr L base off .store))
    {a v : W} {d : List W} (hd : s.dstack = a :: v :: d) {m : Memory 64}
    (hw : s.mem.write? a v = some m) :
    ∃ x', XSteps code x x' ∧ Rel0 c p { s with dstack := d, mem := m } x' ∧
      x'.pc = base + isize (.store : WordDialect.Instr 64) := by
  have hat' : XAt code base (uf L 2 base ++ [.load rax Reg.r15 0, .load rcx Reg.r15 8,
      .movImm rdx (BitVec.ofNat 64 L.memSize), .cmp rax rdx, .jcc .b (base + ufSize 2 + 6),
      .exitTrap .badAddress, .storeIdx Reg.r13 rax rcx, .addImm Reg.r15 16]) := hat
  obtain ⟨hatuf, hatr⟩ := xat_append.mp hat'
  have hufl : (uf L 2 base).length = 4 := by simp [uf]
  rw [hufl] at hatr
  obtain ⟨f0, f1, f2, f3, f4, f5, f6, f7, _⟩ := hatr
  have hk : 2 ≤ s.dstack.length := by simp [hd]
  have hMlt : c.M < 2 ^ 64 := by have := hg.mb_lt; omega
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
    (by simp [hd]) (rd := rax) (by simp) (disp := 0) (by simp) (fetch_cast f0 (by omega))
  obtain ⟨x3, hs3, hr3, hpc3, hv3, ho3, hm3⟩ := ld_step (code := code) hr2 (j := 1) (v := v)
    (by simp [hd]) (rd := rcx) (by simp) (disp := 8) (by simp) (fetch_cast f1 (by omega))
  have hax3 : x3.regs rax = a := by rw [ho3 rax (by decide), hv2]
  obtain ⟨x4, hs4, hr4, hpc4, hax4, ho4, hm4⟩ := addr_pass (code := code) hr3 (rt := rdx) (by simp)
    (n := c.M) hMlt (t := base + ufSize 2 + 6) (by simp [ufSize]; omega) hax3 hlt (by
      rw [← hMs]
      refine ⟨fetch_cast f2 (by omega), fetch_cast f3 (by omega), fetch_cast f4 (by omega),
        fetch_cast f5 (by omega), trivial⟩)
  have hcx4 : x4.regs rcx = v := by rw [ho4 rcx (by decide), hv3]
  obtain ⟨mem', e5, hr5⟩ := st_mem hg hr4 hw hax4 hcx4
  have hst5 : step code x4 = .next { x4.adv with mem := mem' } := by
    rw [xstep_of_fetch (fetch_cast f6 (by omega)), e5]
  have hlen : 2 ≤ ({ s with mem := m } : State 64).dstack.length := by simp [hd]
  obtain ⟨x6, hs6, hr6, hpc6, _⟩ := adj_step (code := code) hg hr5 (n := 2) hlen (δ := 16) (by simp)
    (fetch_cast f7 (by simp [M.adv]; omega))
  have e : ({ s with mem := m } : State 64).dstack.drop 2 = d := by simp [hd]
  have hr6' : Rel0 c p { s with dstack := d, mem := m } x6 := by
    have : ({ { s with mem := m } with dstack := ({ s with mem := m } : State 64).dstack.drop 2 } : State 64)
        = { s with dstack := d, mem := m } := by simp [hd]
    rw [← this]; exact hr6
  exact ⟨x6, (((((hs1.trans hs2).trans hs3).trans hs4).trans (XSteps.single hst5))).trans hs6, hr6',
    by simp [M.adv, isize, ufSize] at *; omega⟩

theorem sim_store_trap (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hMs : L.memSize = c.M)
    (hs : Rel0 c p s x) (hpc : x.pc = base) (hat : XAt code base (lowerInstr L base off .store))
    {a v : W} {d : List W} (hd : s.dstack = a :: v :: d) (hw : s.mem.write? a v = none) :
    XExec code x (.trapped .badAddress) := by
  have hat' : XAt code base (uf L 2 base ++ [.load rax Reg.r15 0, .load rcx Reg.r15 8,
      .movImm rdx (BitVec.ofNat 64 L.memSize), .cmp rax rdx, .jcc .b (base + ufSize 2 + 6),
      .exitTrap .badAddress, .storeIdx Reg.r13 rax rcx, .addImm Reg.r15 16]) := hat
  obtain ⟨hatuf, hatr⟩ := xat_append.mp hat'
  have hufl : (uf L 2 base).length = 4 := by simp [uf]
  rw [hufl] at hatr
  obtain ⟨f0, f1, f2, f3, f4, f5, _⟩ := hatr
  have hk : 2 ≤ s.dstack.length := by simp [hd]
  have hMlt : c.M < 2 ^ 64 := by have := hg.mb_lt; omega
  have hge : ¬ a.toNat < c.M := by
    have hvv := (Memory.write?_none_iff s.mem a v).mp hw
    have := hs.irvalid a
    rw [hvv] at this
    simpa using this
  obtain ⟨x1, hs1, hr1, hpc1, hm1, _⟩ := uf_pass hg hs hL (by decide) (by decide) hk hpc hatuf
  obtain ⟨x2, hs2, hr2, hpc2, hv2, ho2, hm2⟩ := ld_step (code := code) hr1 (j := 0) (v := a)
    (by simp [hd]) (rd := rax) (by simp) (disp := 0) (by simp) (fetch_cast f0 (by omega))
  obtain ⟨x3, hs3, hr3, hpc3, hv3, ho3, hm3⟩ := ld_step (code := code) hr2 (j := 1) (v := v)
    (by simp [hd]) (rd := rcx) (by simp) (disp := 8) (by simp) (fetch_cast f1 (by omega))
  have hax3 : x3.regs rax = a := by rw [ho3 rax (by decide), hv2]
  exact XExec.of_steps ((hs1.trans hs2).trans hs3) (addr_trap (code := code) hr3 (rt := rdx)
    (by simp) (n := c.M) hMlt (t := base + ufSize 2 + 6) (by simp [ufSize]; omega) hax3 hge (by
      rw [← hMs]
      refine ⟨fetch_cast f2 (by omega), fetch_cast f3 (by omega), fetch_cast f4 (by omega),
        fetch_cast f5 (by omega), trivial⟩))

end Ops

end X86
end WordDialect
