import RV.Guard

/-!
# RV.SimBin

Generic simulation of the binary-operation lowering shape

    uf 2 ; load t1,[s1] ; load t0,[s1+8] ; <mid> ; store [s1+8],rr ; add s1,8

`mid` only has to compute `f a b` into `rr` from `t0 = a`, `t1 = b`, touching nothing but
scratch state. Instantiated below for add/sub/mul/and/or/xor, shifts, rotates and compares.
-/

namespace WordDialect
namespace RV

open Reg

def MidSpec (mid : List (Instr Nat)) (rr : Reg) (f : W → W → W) : Prop :=
  ∀ (m : M) (a b : W), m.regs t0 = a → m.regs t1 = b →
    ∃ m', rseq mid m = .next m' ∧ m'.regs rr = f a b ∧ m'.mem = m.mem ∧
      m'.regs s1 = m.regs s1 ∧ m'.regs s2 = m.regs s2 ∧ m'.regs s3 = m.regs s3 ∧
      m'.regs s4 = m.regs s4 ∧ m'.regs s5 = m.regs s5 ∧ m'.regs s6 = m.regs s6 ∧
      m'.pc = m.pc + mid.length

theorem scratch_ne (r : Reg) (h : r = t0 ∨ r = t1 ∨ r = t2 ∨ r = t3) :
    r ≠ s1 ∧ r ≠ s2 ∧ r ≠ s3 ∧ r ≠ s4 ∧ r ≠ s5 ∧ r ≠ s6 := by
  rcases h with rfl | rfl | rfl | rfl <;> decide

