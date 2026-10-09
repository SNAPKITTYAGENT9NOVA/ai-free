import RV.Seq

/-!
# RV.Micro

Micro-lemmas: how single RISC-V instructions (and the push pair) act on a machine state related to
an IR state by `Rel0`. Every IR-instruction simulation proof is a chain of these.
-/

namespace WordDialect
namespace RV

open Reg

theorem ea_nat (a j : Nat) : ofN a + BitVec.ofInt 64 (8 * (j : Int)) = ofN (a + 8 * j) := by
  rw [show (8 * (j : Int)) = ((8 * j : Nat) : Int) by omega, BitVec.ofInt_natCast]
  exact ofN_add _ _

/-- Load stack slot `j` into a scratch register. -/
theorem ld_stack {c : Cfg} {p : Prog 64} {s : State 64} {x : M} (hs : Rel0 c p s x)
    {j : Nat} {v : W} (hj : s.dstack[j]? = some v) (rd : Reg) {disp : Int}
    (hd : disp = 8 * (j : Int)) :
    exec (.load rd Reg.s1 disp) x = .next (x.mov rd v) := by
  have hread := hs.stack j v hj
  simp only [exec, M.ea, hs.s1, hd, ea_nat]
  rw [hread]

theorem mov_rel0 {c : Cfg} {p : Prog 64} {s : State 64} {x : M} (hs : Rel0 c p s x) (rd : Reg)
    (hr : rd ≠ s1 ∧ rd ≠ s2 ∧ rd ≠ s3 ∧ rd ≠ s4 ∧ rd ≠ s5 ∧ rd ≠ s6) (v : W) :
    Rel0 c p s (x.mov rd v) := by
  obtain ⟨h1, h2, h3, h4, h5, h6⟩ := hr
  refine hs.congr rfl ?_ ?_ ?_ ?_ ?_ ?_ <;>
    simp [M.mov, M.setReg, M.adv, Ne.symm h1, Ne.symm h2, Ne.symm h3, Ne.symm h4, Ne.symm h5,
      Ne.symm h6]

theorem arith_rel0 {c : Cfg} {p : Prog 64} {s : State 64} {x : M} (hs : Rel0 c p s x) (rd : Reg)
    (hr : rd ≠ s1 ∧ rd ≠ s2 ∧ rd ≠ s3 ∧ rd ≠ s4 ∧ rd ≠ s5 ∧ rd ≠ s6) (v : W) :
    Rel0 c p s (x.arith rd v) := by
  obtain ⟨h1, h2, h3, h4, h5, h6⟩ := hr
  refine hs.congr rfl ?_ ?_ ?_ ?_ ?_ ?_ <;>
    simp [M.arith, M.setReg, Ne.symm h1, Ne.symm h2, Ne.symm h3, Ne.symm h4, Ne.symm h5,
      Ne.symm h6]

