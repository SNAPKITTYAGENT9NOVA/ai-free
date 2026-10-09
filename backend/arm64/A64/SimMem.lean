import A64.SimStack

/-!
# A64.SimMem

Register-file and IR-memory cells: frame lemmas for writes into those regions, the address
bounds guard, and the simulation theorems for `push pop load store` (success and `badAddress`).
-/

namespace WordDialect
namespace A64

open Reg

theorem ofN_toNat (a : W) : ofN a.toNat = a := by
  apply BitVec.eq_of_toNat_eq
  simp [ofN, BitVec.toNat_ofNat, Nat.mod_eq_of_lt a.isLt]

theorem eaIdx_nat (mb : Nat) (a : W) : ofN mb + a * 8#64 = ofN (mb + 8 * a.toNat) := by
  have h : a * 8#64 = ofN (8 * a.toNat) := by
    have e : a = ofN a.toNat := (ofN_toNat a).symm
    calc a * 8#64 = ofN a.toNat * 8#64 := by rw [← e]
      _ = ofN (8 * a.toNat) := by
        simp only [ofN]; rw [Nat.mul_comm 8, BitVec.ofNat_mul]
  rw [h, ofN_add]

section Frame

variable {c : Cfg} {p : Prog 64} {s : State 64} {x : M}