theorem sim_bin_ok {c : Cfg} {p : Prog 64} {s : State 64} {x : M} {code : List (Instr Nat)}
    {L : Layout} {base : Nat} (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x)
    (hpc : x.pc = base) (mid : List (Instr Nat)) (rr : Reg)
    (hrr : rr = t0 ∨ rr = t1 ∨ rr = t2 ∨ rr = t3) (f : W → W → W)
    (hmid : MidSpec mid rr f) (hstr : ∀ i ∈ mid, i.straightR = true)
    (hat : RAt code base (uf L 2 base ++
      ([.load t1 s1 0, .load t0 s1 8] ++ mid ++ [.store s1 8 rr, .addImm s1 8])))
    {b a : W} {d : List W} (hd : s.dstack = b :: a :: d) :
    ∃ x', RSteps code x x' ∧ Rel0 c p { s with dstack := f a b :: d } x' ∧
      x'.pc = base + 3 + (4 + mid.length) := by
  have hk : 2 ≤ s.dstack.length := by simp [hd]
  obtain ⟨hatuf, hatrest⟩ := rat_append.mp hat
  have hufl : (uf L 2 base).length = 3 := by simp [uf]
  rw [hufl] at hatrest
  obtain ⟨hatA, hatB⟩ := rat_append.mp hatrest
  obtain ⟨hatLd, hatMid⟩ := rat_append.mp hatA
  obtain ⟨f0, f1, _⟩ := hatLd
  obtain ⟨x1, hs1, hr1, hpc1, hm1, _⟩ := uf_pass hg hs hL (by decide) (by decide) hk hpc hatuf
  have hrcx := scratch_ne t1 (by simp)
  have hrax := scratch_ne t0 (by simp)
  -- load t1, [s1 + 0]
  have e0 := ld_stack hr1 (j := 0) (v := b) (by simp [hd]) t1 (disp := 0) (by simp)
  obtain ⟨x2, hx2⟩ : ∃ x2, x2 = x1.mov t1 b := ⟨_, rfl⟩
  have hst0 : RSteps code x1 x2 := RSteps.single (by
    rw [rstep_of_fetch (m := x1) (by rw [hpc1]; exact f0), e0, hx2])
  have hr2 : Rel0 c p s x2 := by rw [hx2]; exact mov_rel0 hr1 t1 hrcx b
  have hpc2 : x2.pc = base + 3 + 1 := by simp [hx2, M.mov, M.setReg, M.adv, hpc1]
  -- load t0, [s1 + 8]
  have e1 := ld_stack hr2 (j := 1) (v := a) (by simp [hd]) t0 (disp := 8) (by simp)
  obtain ⟨x3, hx3⟩ : ∃ x3, x3 = x2.mov t0 a := ⟨_, rfl⟩
  have hst1 : RSteps code x2 x3 := RSteps.single (by
    rw [rstep_of_fetch (m := x2) (by rw [hpc2]; exact f1), e1, hx3])
  have hr3 : Rel0 c p s x3 := by rw [hx3]; exact mov_rel0 hr2 t0 hrax a
  have hpc3 : x3.pc = base + 3 + 2 := by simp [hx3, M.mov, M.setReg, M.adv, hpc2]
  have hax : x3.regs t0 = a := by simp [hx3, M.mov, M.setReg, M.adv]
  have hcx : x3.regs t1 = b := by simp [hx3, hx2, M.mov, M.setReg, M.adv]
  -- mid
  obtain ⟨x4, hx4, hrr4, hm4, h15, h14, h13, h12, hsp, hbp, hpc4⟩ := hmid x3 a b hax hcx
  obtain ⟨hstM, _⟩ := rseq_steps hstr (by rw [hpc3]; exact hatMid) hx4
  have hr4 : Rel0 c p s x4 := hr3.congr hm4 h15 h14 h13 h12 hsp hbp
  -- store [s1 + 8], rr
  have hlen : 1 < s.dstack.length := by simp [hd]
  obtain ⟨mem', e2, hr5⟩ := st_stack hg hr4 (j := 1) hlen rr (disp := 8) (by simp)
  obtain ⟨st, adj, _⟩ := hatB
  have hpc4' : x4.pc = base + 3 + (2 + mid.length) := by rw [hpc4, hpc3]; omega
  obtain ⟨x5, hx5⟩ : ∃ x5, x5 = ({ x4.adv with mem := mem' } : M) := ⟨_, rfl⟩
  have hst2 : RSteps code x4 x5 := RSteps.single (by
    rw [rstep_of_fetch (m := x4) (fetch_cast st (by rw [hpc4']; simp; omega)), e2, hx5])
  rw [← hx5] at hr5
  have hpc5 : x5.pc = base + 3 + (2 + mid.length + 1) := by
    simp [hx5, M.adv]; omega
  -- adjust s1
  have hlen5 : 1 ≤ ({ s with dstack := s.dstack.set 1 (x4.regs rr) } : State 64).dstack.length := by
    simp [hd]
  obtain ⟨e3, hr6⟩ := adj_drop hg hr5 (n := 1) hlen5 (δ := 8) (by simp)
  obtain ⟨x6, hx6⟩ : ∃ x6, x6 = x5.arith Reg.s1
      (ofN (c.dEnd - 8 * (({ s with dstack := s.dstack.set 1 (x4.regs rr) } : State 64).dstack.length - 1))) :=
    ⟨_, rfl⟩
  rw [← hx6] at e3 hr6
  have hst3 : RSteps code x5 x6 := RSteps.single (by
    rw [rstep_of_fetch (m := x5) (fetch_cast adj (by rw [hpc5]; simp; omega)), e3])
  have hrrv : x4.regs rr = f a b := hrr4
  refine ⟨x6, ((((hst0 |> fun h => (hs1.trans h)).trans hst1).trans hstM).trans hst2).trans hst3, ?_, ?_⟩
  · have e : (({ s with dstack := s.dstack.set 1 (x4.regs rr) } : State 64).dstack).drop 1 = f a b :: d := by
      simp [hd, hrrv]
    simpa [e] using hr6
  · simp [hx6, M.arith, hpc5]
    omega

end RV
end WordDialect
