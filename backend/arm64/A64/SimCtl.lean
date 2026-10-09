import A64.SimDiv

/-!
# A64.SimCtl

Control flow: `jmp branch call ret halt`. IR `call` and `ret` are the model's `call` and `ret`
(fixed sequences on `x23`, see `A64.Isa`), so the IR return stack is the return stack
(`.rstack`) below `sp0`, related by `RsRel` (cells hold the AArch64 code index of the return
instruction).
-/

namespace WordDialect
namespace A64

open Reg

theorem offs_succ {p : Prog 64} {k : Nat} {i : WordDialect.Instr 64} (h : p[k]? = some i) :
    offs p (k + 1) = offs p k + isize i := by
  have hk : k < p.length := (List.getElem?_eq_some_iff.mp h).1
  have hi : p[k] = i := (List.getElem?_eq_some_iff.mp h).2
  simp [offs, List.take_succ, h, List.sum_append]

section Ctl

variable {c : Cfg} {p : Prog 64} {s : State 64} {x : M} {code : List (Instr Nat)}
  {L : Layout} {base : Nat} {off : Nat → Nat}

theorem sim_jmp_ok (hs : Rel0 c p s x) (hpc : x.pc = base) {t : Nat}
    (hat : AAt code base (lowerInstr L base off (.jmp t))) :
    ∃ x', ASteps code x x' ∧ Rel0 c p s x' ∧ x'.pc = off t := by
  have hat' : AAt code base [.jmp (off t)] := hat
  obtain ⟨f0, _⟩ := hat'
  refine ⟨{ x with pc := off t }, ASteps.single (by rw [astep_of_fetch (by rw [hpc]; exact f0)]; rfl),
    hs.congr rfl rfl rfl rfl rfl rfl rfl, rfl⟩

/-- `branch t`: both outcomes. -/
theorem sim_branch_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x)
    (hpc : x.pc = base) {t : Nat} (hat : AAt code base (lowerInstr L base off (.branch t)))
    {cc : W} {d : List W} (hd : s.dstack = cc :: d) :
    ∃ x', ASteps code x x' ∧ Rel0 c p { s with dstack := d } x' ∧
      x'.pc = (if Word.isTrue cc then off t else base + isize (.branch t : WordDialect.Instr 64)) := by
  have hat' : AAt code base (uf L 1 base ++ [.load x9 Reg.x19 0, .addImm Reg.x19 8, .test x9 x9,
      .jcc .ne (off t)]) := hat
  obtain ⟨hatuf, hatr⟩ := aat_append.mp hat'
  have hufl : (uf L 1 base).length = 4 := by simp [uf]
  rw [hufl] at hatr
  obtain ⟨f0, f1, f2, f3, _⟩ := hatr
  have hk : 1 ≤ s.dstack.length := by simp [hd]
  obtain ⟨x1, hs1, hr1, hpc1, hm1, _⟩ := uf_pass hg hs hL (by decide) (by decide) hk hpc hatuf
  obtain ⟨x2, hs2, hr2, hpc2, hv2, ho2, _⟩ := ld_step (code := code) hr1 (j := 0) (v := cc)
    (by simp [hd]) (rd := x9) (by simp) (disp := 0) (by simp) (fetch_cast f0 (by omega))
  obtain ⟨x3, hs3, hr3, hpc3, ho3⟩ := adj_step (code := code) hg hr2 (n := 1) (by simp [hd])
    (δ := 8) (by simp) (fetch_cast f1 (by omega))
  have hax3 : x3.regs x9 = cc := by rw [ho3 x9 (by decide), hv2]
  have e : s.dstack.drop 1 = d := by simp [hd]
  rw [e] at hr3
  let x4 : M := { x3.adv with flags := some (logicFlags (x3.regs x9 &&& x3.regs x9)) }
  have hst4 : step code x3 = .next x4 := by
    rw [astep_of_fetch (m := x3) (fetch_cast f2 (by omega))]; rfl
  have hr4 : Rel0 c p { s with dstack := d } x4 := hr3.congr rfl rfl rfl rfl rfl rfl rfl
  have hpc4 : x4.pc = base + 4 + 3 := by simp [x4, M.adv]; omega
  have hfl4 : x4.flags = some (logicFlags (cc &&& cc)) := by simp [x4, hax3]
  by_cases hc : cc = 0#64
  · have hst5 : step code x4 = .next x4.adv := by
      rw [astep_of_fetch (m := x4) (fetch_cast f3 (by omega))]
      simp [exec, hfl4, hc, Cc.holds, logicFlags]
    refine ⟨x4.adv, (((hs1.trans hs2).trans hs3).trans (ASteps.single hst4)).trans
      (ASteps.single hst5), hr4.congr rfl rfl rfl rfl rfl rfl rfl, ?_⟩
    simp [hc, Word.isTrue, M.adv, hpc4, isize, ufSize]
  · have hst5 : step code x4 = .next { x4 with pc := off t } := by
      rw [astep_of_fetch (m := x4) (fetch_cast f3 (by omega))]
      simp [exec, hfl4, hc, Cc.holds, logicFlags]
    refine ⟨{ x4 with pc := off t }, (((hs1.trans hs2).trans hs3).trans (ASteps.single hst4)).trans
      (ASteps.single hst5), hr4.congr rfl rfl rfl rfl rfl rfl rfl, ?_⟩
    simp [hc, Word.isTrue]

