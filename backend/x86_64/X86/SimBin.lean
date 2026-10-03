import X86.Guard

/-!
# X86.SimBin

Generic simulation of the binary-operation lowering shape

    uf 2 ; load rcx,[r15] ; load rax,[r15+8] ; <mid> ; store [r15+8],rr ; add r15,8

`mid` only has to compute `f a b` into `rr` from `rax = a`, `rcx = b`, touching nothing but
scratch state. Instantiated below for add/sub/mul/and/or/xor, shifts, rotates and compares.
-/

namespace WordDialect
namespace X86

open Reg

def MidSpec (mid : List (Instr Nat)) (rr : Reg) (f : W → W → W) : Prop :=
  ∀ (m : M) (a b : W), m.regs rax = a → m.regs rcx = b →
    ∃ m', xseq mid m = .next m' ∧ m'.regs rr = f a b ∧ m'.mem = m.mem ∧
      m'.regs r15 = m.regs r15 ∧ m'.regs r14 = m.regs r14 ∧ m'.regs r13 = m.regs r13 ∧
      m'.regs r12 = m.regs r12 ∧ m'.regs rsp = m.regs rsp ∧ m'.pc = m.pc + mid.length

theorem scratch_ne (r : Reg) (h : r = rax ∨ r = rcx ∨ r = rdx ∨ r = rbx) :
    r ≠ r15 ∧ r ≠ r14 ∧ r ≠ r13 ∧ r ≠ r12 ∧ r ≠ rsp := by
  rcases h with rfl | rfl | rfl | rfl <;> decide

theorem sim_bin_ok {c : Cfg} {p : Prog 64} {s : State 64} {x : M} {code : List (Instr Nat)}
    {L : Layout} {base : Nat} (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x)
    (hpc : x.pc = base) (mid : List (Instr Nat)) (rr : Reg)
    (hrr : rr = rax ∨ rr = rcx ∨ rr = rdx ∨ rr = rbx) (f : W → W → W)
    (hmid : MidSpec mid rr f) (hstr : ∀ i ∈ mid, i.straightX = true)
    (hat : XAt code base (uf L 2 base ++
      ([.load rcx r15 0, .load rax r15 8] ++ mid ++ [.store r15 8 rr, .addImm r15 8])))
    {b a : W} {d : List W} (hd : s.dstack = b :: a :: d) :
    ∃ x', XSteps code x x' ∧ Rel0 c p { s with dstack := f a b :: d } x' ∧
      x'.pc = base + 4 + (4 + mid.length) := by
  have hk : 2 ≤ s.dstack.length := by simp [hd]
  obtain ⟨hatuf, hatrest⟩ := xat_append.mp hat
  have hufl : (uf L 2 base).length = 4 := by simp [uf]
  rw [hufl] at hatrest
  obtain ⟨hatA, hatB⟩ := xat_append.mp hatrest
  obtain ⟨hatLd, hatMid⟩ := xat_append.mp hatA
  obtain ⟨f0, f1, _⟩ := hatLd
  obtain ⟨x1, hs1, hr1, hpc1, hm1, _⟩ := uf_pass hg hs hL (by decide) (by decide) hk hpc hatuf
  have hrcx := scratch_ne rcx (by simp)
  have hrax := scratch_ne rax (by simp)
  -- load rcx, [r15 + 0]
  have e0 := ld_stack hr1 (j := 0) (v := b) (by simp [hd]) rcx (disp := 0) (by simp)
  obtain ⟨x2, hx2⟩ : ∃ x2, x2 = x1.mov rcx b := ⟨_, rfl⟩
  have hst0 : XSteps code x1 x2 := XSteps.single (by
    rw [xstep_of_fetch (m := x1) (by rw [hpc1]; exact f0), e0, hx2])
  have hr2 : Rel0 c p s x2 := by rw [hx2]; exact mov_rel0 hr1 rcx hrcx b
  have hpc2 : x2.pc = base + 4 + 1 := by simp [hx2, M.mov, M.setReg, M.adv, hpc1]
  -- load rax, [r15 + 8]
  have e1 := ld_stack hr2 (j := 1) (v := a) (by simp [hd]) rax (disp := 8) (by simp)
  obtain ⟨x3, hx3⟩ : ∃ x3, x3 = x2.mov rax a := ⟨_, rfl⟩
  have hst1 : XSteps code x2 x3 := XSteps.single (by
    rw [xstep_of_fetch (m := x2) (by rw [hpc2]; exact f1), e1, hx3])
  have hr3 : Rel0 c p s x3 := by rw [hx3]; exact mov_rel0 hr2 rax hrax a
  have hpc3 : x3.pc = base + 4 + 2 := by simp [hx3, M.mov, M.setReg, M.adv, hpc2]
  have hax : x3.regs rax = a := by simp [hx3, M.mov, M.setReg, M.adv]
  have hcx : x3.regs rcx = b := by simp [hx3, hx2, M.mov, M.setReg, M.adv]
  -- mid
  obtain ⟨x4, hx4, hrr4, hm4, h15, h14, h13, h12, hsp, hpc4⟩ := hmid x3 a b hax hcx
  obtain ⟨hstM, _⟩ := xseq_steps hstr (by rw [hpc3]; exact hatMid) hx4
  have hr4 : Rel0 c p s x4 := hr3.congr hm4 h15 h14 h13 h12 hsp
  -- store [r15 + 8], rr
  have hlen : 1 < s.dstack.length := by simp [hd]
  obtain ⟨mem', e2, hr5⟩ := st_stack hg hr4 (j := 1) hlen rr (disp := 8) (by simp)
  obtain ⟨st, adj, _⟩ := hatB
  have hpc4' : x4.pc = base + 4 + (2 + mid.length) := by rw [hpc4, hpc3]; omega
  obtain ⟨x5, hx5⟩ : ∃ x5, x5 = ({ x4.adv with mem := mem' } : M) := ⟨_, rfl⟩
  have hst2 : XSteps code x4 x5 := XSteps.single (by
    rw [xstep_of_fetch (m := x4) (fetch_cast st (by rw [hpc4']; simp; omega)), e2, hx5])
  rw [← hx5] at hr5
  have hpc5 : x5.pc = base + 4 + (2 + mid.length + 1) := by
    simp [hx5, M.adv]; omega
  -- adjust r15
  have hlen5 : 1 ≤ ({ s with dstack := s.dstack.set 1 (x4.regs rr) } : State 64).dstack.length := by
    simp [hd]
  obtain ⟨e3, hr6⟩ := adj_drop hg hr5 (n := 1) hlen5 (δ := 8) (by simp)
  obtain ⟨x6, hx6⟩ : ∃ x6, x6 = x5.arith Reg.r15
      (ofN (c.dEnd - 8 * (({ s with dstack := s.dstack.set 1 (x4.regs rr) } : State 64).dstack.length - 1))) :=
    ⟨_, rfl⟩
  rw [← hx6] at e3 hr6
  have hst3 : XSteps code x5 x6 := XSteps.single (by
    rw [xstep_of_fetch (m := x5) (fetch_cast adj (by rw [hpc5]; simp; omega)), e3])
  have hrrv : x4.regs rr = f a b := hrr4
  refine ⟨x6, ((((hst0 |> fun h => (hs1.trans h)).trans hst1).trans hstM).trans hst2).trans hst3, ?_, ?_⟩
  · have e : (({ s with dstack := s.dstack.set 1 (x4.regs rr) } : State 64).dstack).drop 1 = f a b :: d := by
      simp [hd, hrrv]
    simpa [e] using hr6
  · simp [hx6, M.arith, hpc5]
    omega

end X86
end WordDialect