/-- Store a register into stack slot `j`: the relation holds for the stack with that slot replaced. -/
theorem st_stack {c : Cfg} {p : Prog 64} {s : State 64} {x : M} (hg : Geom c) (hs : Rel0 c p s x)
    {j : Nat} (hj : j < s.dstack.length) (rs : Reg) {disp : Int} (hd : disp = 8 * (j : Int)) :
    ∃ mem', exec (.store Reg.s1 disp rs) x = .next { x.adv with mem := mem' } ∧
      Rel0 c p { s with dstack := s.dstack.set j (x.regs rs) } { x.adv with mem := mem' } := by
  have hcap := hs.capD
  have hcapR := hs.capR
  have hdE := hg.dEnd_lt
  have hA : c.dBase ≤ c.dEnd - 8 * s.dstack.length + 8 * j := by omega
  have hA' : c.dEnd - 8 * s.dstack.length + 8 * j < c.dEnd := by omega
  have hvalid := hs.xvalid.1 _ hA hA'
  obtain ⟨mem', hw⟩ : ∃ m', x.mem.write? (ofN (c.dEnd - 8 * s.dstack.length + 8 * j)) (x.regs rs)
      = some m' := by simp [Memory.write?, hvalid]
  refine ⟨mem', ?_, ?_⟩
  · simp only [exec, M.ea, hs.s1, hd, ea_nat]; rw [hw]
  · have hlen : (s.dstack.set j (x.regs rs)).length = s.dstack.length := by simp
    have hAlt : c.dEnd - 8 * s.dstack.length + 8 * j < 2 ^ 64 := by omega
    refine { s1 := ?_, s2 := ?_, s3 := ?_, s4 := ?_, s5 := ?_, s6 := ?_, stack := ?_,
             regs := ?_, mem := ?_, rs := ?_, aux := ?_, irvalid := hs.irvalid, xvalid := ?_,
             capD := ?_, capR := hs.capR, capA := hs.capA }
    · simpa [M.adv, hlen] using hs.s1
    · simpa [M.adv] using hs.s2
    · simpa [M.adv] using hs.s3
    · simpa [M.adv] using hs.s4
    · simpa [M.adv] using hs.s5
    · simpa [M.adv] using hs.s6
    · intro i w hi
      simp only [hlen]
      have hik : i < s.dstack.length := by
        have := (List.getElem?_eq_some_iff.mp hi).1; simpa using this
      by_cases hij : i = j
      · subst hij
        have h1 : (s.dstack.set i (x.regs rs))[i]? = some (x.regs rs) := by simp [hj]
        rw [h1] at hi
        cases hi
        rw [read_write_nat hw hAlt hAlt]; simp
      · rw [List.getElem?_set_ne (Ne.symm hij)] at hi
        have hne : c.dEnd - 8 * s.dstack.length + 8 * j ≠ c.dEnd - 8 * s.dstack.length + 8 * i := by
          omega
        rw [read_write_nat hw hAlt (by omega)]
        simp only [hne, ite_false]
        exact hs.stack i w hi
    · intro r hr
      have hrf := hg.rf_lt
      have hne : c.dEnd - 8 * s.dstack.length + 8 * j ≠ c.rf + 8 * r := by
        rcases hg.dS_F with h | h <;> omega
      rw [read_write_nat hw hAlt (by omega)]
      simp only [hne, ite_false]
      exact hs.regs r hr
    · intro a ha
      have hmb := hg.mb_lt
      have hne : c.dEnd - 8 * s.dstack.length + 8 * j ≠ c.mb + 8 * a := by
        rcases hg.dS_M with h | h <;> omega
      rw [read_write_nat hw hAlt (by omega)]
      simp only [hne, ite_false]
      exact hs.mem a ha
    · intro i a hi
      have hsp := hg.sp0_lt
      have hrc := hg.rcap_le
      have hi' : i < s.rstack.length := by
        by_cases hh : i < s.rstack.length
        · exact hh
        · have hn : s.rstack.length ≤ i := by omega
          rw [List.getElem?_eq_none hn] at hi; simp at hi
      have hne : c.dEnd - 8 * s.dstack.length + 8 * j ≠
          c.sp0 - 8 * s.rstack.length + 8 * i := by
        rcases hg.dS_K with h | h <;> omega
      have hkr : 8 * s.rstack.length ≤ c.sp0 := by omega
      have hB : c.sp0 - 8 * s.rstack.length + 8 * i < 2 ^ 64 := by omega
      rw [read_write_nat hw hAlt hB]
      simp only [hne, ite_false]
      exact hs.rs i a hi
    · exact aux_write_other hg.aEnd_lt hs.capA hs.aux hw hAlt (by rcases hg.dS_A with h | h <;> omega)
    · have := Memory.write?_valid hw
      show RegionsValid c mem'.valid
      rw [this]; exact hs.xvalid
    · simpa [hlen] using hcap

/-- Adjust the stack pointer upward by `n` words (popping `n` elements). -/
theorem adj_drop {c : Cfg} {p : Prog 64} {s : State 64} {x : M} (hg : Geom c) (hs : Rel0 c p s x)
    {n : Nat} (hn : n ≤ s.dstack.length) {δ : Int} (hd : δ = 8 * (n : Int)) :
    exec (.addImm Reg.s1 δ) x = .next (x.arith Reg.s1 (ofN (c.dEnd - 8 * (s.dstack.length - n)))) ∧
      Rel0 c p { s with dstack := s.dstack.drop n }
        (x.arith Reg.s1 (ofN (c.dEnd - 8 * (s.dstack.length - n)))) := by
  have hcap := hs.capD
  have hval : x.regs Reg.s1 + BitVec.ofInt 64 δ = ofN (c.dEnd - 8 * (s.dstack.length - n)) := by
    rw [hs.s1, hd, ea_nat]; congr 1; omega
  refine ⟨by simp only [exec, hval], ?_⟩
  refine { s1 := ?_, s2 := ?_, s3 := ?_, s4 := ?_, s5 := ?_, s6 := ?_, stack := ?_,
           regs := ?_, mem := ?_, rs := ?_, aux := hs.aux, irvalid := hs.irvalid, xvalid := ?_,
           capD := ?_, capR := hs.capR, capA := hs.capA }
  · simp [M.arith, M.setReg]
  · simpa [M.arith, M.setReg] using hs.s2
  · simpa [M.arith, M.setReg] using hs.s3
  · simpa [M.arith, M.setReg] using hs.s4
  · simpa [M.arith, M.setReg] using hs.s5
  · simpa [M.arith, M.setReg] using hs.s6
  · intro i w hi
    simp only [List.length_drop]
    rw [List.getElem?_drop] at hi
    have := hs.stack (n + i) w hi
    have e : c.dEnd - 8 * (s.dstack.length - n) + 8 * i =
        c.dEnd - 8 * s.dstack.length + 8 * (n + i) := by omega
    simp only [M.arith, M.setReg]
    rw [e]; exact this
  · exact hs.regs
  · exact hs.mem
  · exact hs.rs
  · exact hs.xvalid
  · simp only [List.length_drop]; omega

theorem ea_neg8 {a : Nat} (h : 8 ≤ a) : ofN a + BitVec.ofInt 64 (-8) = ofN (a - 8) := by
  have : BitVec.ofInt 64 (-8) = -(ofN 8) := by
    rw [show (-8 : Int) = -((8 : Nat) : Int) by omega, BitVec.ofInt_neg, BitVec.ofInt_natCast]
    rfl
  rw [this, ← BitVec.sub_eq_add_neg, ofN_sub h]

/-- A write inside the data-stack region leaves the register-file, IR-memory and return-stack
views unchanged. -/
theorem others_write {c : Cfg} {p : Prog 64} {s : State 64} {x : M} (hg : Geom c)
    (hs : Rel0 c p s x) {A : Nat} {v : W} {mem' : Memory 64} (hA1 : c.dBase ≤ A) (hA2 : A < c.dEnd)
    (hw : x.mem.write? (ofN A) v = some mem') :
    RegRel c mem' s.regs ∧ MemRel c mem' s.mem ∧ RsRel c p mem' s.rstack ∧
      AuxRel c mem' s.astack := by
  have hdE := hg.dEnd_lt
  have hAlt : A < 2 ^ 64 := by omega
  have hcapR := hs.capR
  have hrc := hg.rcap_le
  have hsp := hg.sp0_lt
  refine ⟨?_, ?_, ?_, aux_write_other hg.aEnd_lt hs.capA hs.aux hw hAlt
    (by rcases hg.dS_A with h | h <;> omega)⟩
  · intro r hr
    have hrf := hg.rf_lt
    have hne : A ≠ c.rf + 8 * r := by rcases hg.dS_F with h | h <;> omega
    rw [read_write_nat hw hAlt (by omega)]
    simp only [hne, ite_false]
    exact hs.regs r hr
  · intro a ha
    have hmb := hg.mb_lt
    have hne : A ≠ c.mb + 8 * a := by rcases hg.dS_M with h | h <;> omega
    rw [read_write_nat hw hAlt (by omega)]
    simp only [hne, ite_false]
    exact hs.mem a ha
  · intro i a hi
    have hi' : i < s.rstack.length := by
      by_cases hh : i < s.rstack.length
      · exact hh
      · have hn : s.rstack.length ≤ i := by omega
        rw [List.getElem?_eq_none hn] at hi; simp at hi
    have hkr : 8 * s.rstack.length ≤ c.sp0 := by omega
    have hB : c.sp0 - 8 * s.rstack.length + 8 * i < 2 ^ 64 := by omega
    have hne : A ≠ c.sp0 - 8 * s.rstack.length + 8 * i := by rcases hg.dS_K with h | h <;> omega
    rw [read_write_nat hw hAlt hB]
    simp only [hne, ite_false]
    exact hs.rs i a hi

/-- `addImm s1, -8; store [s1], rs` pushes the value of `rs`. -/
theorem push_pair {c : Cfg} {p : Prog 64} {s : State 64} {x : M} {code : List (Instr Nat)}
    (hg : Geom c) (hs : Rel0 c p s x) (rs : Reg) (hrs : rs ≠ s1)
    (hfit : c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd)
    (hat : RAt code x.pc [.addImm Reg.s1 (-8), .store Reg.s1 0 rs]) :
    ∃ x', RSteps code x x' ∧
      Rel0 c p { s with dstack := x.regs rs :: s.dstack } x' ∧ x'.pc = x.pc + 2 ∧
      (∀ r, r ≠ s1 → x'.regs r = x.regs r) := by
  obtain ⟨h1, h2, _⟩ := hat
  have hcap := hs.capD
  have hdE := hg.dEnd_lt
  have hA1 : c.dBase ≤ c.dEnd - 8 * (s.dstack.length + 1) := by omega
  have hA2 : c.dEnd - 8 * (s.dstack.length + 1) < c.dEnd := by omega
  have hAlt : c.dEnd - 8 * (s.dstack.length + 1) < 2 ^ 64 := by omega
  -- step 1: s1 := s1 - 8
  have hval : x.regs Reg.s1 + BitVec.ofInt 64 (-8) = ofN (c.dEnd - 8 * (s.dstack.length + 1)) := by
    rw [hs.s1, ea_neg8 (by omega)]
    congr 1
  have e1 : exec (.addImm Reg.s1 (-8)) x = .next (x.arith Reg.s1 (ofN (c.dEnd - 8 * (s.dstack.length + 1)))) := by
    simp only [exec, hval]
  obtain ⟨x1, hx1⟩ : ∃ x1, x1 = x.arith Reg.s1 (ofN (c.dEnd - 8 * (s.dstack.length + 1))) := ⟨_, rfl⟩
  rw [← hx1] at e1
  have hst1 : step code x = .next x1 := by rw [rstep_of_fetch h1, e1]
  -- step 2: store [s1], rs
  have hr15 : x1.regs Reg.s1 = ofN (c.dEnd - 8 * (s.dstack.length + 1)) := by simp [hx1, M.arith, M.setReg]
  have hrsv : x1.regs rs = x.regs rs := by simp [hx1, M.arith, M.setReg, hrs]
  have hvalid := hs.xvalid.1 _ hA1 hA2
  obtain ⟨mem', hw⟩ : ∃ m', x.mem.write? (ofN (c.dEnd - 8 * (s.dstack.length + 1))) (x.regs rs) = some m' := by
    simp [Memory.write?, hvalid]
  have e2 : exec (.store Reg.s1 0 rs) x1 = .next { x1.adv with mem := mem' } := by
    have : x1.mem = x.mem := by simp [hx1, M.arith, M.setReg]
    simp only [exec, M.ea, hr15, hrsv, this]
    have h0 : ofN (c.dEnd - 8 * (s.dstack.length + 1)) + BitVec.ofInt 64 0 = ofN (c.dEnd - 8 * (s.dstack.length + 1)) := by
      simp
    rw [h0, hw]
  have hpc1 : x1.pc = x.pc + 1 := by simp [hx1, M.arith, M.setReg]
  have hst2 : step code x1 = .next { x1.adv with mem := mem' } := by
    rw [rstep_of_fetch (m := x1) (by rw [hpc1]; exact h2), e2]
  refine ⟨{ x1.adv with mem := mem' }, (RSteps.single hst1).trans (RSteps.single hst2), ?_, ?_, ?_⟩
  · have ⟨hrg, hmm, hrr, hax⟩ := others_write hg hs hA1 hA2 hw
    have hlen : (x.regs rs :: s.dstack).length = s.dstack.length + 1 := by simp
    refine { s1 := ?_, s2 := ?_, s3 := ?_, s4 := ?_, s5 := ?_, s6 := ?_, stack := ?_,
             regs := hrg, mem := hmm, rs := hrr, aux := hax, irvalid := hs.irvalid, xvalid := ?_,
             capD := ?_, capR := hs.capR, capA := hs.capA }
    · simpa [hlen, M.adv, hx1, M.arith, M.setReg] using rfl
    · simpa [M.adv, hx1, M.arith, M.setReg] using hs.s2
    · simpa [M.adv, hx1, M.arith, M.setReg] using hs.s3
    · simpa [M.adv, hx1, M.arith, M.setReg] using hs.s4
    · simpa [M.adv, hx1, M.arith, M.setReg] using hs.s5
    · simpa [M.adv, hx1, M.arith, M.setReg] using hs.s6
    · intro i w hi
      simp only [hlen]
      cases i with
      | zero =>
        simp at hi; subst hi
        rw [show c.dEnd - 8 * (s.dstack.length + 1) + 8 * 0 = c.dEnd - 8 * (s.dstack.length + 1) by omega,
          read_write_nat hw hAlt hAlt]; simp
      | succ i =>
        simp only [List.getElem?_cons_succ] at hi
        have hik : i < s.dstack.length := by
          have := (List.getElem?_eq_some_iff.mp hi).1; simpa using this
        have hB : c.dEnd - 8 * (s.dstack.length + 1) + 8 * (i + 1) < 2 ^ 64 := by omega
        have hne : c.dEnd - 8 * (s.dstack.length + 1) ≠ c.dEnd - 8 * (s.dstack.length + 1) + 8 * (i + 1) := by omega
        rw [read_write_nat hw hAlt hB]
        simp only [hne, ite_false]
        have e : c.dEnd - 8 * (s.dstack.length + 1) + 8 * (i + 1) = c.dEnd - 8 * s.dstack.length + 8 * i := by omega
        rw [e]; exact hs.stack i w hi
    · have := Memory.write?_valid hw
      show RegionsValid c mem'.valid
      rw [this]; exact hs.xvalid
    · simpa [hlen] using hfit
  · simp [M.adv, hpc1]
  · intro r hr
    simp [M.adv, hx1, M.arith, M.setReg, hr]

end RV
end WordDialect