theorem sim_halt (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : AAt code base (lowerInstr L base off .halt)) : AExec code x (.halted x) := by
  have hat' : AAt code base [.exitHalt] := hat
  obtain ⟨f0, _⟩ := hat'
  exact AExec.halt (by rw [astep_of_fetch (by rw [hpc]; exact f0)]; rfl)

/-- The model's `call` itself: pushes the index of the return instruction onto the return stack
(`x23`) and writes `x30`. -/
theorem sim_call_core (hg : Geom c) (hs : Rel0 c p s x) (hpc : x.pc = base) {t : Nat}
    (hat : AAt code base [.call (off t)])
    (hret : base + 1 = offs p (s.pc + 1)) (hfitR : s.rstack.length + 2 ≤ c.rcap) :
    ∃ x', ASteps code x x' ∧ Rel0 c p { s with rstack := (s.pc + 1) :: s.rstack } x' ∧
      x'.pc = off t := by
  obtain ⟨f0, _⟩ := hat
  have hcapR := hs.capR
  have hrc := hg.rcap_le
  have hsp := hg.sp0_lt
  have hA1 : c.sp0 - 8 * c.rcap ≤ c.sp0 - 8 * (s.rstack.length + 1) := by omega
  have hA2 : c.sp0 - 8 * (s.rstack.length + 1) < c.sp0 := by omega
  have hAlt : c.sp0 - 8 * (s.rstack.length + 1) < 2 ^ 64 := by omega
  have hvalid := hs.xvalid.2.2.2.1 _ hA1 hA2
  have hsub : x.regs x23 - 8#64 = ofN (c.sp0 - 8 * (s.rstack.length + 1)) := by
    rw [hs.x23]
    show ofN _ - ofN 8 = _
    rw [ofN_sub (by omega)]
    congr 1
  obtain ⟨mem', hw⟩ : ∃ m', x.mem.write? (ofN (c.sp0 - 8 * (s.rstack.length + 1)))
      (BitVec.ofNat 64 (x.pc + 1)) = some m' := by simp [Memory.write?, hvalid]
  have hst : step code x = .next { ((x.setReg x30 (BitVec.ofNat 64 (x.pc + 1))).setReg x23
      (ofN (c.sp0 - 8 * (s.rstack.length + 1)))) with mem := mem', pc := off t } := by
    rw [astep_of_fetch (by rw [hpc]; exact f0)]
    simp only [exec, hsub, hw]
  refine ⟨_, ASteps.single hst, ?_, rfl⟩
  have hdE := hg.dEnd_lt
  have hcap := hs.capD
  refine { x19 := ?_, x20 := ?_, x21 := ?_, x22 := ?_, x23 := ?_, stack := ?_, regs := ?_,
           mem := ?_, rs := ?_, irvalid := hs.irvalid, xvalid := ?_, capD := hs.capD, capR := ?_,
           x24 := by simpa [M.setReg] using hs.x24,
           aux := aux_write_other hg.aEnd_lt hs.capA hs.aux hw hAlt
             (by rcases hg.dA_K with h | h <;> omega),
           capA := hs.capA }
  · simpa [M.setReg] using hs.x19
  · simpa [M.setReg] using hs.x20
  · simpa [M.setReg] using hs.x21
  · simpa [M.setReg] using hs.x22
  · simp [M.setReg]
  · intro i w hi
    have hi : s.dstack[i]? = some w := hi
    have hik : i < s.dstack.length := by
      by_cases hh : i < s.dstack.length
      · exact hh
      · rw [List.getElem?_eq_none (by omega)] at hi; simp at hi
    have hB : c.dEnd - 8 * s.dstack.length + 8 * i < 2 ^ 64 := by omega
    have hne : c.sp0 - 8 * (s.rstack.length + 1) ≠ c.dEnd - 8 * s.dstack.length + 8 * i := by
      rcases hg.dS_K with h | h <;> omega
    show mem'.read? _ = some w
    rw [read_write_nat hw hAlt hB]
    simp only [hne, ite_false]
    exact hs.stack i w hi
  · intro r hr
    have hrf := hg.rf_lt
    have hne : c.sp0 - 8 * (s.rstack.length + 1) ≠ c.rf + 8 * r := by
      rcases hg.dF_K with h | h <;> omega
    show mem'.read? _ = some _
    rw [read_write_nat hw hAlt (by omega)]
    simp only [hne, ite_false]
    exact hs.regs r hr
  · intro a ha
    have hmb := hg.mb_lt
    have hne : c.sp0 - 8 * (s.rstack.length + 1) ≠ c.mb + 8 * a := by
      rcases hg.dM_K with h | h <;> omega
    show mem'.read? _ = some _
    rw [read_write_nat hw hAlt (by omega)]
    simp only [hne, ite_false]
    exact hs.mem a ha
  · intro i a hi
    show mem'.read? _ = some _
    simp only [List.length_cons]
    cases i with
    | zero =>
      simp at hi; subst hi
      rw [show c.sp0 - 8 * (s.rstack.length + 1) + 8 * 0 = c.sp0 - 8 * (s.rstack.length + 1) by omega,
        read_write_nat hw hAlt hAlt]
      simp [hpc, hret, ofN]
    | succ i =>
      simp only [List.getElem?_cons_succ] at hi
      have hik : i < s.rstack.length := by
        have := (List.getElem?_eq_some_iff.mp hi).1; simpa using this
      have hB : c.sp0 - 8 * (s.rstack.length + 1) + 8 * (i + 1) < 2 ^ 64 := by omega
      have hne : c.sp0 - 8 * (s.rstack.length + 1) ≠
          c.sp0 - 8 * (s.rstack.length + 1) + 8 * (i + 1) := by omega
      rw [read_write_nat hw hAlt hB]
      simp only [hne, ite_false]
      have e : c.sp0 - 8 * (s.rstack.length + 1) + 8 * (i + 1) =
          c.sp0 - 8 * s.rstack.length + 8 * i := by omega
      rw [e]; exact hs.rs i a hi
  · have := Memory.write?_valid hw
    show RegionsValid c mem'.valid
    rw [this]; exact hs.xvalid
  · simp only [List.length_cons]; omega

theorem sim_ret_ok (hg : Geom c) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : AAt code base (lowerInstr L base off .ret)) {a : Nat} {rs : List Nat}
    (hr : s.rstack = a :: rs) (hsz : offs p a < 2 ^ 64) :
    ∃ x', ASteps code x x' ∧ Rel0 c p { s with rstack := rs } x' ∧ x'.pc = offs p a := by
  have hat' : AAt code base [.cmp x23 x22, .jcc .ne (base + 3), .exitTrap .returnUnderflow, .ret] := hat
  obtain ⟨f0, f1, f2, f3, _⟩ := hat'
  have hcapR := hs.capR
  have hrc := hg.rcap_le
  have hsp := hg.sp0_lt
  rw [hr] at hcapR
  simp only [List.length_cons] at hcapR
  let x1 : M := { x.adv with flags := some (subFlags (x.regs x23) (x.regs x22)) }
  have hst1 : step code x = .next x1 := by
    rw [astep_of_fetch (by rw [hpc]; exact f0)]; rfl
  have hpc1 : x1.pc = base + 1 := by simp [x1, M.adv, hpc]
  have hrsp : x.regs x23 = ofN (c.sp0 - 8 * (rs.length + 1)) := by rw [hs.x23, hr]; simp
  have hne : (x.regs x23 != x.regs x22) = true := by
    rw [hrsp, hs.x22]
    have : ofN (c.sp0 - 8 * (rs.length + 1)) ≠ ofN c.sp0 := by
      intro e; have := ofN_inj (by omega) hsp e; omega
    simpa using this
  have hst2 : step code x1 = .next { x1 with pc := base + 3 } := by
    rw [astep_of_fetch (m := x1) (by rw [hpc1]; exact f1)]
    simp [exec, x1, holds_ne, hne]
  have hread := hs.rs 0 a (by simp [hr])
  rw [hr] at hread
  simp only [List.length_cons, Nat.mul_zero, Nat.add_zero] at hread
  have hst3 : step code { x1 with pc := base + 3 } = .next { ((({ x1 with pc := base + 3 } : M).setReg
      x30 (ofN (offs p a))).setReg x23 (ofN (c.sp0 - 8 * rs.length))) with pc := offs p a } := by
    rw [astep_of_fetch (m := { x1 with pc := base + 3 }) f3]
    have hx1r : x1.regs x23 = ofN (c.sp0 - 8 * (rs.length + 1)) := hrsp
    have hx1m : x1.mem = x.mem := rfl
    have hadd : ofN (c.sp0 - 8 * (rs.length + 1)) + 8#64 = ofN (c.sp0 - 8 * rs.length) := by
      show ofN _ + ofN 8 = _
      rw [ofN_add]; congr 1; omega
    have hv : (ofN (offs p a)).toNat = offs p a := by
      simp [ofN, BitVec.toNat_ofNat, Nat.mod_eq_of_lt hsz]
    simp only [exec]
    rw [hx1m, hx1r, hread]
    simp only [hadd, hv]
  refine ⟨_, ((ASteps.single hst1).trans (ASteps.single hst2)).trans (ASteps.single hst3), ?_, rfl⟩
  refine { x19 := ?_, x20 := ?_, x21 := ?_, x22 := ?_, x23 := ?_, stack := ?_, regs := ?_,
           mem := ?_, rs := ?_, irvalid := hs.irvalid, xvalid := ?_, capD := hs.capD, capR := ?_,
           x24 := by simpa [M.setReg, x1, M.adv] using hs.x24, aux := hs.aux, capA := hs.capA }
  · simpa [M.setReg, x1, M.adv] using hs.x19
  · simpa [M.setReg, x1, M.adv] using hs.x20
  · simpa [M.setReg, x1, M.adv] using hs.x21
  · simpa [M.setReg, x1, M.adv] using hs.x22
  · simp [M.setReg]
  · exact hs.stack
  · exact hs.regs
  · exact hs.mem
  · intro i a' hi
    have h := hs.rs (i + 1) a' (by simpa [hr] using hi)
    rw [hr] at h
    simp only [List.length_cons] at h
    have e : c.sp0 - 8 * (rs.length + 1) + 8 * (i + 1) = c.sp0 - 8 * rs.length + 8 * i := by omega
    rw [e] at h
    exact h
  · exact hs.xvalid
  · show rs.length + 1 ≤ c.rcap
    omega

