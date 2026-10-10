import CM0.SimStack

/-!
# CM0.SimMem

Register-file and IR-memory cells: frame lemmas for writes into those regions, the address
computation `lsls r0, r0, #2; add r0, r8` (`idx_addr`, `idx_steps`), and the IR-memory load and
store (`ld_mem`, `st_mem`).
-/

namespace WordDialect
namespace CM0

open Reg

theorem ofN_toNat (a : W) : ofN a.toNat = a := by
  apply BitVec.eq_of_toNat_eq
  simp [ofN, BitVec.toNat_ofNat, Nat.mod_eq_of_lt a.isLt]

theorem eaIdx_nat (mb : Nat) (a : W) : ofN mb + a * 4#32 = ofN (mb + 4 * a.toNat) := by
  have h : a * 4#32 = ofN (4 * a.toNat) := by
    have e : a = ofN a.toNat := (ofN_toNat a).symm
    calc a * 4#32 = ofN a.toNat * 4#32 := by rw [← e]
      _ = ofN (4 * a.toNat) := by
        simp only [ofN]; rw [Nat.mul_comm 4, BitVec.ofNat_mul]
  rw [h, ofN_add]

section Frame

variable {c : Cfg} {p : Prog 32} {s : State 32} {x : M}

/-- A write into the register file or IR memory leaves the data-stack view unchanged. -/
theorem wf_stack (hg : Geom c) (hs : Rel0 c p s x) {A : Nat} {v : W} {mem' : Memory 32}
    (hw : x.mem.write? (ofN A) v = some mem') (hAlt : A < 2 ^ 32)
    (hA : (c.rf ≤ A ∧ A < c.rf + 4 * c.nregs) ∨ (c.mb ≤ A ∧ A < c.mb + 4 * c.M)) :
    StackRel c mem' s.dstack := by
  have hcap := hs.capD
  have hdE := hg.dEnd_lt
  intro i w hi
  have hik : i < s.dstack.length := by
    by_cases hh : i < s.dstack.length
    · exact hh
    · rw [List.getElem?_eq_none (by omega)] at hi; simp at hi
  have hB : c.dEnd - 4 * s.dstack.length + 4 * i < 2 ^ 32 := by omega
  have hne : A ≠ c.dEnd - 4 * s.dstack.length + 4 * i := by
    rcases hA with ⟨h1, h2⟩ | ⟨h1, h2⟩ <;> rcases hg.dS_F with h | h <;>
      rcases hg.dS_M with h' | h' <;> omega
  rw [read_write_nat hw hAlt hB]
  simp only [hne, ite_false]
  exact hs.stack i w hi

theorem wf_rs (hg : Geom c) (hs : Rel0 c p s x) {A : Nat} {v : W} {mem' : Memory 32}
    (hw : x.mem.write? (ofN A) v = some mem') (hAlt : A < 2 ^ 32)
    (hA : (c.rf ≤ A ∧ A < c.rf + 4 * c.nregs) ∨ (c.mb ≤ A ∧ A < c.mb + 4 * c.M)) :
    RsRel c p mem' s.rstack := by
  have hcapR := hs.capR
  have hrc := hg.rcap_le
  have hsp := hg.sp0_lt
  intro i a hi
  have hi' : i < s.rstack.length := by
    by_cases hh : i < s.rstack.length
    · exact hh
    · rw [List.getElem?_eq_none (by omega)] at hi; simp at hi
  have hB : c.sp0 - 4 * s.rstack.length + 4 * i < 2 ^ 32 := by omega
  have hne : A ≠ c.sp0 - 4 * s.rstack.length + 4 * i := by
    rcases hA with ⟨h1, h2⟩ | ⟨h1, h2⟩ <;> rcases hg.dF_K with h | h <;>
      rcases hg.dM_K with h' | h' <;> omega
  rw [read_write_nat hw hAlt hB]
  simp only [hne, ite_false]
  exact hs.rs i a hi

theorem wf_regs_mb (hg : Geom c) (hs : Rel0 c p s x) {A : Nat} {v : W} {mem' : Memory 32}
    (hw : x.mem.write? (ofN A) v = some mem') (hAlt : A < 2 ^ 32)
    (hA : c.mb ≤ A ∧ A < c.mb + 4 * c.M) : RegRel c mem' s.regs := by
  have hrf := hg.rf_lt
  intro r hr
  have hne : A ≠ c.rf + 4 * r := by rcases hg.dF_M with h | h <;> omega
  rw [read_write_nat hw hAlt (by omega)]
  simp only [hne, ite_false]
  exact hs.regs r hr

theorem wf_mem_rf (hg : Geom c) (hs : Rel0 c p s x) {A : Nat} {v : W} {mem' : Memory 32}
    (hw : x.mem.write? (ofN A) v = some mem') (hAlt : A < 2 ^ 32)
    (hA : c.rf ≤ A ∧ A < c.rf + 4 * c.nregs) : MemRel c mem' s.mem := by
  have hmb := hg.mb_lt
  intro a ha
  have hne : A ≠ c.mb + 4 * a := by rcases hg.dF_M with h | h <;> omega
  rw [read_write_nat hw hAlt (by omega)]
  simp only [hne, ite_false]
  exact hs.mem a ha

/-- Load virtual register `r` (through `r5`). -/
theorem ld_reg (hs : Rel0 c p s x) {r : Nat} (hr : r < c.nregs) (rd : Reg) {disp : Int}
    (hd : disp = 4 * (r : Int)) :
    exec (.load rd Reg.r5 disp) x = .next (x.mov rd (s.regs r)) := by
  have hread := hs.regs r hr
  simp only [exec, M.ea, hs.r5, hd, ea_nat]
  rw [hread]

/-- Store into virtual register `r`. -/
theorem st_reg (hg : Geom c) (hs : Rel0 c p s x) {r : Nat} (hr : r < c.nregs) (rs : Reg)
    {disp : Int} (hd : disp = 4 * (r : Int)) :
    ∃ mem', exec (.store Reg.r5 disp rs) x = .next { x.adv with mem := mem' } ∧
      Rel0 c p { s with regs := State.setReg s.regs r (x.regs rs) } { x.adv with mem := mem' } := by
  have hrf := hg.rf_lt
  have hA1 : c.rf ≤ c.rf + 4 * r := by omega
  have hA2 : c.rf + 4 * r < c.rf + 4 * c.nregs := by omega
  have hAlt : c.rf + 4 * r < 2 ^ 32 := by omega
  have hvalid := hs.xvalid.2.1 _ hA1 hA2
  obtain ⟨mem', hw⟩ : ∃ m', x.mem.write? (ofN (c.rf + 4 * r)) (x.regs rs) = some m' := by
    simp [Memory.write?, hvalid]
  refine ⟨mem', ?_, ?_⟩
  · simp only [exec, M.ea, hs.r5, hd, ea_nat]; rw [hw]
  · have hA : (c.rf ≤ c.rf + 4 * r ∧ c.rf + 4 * r < c.rf + 4 * c.nregs) ∨
        (c.mb ≤ c.rf + 4 * r ∧ c.rf + 4 * r < c.mb + 4 * c.M) := Or.inl ⟨hA1, hA2⟩
    refine { r4 := ?_, r5 := ?_, r8 := ?_, r9 := ?_, sp := ?_,
             stack := wf_stack hg hs hw hAlt hA, regs := ?_, mem := wf_mem_rf hg hs hw hAlt ⟨hA1, hA2⟩,
             rs := wf_rs hg hs hw hAlt hA, irvalid := hs.irvalid, xvalid := ?_, capD := hs.capD,
             capR := hs.capR, r6 := by simpa [M.adv] using hs.r6,
             aux := aux_write_other hg.aEnd_lt hs.capA hs.aux hw hAlt
               (by rcases hg.dA_F with h | h <;> omega),
             capA := hs.capA }
    · simpa [M.adv] using hs.r4
    · simpa [M.adv] using hs.r5
    · simpa [M.adv] using hs.r8
    · simpa [M.adv] using hs.r9
    · simpa [M.adv] using hs.sp
    · intro r' hr'
      rw [read_write_nat hw hAlt (by omega)]
      by_cases h : r' = r
      · subst h; simp [State.setReg]
      · have hne : c.rf + 4 * r ≠ c.rf + 4 * r' := by omega
        simp only [hne, ite_false, State.setReg, h]
        exact hs.regs r' hr'
    · have := Memory.write?_valid hw
      show RegionsValid c mem'.valid
      rw [this]; exact hs.xvalid

/-- The address of IR cell `a`: `lsls r0, r0, #2; add r0, r8` (`r8`, a high register, can be
added but not used as a load base). -/
theorem ofInt_zero32 : BitVec.ofInt 32 0 = 0#32 := by decide

theorem idx_addr (mb : Nat) (a : W) : (a <<< (2 % 32)) + ofN mb = ofN (mb + 4 * a.toNat) := by
  apply BitVec.eq_of_toNat_eq
  simp only [BitVec.toNat_add, BitVec.toNat_shiftLeft, ofN, BitVec.toNat_ofNat, Nat.shiftLeft_eq,
    show (2 : Nat) % 32 = 2 from rfl, show (2 : Nat) ^ 2 = 4 from rfl]
  omega

/-- The address computation, preserving the relation (only `r0` changes). -/
theorem idx_steps (hs : Rel0 c p s x) {code : List (Instr Nat)} {a : W} (hrax : x.regs r0 = a)
    (hat : RAt code x.pc [.shlImm r0 2, .add r0 Reg.r8]) :
    ∃ x2, RSteps code x x2 ∧ Rel0 c p s x2 ∧ x2.pc = x.pc + 2 ∧
      x2.regs r0 = ofN (c.mb + 4 * a.toNat) ∧ (∀ r, r ≠ r0 → x2.regs r = x.regs r) ∧
      x2.mem = x.mem := by
  obtain ⟨f0, f1, _⟩ := hat
  let x1 := x.arith r0 (x.regs r0 <<< (2 % 32))
  have hst1 : step code x = .next x1 := by rw [rstep_of_fetch f0]; rfl
  have hpc1 : x1.pc = x.pc + 1 := by simp [x1, M.arith]
  let x2 := x1.arith r0 (x1.regs r0 + x1.regs Reg.r8)
  have hst2 : step code x1 = .next x2 := by rw [rstep_of_fetch (m := x1) (by rw [hpc1]; exact f1)]; rfl
  refine ⟨x2, (RSteps.single hst1).trans (RSteps.single hst2), ?_, by simp [x2, x1, M.arith], ?_,
    ?_, by simp [x2, x1, M.arith, M.setReg]⟩
  · refine hs.congr (by simp [x2, x1, M.arith, M.setReg]) ?_ ?_ ?_ ?_ ?_ ?_ <;>
      simp [x2, x1, M.arith, M.setReg]
  · simp only [x2, x1, M.arith, M.setReg, ite_true, show (Reg.r8 = r0) = False by decide, ite_false,
      hrax, hs.r8]
    exact idx_addr c.mb a
  · intro r hr; simp [x2, x1, M.arith, M.setReg, hr]

/-- Load IR memory cell at word address `a` (`r0` holds its address). -/
theorem ld_mem (hs : Rel0 c p s x) {a v : W} (hr : s.mem.read? a = some v)
    (hrax : x.regs r0 = ofN (c.mb + 4 * a.toNat)) :
    exec (.load r0 r0 0) x = .next (x.mov r0 v) := by
  obtain ⟨hv, hc⟩ := Memory.read?_some hr
  have hlt : a.toNat < c.M := by
    have := hs.irvalid a
    rw [hv] at this
    simpa using this.symm
  have hread := hs.mem a.toNat hlt
  rw [ofN_toNat, hc] at hread
  simp only [exec, M.ea, hrax, ofInt_zero32, BitVec.add_zero]
  rw [hread]

/-- Store into IR memory cell `a` (`r0` holds its address, `r1 = v`). -/
theorem st_mem (hg : Geom c) (hs : Rel0 c p s x) {a v : W} {m : Memory 32}
    (hw : s.mem.write? a v = some m) (hrax : x.regs r0 = ofN (c.mb + 4 * a.toNat))
    (hrcx : x.regs r1 = v) :
    ∃ mem', exec (.store r0 0 r1) x = .next { x.adv with mem := mem' } ∧
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
  have hA1 : c.mb ≤ c.mb + 4 * a.toNat := by omega
  have hA2 : c.mb + 4 * a.toNat < c.mb + 4 * c.M := by omega
  have hAlt : c.mb + 4 * a.toNat < 2 ^ 32 := by omega
  have hvalid := hs.xvalid.2.2.1 _ hA1 hA2
  obtain ⟨mem', hw'⟩ : ∃ m', x.mem.write? (ofN (c.mb + 4 * a.toNat)) v = some m' := by
    simp [Memory.write?, hvalid]
  refine ⟨mem', ?_, ?_⟩
  · simp only [exec, M.ea, hrax, hrcx, ofInt_zero32, BitVec.add_zero]; rw [hw']
  · have hA : (c.rf ≤ c.mb + 4 * a.toNat ∧ c.mb + 4 * a.toNat < c.rf + 4 * c.nregs) ∨
        (c.mb ≤ c.mb + 4 * a.toNat ∧ c.mb + 4 * a.toNat < c.mb + 4 * c.M) := Or.inr ⟨hA1, hA2⟩
    refine { r4 := ?_, r5 := ?_, r8 := ?_, r9 := ?_, sp := ?_,
             stack := wf_stack hg hs hw' hAlt hA, regs := wf_regs_mb hg hs hw' hAlt ⟨hA1, hA2⟩,
             mem := ?_, rs := wf_rs hg hs hw' hAlt hA, irvalid := ?_, xvalid := ?_,
             capD := hs.capD, capR := hs.capR, r6 := by simpa [M.adv] using hs.r6,
             aux := aux_write_other hg.aEnd_lt hs.capA hs.aux hw' hAlt
               (by rcases hg.dA_M with h | h <;> omega),
             capA := hs.capA }
    · simpa [M.adv] using hs.r4
    · simpa [M.adv] using hs.r5
    · simpa [M.adv] using hs.r8
    · simpa [M.adv] using hs.r9
    · simpa [M.adv] using hs.sp
    · intro a' ha'
      have hMlt : c.M < 2 ^ 32 := by omega
      rw [read_write_nat hw' hAlt (by omega)]
      by_cases h : a' = a.toNat
      · subst h
        simp only [ite_true]
        rw [ofN_toNat]
        have := (Memory.read?_some (Memory.read_write_same hw)).2
        rw [this]
      · have hne : c.mb + 4 * a.toNat ≠ c.mb + 4 * a' := by omega
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

end CM0
end WordDialect