/-- A write into the register file or IR memory leaves the data-stack view unchanged. -/
theorem wf_stack (hg : Geom c) (hs : Rel0 c p s x) {A : Nat} {v : W} {mem' : Memory 64}
    (hw : x.mem.write? (ofN A) v = some mem') (hAlt : A < 2 ^ 64)
    (hA : (c.rf ≤ A ∧ A < c.rf + 8 * c.nregs) ∨ (c.mb ≤ A ∧ A < c.mb + 8 * c.M)) :
    StackRel c mem' s.dstack := by
  have hcap := hs.capD
  have hdE := hg.dEnd_lt
  intro i w hi
  have hik : i < s.dstack.length := by
    by_cases hh : i < s.dstack.length
    · exact hh
    · rw [List.getElem?_eq_none (by omega)] at hi; simp at hi
  have hB : c.dEnd - 8 * s.dstack.length + 8 * i < 2 ^ 64 := by omega
  have hne : A ≠ c.dEnd - 8 * s.dstack.length + 8 * i := by
    rcases hA with ⟨h1, h2⟩ | ⟨h1, h2⟩ <;> rcases hg.dS_F with h | h <;>
      rcases hg.dS_M with h' | h' <;> omega
  rw [read_write_nat hw hAlt hB]
  simp only [hne, ite_false]
  exact hs.stack i w hi

theorem wf_rs (hg : Geom c) (hs : Rel0 c p s x) {A : Nat} {v : W} {mem' : Memory 64}
    (hw : x.mem.write? (ofN A) v = some mem') (hAlt : A < 2 ^ 64)
    (hA : (c.rf ≤ A ∧ A < c.rf + 8 * c.nregs) ∨ (c.mb ≤ A ∧ A < c.mb + 8 * c.M)) :
    RsRel c p mem' s.rstack := by
  have hcapR := hs.capR
  have hrc := hg.rcap_le
  have hsp := hg.sp0_lt
  intro i a hi
  have hi' : i < s.rstack.length := by
    by_cases hh : i < s.rstack.length
    · exact hh
    · rw [List.getElem?_eq_none (by omega)] at hi; simp at hi
  have hB : c.sp0 - 8 * s.rstack.length + 8 * i < 2 ^ 64 := by omega
  have hne : A ≠ c.sp0 - 8 * s.rstack.length + 8 * i := by
    rcases hA with ⟨h1, h2⟩ | ⟨h1, h2⟩ <;> rcases hg.dF_K with h | h <;>
      rcases hg.dM_K with h' | h' <;> omega
  rw [read_write_nat hw hAlt hB]
  simp only [hne, ite_false]
  exact hs.rs i a hi

theorem wf_regs_mb (hg : Geom c) (hs : Rel0 c p s x) {A : Nat} {v : W} {mem' : Memory 64}
    (hw : x.mem.write? (ofN A) v = some mem') (hAlt : A < 2 ^ 64)
    (hA : c.mb ≤ A ∧ A < c.mb + 8 * c.M) : RegRel c mem' s.regs := by
  have hrf := hg.rf_lt
  intro r hr
  have hne : A ≠ c.rf + 8 * r := by rcases hg.dF_M with h | h <;> omega
  rw [read_write_nat hw hAlt (by omega)]
  simp only [hne, ite_false]
  exact hs.regs r hr

theorem wf_mem_rf (hg : Geom c) (hs : Rel0 c p s x) {A : Nat} {v : W} {mem' : Memory 64}
    (hw : x.mem.write? (ofN A) v = some mem') (hAlt : A < 2 ^ 64)
    (hA : c.rf ≤ A ∧ A < c.rf + 8 * c.nregs) : MemRel c mem' s.mem := by
  have hmb := hg.mb_lt
  intro a ha
  have hne : A ≠ c.mb + 8 * a := by rcases hg.dF_M with h | h <;> omega
  rw [read_write_nat hw hAlt (by omega)]
  simp only [hne, ite_false]
  exact hs.mem a ha

/-- Load virtual register `r` (through `x20`). -/
theorem ld_reg (hs : Rel0 c p s x) {r : Nat} (hr : r < c.nregs) (rd : Reg) {disp : Int}
    (hd : disp = 8 * (r : Int)) :
    exec (.load rd Reg.x20 disp) x = .next (x.mov rd (s.regs r)) := by
  have hread := hs.regs r hr
  simp only [exec, M.ea, hs.x20, hd, ea_nat]
  rw [hread]

/-- Store into virtual register `r`. -/
theorem st_reg (hg : Geom c) (hs : Rel0 c p s x) {r : Nat} (hr : r < c.nregs) (rs : Reg)
    {disp : Int} (hd : disp = 8 * (r : Int)) :
    ∃ mem', exec (.store Reg.x20 disp rs) x = .next { x.adv with mem := mem' } ∧
      Rel0 c p { s with regs := State.setReg s.regs r (x.regs rs) } { x.adv with mem := mem' } := by
  have hrf := hg.rf_lt
  have hA1 : c.rf ≤ c.rf + 8 * r := by omega
  have hA2 : c.rf + 8 * r < c.rf + 8 * c.nregs := by omega
  have hAlt : c.rf + 8 * r < 2 ^ 64 := by omega
  have hvalid := hs.xvalid.2.1 _ hA1 hA2
  obtain ⟨mem', hw⟩ : ∃ m', x.mem.write? (ofN (c.rf + 8 * r)) (x.regs rs) = some m' := by
    simp [Memory.write?, hvalid]
  refine ⟨mem', ?_, ?_⟩
  · simp only [exec, M.ea, hs.x20, hd, ea_nat]; rw [hw]
  · have hA : (c.rf ≤ c.rf + 8 * r ∧ c.rf + 8 * r < c.rf + 8 * c.nregs) ∨
        (c.mb ≤ c.rf + 8 * r ∧ c.rf + 8 * r < c.mb + 8 * c.M) := Or.inl ⟨hA1, hA2⟩
    refine { x19 := ?_, x20 := ?_, x21 := ?_, x22 := ?_, x23 := ?_,
             stack := wf_stack hg hs hw hAlt hA, regs := ?_, mem := wf_mem_rf hg hs hw hAlt ⟨hA1, hA2⟩,
             rs := wf_rs hg hs hw hAlt hA, irvalid := hs.irvalid, xvalid := ?_, capD := hs.capD,
             capR := hs.capR, x24 := by simpa [M.adv] using hs.x24,
             aux := aux_write_other hg.aEnd_lt hs.capA hs.aux hw hAlt
               (by rcases hg.dA_F with h | h <;> omega),
             capA := hs.capA }
    · simpa [M.adv] using hs.x19
    · simpa [M.adv] using hs.x20
    · simpa [M.adv] using hs.x21
    · simpa [M.adv] using hs.x22
    · simpa [M.adv] using hs.x23
    · intro r' hr'
      rw [read_write_nat hw hAlt (by omega)]
      by_cases h : r' = r
      · subst h; simp [State.setReg]
      · have hne : c.rf + 8 * r ≠ c.rf + 8 * r' := by omega
        simp only [hne, ite_false, State.setReg, h]
        exact hs.regs r' hr'
    · have := Memory.write?_valid hw
      show RegionsValid c mem'.valid
      rw [this]; exact hs.xvalid

/-- Load IR memory cell at word address `a` (`x9 = a`). -/
theorem ld_mem (hs : Rel0 c p s x) {a v : W} (hr : s.mem.read? a = some v) (hrax : x.regs x9 = a) :
    exec (.loadIdx x9 Reg.x21 x9) x = .next (x.mov x9 v) := by
  obtain ⟨hv, hc⟩ := Memory.read?_some hr
  have hlt : a.toNat < c.M := by
    have := hs.irvalid a
    rw [hv] at this
    simpa using this.symm
  have hread := hs.mem a.toNat hlt
  rw [ofN_toNat, hc] at hread
  simp only [exec, M.eaIdx, hs.x21, hrax, eaIdx_nat]
  rw [hread]

/-- Store into IR memory cell `a` (`x9 = a`, `x10 = v`). -/
theorem st_mem (hg : Geom c) (hs : Rel0 c p s x) {a v : W} {m : Memory 64}
    (hw : s.mem.write? a v = some m) (hrax : x.regs x9 = a) (hrcx : x.regs x10 = v) :
    ∃ mem', exec (.storeIdx Reg.x21 x9 x10) x = .next { x.adv with mem := mem' } ∧
      Rel0 c p { s with mem := m } { x.adv with mem := mem' } := by
  have hv : s.mem.valid a = true := by
    by_cases hh : s.mem.valid a = true
    · exact hh
    · have := (Memory.write?_none_iff s.mem a v).mpr (by simpa using hh); rw [hw] at this; simp at this
  have hlt : a.toNat < c.M := by
    have := hs.irvalid a
    rw [hv] at this
    simpa using this.symm
  have hmb := hg.mb_lt
  have hA1 : c.mb ≤ c.mb + 8 * a.toNat := by omega
  have hA2 : c.mb + 8 * a.toNat < c.mb + 8 * c.M := by omega
  have hAlt : c.mb + 8 * a.toNat < 2 ^ 64 := by omega
  have hvalid := hs.xvalid.2.2.1 _ hA1 hA2
  obtain ⟨mem', hw'⟩ : ∃ m', x.mem.write? (ofN (c.mb + 8 * a.toNat)) v = some m' := by
    simp [Memory.write?, hvalid]
  refine ⟨mem', ?_, ?_⟩
  · simp only [exec, M.eaIdx, hs.x21, hrax, hrcx, eaIdx_nat]; rw [hw']
  · have hA : (c.rf ≤ c.mb + 8 * a.toNat ∧ c.mb + 8 * a.toNat < c.rf + 8 * c.nregs) ∨
        (c.mb ≤ c.mb + 8 * a.toNat ∧ c.mb + 8 * a.toNat < c.mb + 8 * c.M) := Or.inr ⟨hA1, hA2⟩
    refine { x19 := ?_, x20 := ?_, x21 := ?_, x22 := ?_, x23 := ?_,
             stack := wf_stack hg hs hw' hAlt hA, regs := wf_regs_mb hg hs hw' hAlt ⟨hA1, hA2⟩,
             mem := ?_, rs := wf_rs hg hs hw' hAlt hA, irvalid := ?_, xvalid := ?_,
             capD := hs.capD, capR := hs.capR, x24 := by simpa [M.adv] using hs.x24,
             aux := aux_write_other hg.aEnd_lt hs.capA hs.aux hw' hAlt
               (by rcases hg.dA_M with h | h <;> omega),
             capA := hs.capA }
    · simpa [M.adv] using hs.x19
    · simpa [M.adv] using hs.x20
    · simpa [M.adv] using hs.x21
    · simpa [M.adv] using hs.x22
    · simpa [M.adv] using hs.x23
    · intro a' ha'
      have hMlt : c.M < 2 ^ 64 := by omega
      rw [read_write_nat hw' hAlt (by omega)]
      by_cases h : a' = a.toNat
      · subst h
        simp only [ite_true]
        rw [ofN_toNat]
        have := (Memory.read?_some (Memory.read_write_same hw)).2
        rw [this]
      · have hne : c.mb + 8 * a.toNat ≠ c.mb + 8 * a' := by omega
        have hne' : ofN a' ≠ a := by
          intro e
          apply h
          have := ofN_inj (by omega) a.isLt (e.trans (ofN_toNat a).symm)
          omega
        simp only [hne, ite_false]
        rw [Memory.cell_write_other hw hne']
        exact hs.mem a' ha'
    · intro a'; rw [Memory.write?_valid hw]; exact hs.irvalid a'
    · have := Memory.write?_valid hw'
      show RegionsValid c mem'.valid
      rw [this]; exact hs.xvalid

end Frame

end A64
end WordDialect