theorem sim_ret_trap (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : AAt code base (lowerInstr L base off .ret)) (hr : s.rstack = []) :
    AExec code x (.trapped .returnUnderflow) := by
  have hat' : AAt code base [.cmp x23 x22, .jcc .ne (base + 3), .exitTrap .returnUnderflow, .ret] := hat
  obtain ⟨f0, f1, f2, f3, _⟩ := hat'
  let x1 : M := { x.adv with flags := some (subFlags (x.regs x23) (x.regs x22)) }
  have hst1 : step code x = .next x1 := by
    rw [astep_of_fetch (by rw [hpc]; exact f0)]; rfl
  have hpc1 : x1.pc = base + 1 := by simp [x1, M.adv, hpc]
  have heq : x.regs x23 = x.regs x22 := by rw [hs.x23, hs.x22, hr]; simp
  have hfl : x1.flags = some (subFlags (x.regs x23) (x.regs x23)) := by simp [x1, heq]
  have hhold : Cc.ne.holds (subFlags (x.regs x23) (x.regs x23)) = false := by
    rw [holds_ne]; simp
  exact AExec.of_steps (ASteps.single hst1)
    (guard_trap (code := code) (pc := base + 1) (m := x1) (c := .ne) (t := .returnUnderflow)
      (f := subFlags (x.regs x23) (x.regs x23)) ⟨f1, f2, trivial⟩ hpc1 hfl hhold)

/-- `call t`: the return-stack guard, then the model's `call`. -/
theorem sim_call_ok (hg : Geom c) (hs : Rel0 c p s x) (hpc : x.pc = base) {t : Nat}
    (hLr : L.rGap = ofN (8 * c.rcap - 16)) (hat : AAt code base (lowerInstr L base off (.call t)))
    (hret : base + isize (.call t : WordDialect.Instr 64) = offs p (s.pc + 1))
    (hfitR : s.rstack.length + 2 ≤ c.rcap) :
    ∃ x', ASteps code x x' ∧ Rel0 c p { s with rstack := (s.pc + 1) :: s.rstack } x' ∧
      x'.pc = off t := by
  have hat' : AAt code base (ovfR L base ++ [.call (off t)]) := hat
  obtain ⟨hato, hatc⟩ := aat_append.mp hat'
  have hl : (ovfR L base).length = 6 := rfl
  rw [hl] at hatc
  obtain ⟨x1, hs1, hr1, hpc1, _⟩ := ovfR_pass hg hs hLr hfitR hpc hato
  obtain ⟨x', hs', hr', hpc'⟩ := sim_call_core hg hr1 hpc1 hatc (by simpa [isize] using hret) hfitR
  exact ⟨x', hs1.trans hs', hr', hpc'⟩

theorem sim_call_ovf (hg : Geom c) (hs : Rel0 c p s x) (hpc : x.pc = base) {t : Nat}
    (hLr : L.rGap = ofN (8 * c.rcap - 16)) (hat : AAt code base (lowerInstr L base off (.call t)))
    (h : ¬ s.rstack.length + 2 ≤ c.rcap) : AExec code x .overflow := by
  have hat' : AAt code base (ovfR L base ++ [.call (off t)]) := hat
  exact ovfR_trap hg hs hLr h hpc (aat_append.mp hat').1

end Ctl

end A64
end WordDialect
