import Wasm.Seq

/-!
# Wasm.Frame

How a write of one 8-byte cell into one region affects the four views `StackRel RegRel MemRel RsRel`:
the views of the other regions are unchanged, and the view of the written region changes in the
expected way. All statements are about `Rel0` and the byte memory only.
-/

namespace WordDialect
namespace Wasm

section Keep

variable {c : Cfg} {s : State 64} {w : WState} {m' : WMem} {A : Nat} {v : W}

theorem keep_stack (hs : Rel0 c s w) (hw : w.mem.write64 A v = some m')
    (hA : A + 8 ≤ c.dBase ∨ c.dEnd ≤ A) : StackRel c m' s.dstack := by
  have hcap := hs.capD
  intro i x hi
  have hik : i < s.dstack.length := by
    by_cases hh : i < s.dstack.length
    · exact hh
    · rw [List.getElem?_eq_none (by omega)] at hi; simp at hi
  rw [read64_write64_other hw (by omega)]
  exact hs.stack i x hi

theorem keep_regs (hs : Rel0 c s w) (hw : w.mem.write64 A v = some m')
    (hA : A + 8 ≤ c.rf ∨ c.rf + 8 * c.nregs ≤ A) : RegRel c m' s.regs := by
  intro r hr
  rw [read64_write64_other hw (by omega)]
  exact hs.regs r hr

theorem keep_mem (hs : Rel0 c s w) (hw : w.mem.write64 A v = some m')
    (hA : A + 8 ≤ c.mb ∨ c.mb + 8 * c.M ≤ A) : MemRel c m' s.mem := by
  intro a ha
  rw [read64_write64_other hw (by omega)]
  exact hs.mem a ha

theorem keep_rs (hs : Rel0 c s w) (hw : w.mem.write64 A v = some m')
    (hA : A + 8 ≤ c.rBase ∨ c.rEnd ≤ A) : RsRel c m' s.rstack := by
  have hcap := hs.capR
  intro i a hi
  have hik : i < s.rstack.length := by
    by_cases hh : i < s.rstack.length
    · exact hh
    · rw [List.getElem?_eq_none (by omega)] at hi; simp at hi
  rw [read64_write64_other hw (by omega)]
  exact hs.rs i a hi

end Keep

section Write

variable {c : Cfg} {s : State 64} {w : WState} {m' : WMem} {v : W}

/-- Write into data-stack slot `j`. -/
theorem wr_stack_at (hg : Geom c) (hs : Rel0 c s w) {j : Nat} (hj : j < s.dstack.length) {A : Nat}
    (hA : A = c.dEnd - 8 * s.dstack.length + 8 * j)
    (hw : w.mem.write64 A v = some m') :
    Rel0 c { s with dstack := s.dstack.set j v } { w with mem := m' } := by
  subst hA
  have hcap := hs.capD
  have hdG := hg.dEnd_ge
  obtain ⟨hsz, _⟩ := write64_size hw
  refine { sp := ?_, rp := hs.rp, stack := ?_, regs := ?_, mem := ?_, rs := ?_, irvalid := hs.irvalid,
           size := ?_, capD := ?_, capR := hs.capR }
  · simpa using hs.sp
  · intro i x hi
    simp only [List.length_set] at hi ⊢
    by_cases hij : i = j
    · subst hij
      have : x = v := by simpa [List.getElem?_set_self hj] using hi.symm
      subst this
      exact read64_write64_same hw
    · rw [List.getElem?_set_ne (by omega)] at hi
      rw [read64_write64_other hw (by omega)]
      exact hs.stack i x hi
  · exact keep_regs (s := s) hs hw (by rcases hg.dS_F with h | h <;> omega)
  · exact keep_mem (s := s) hs hw (by rcases hg.dS_M with h | h <;> omega)
  · exact keep_rs (s := s) hs hw (by rcases hg.dS_K with h | h <;> omega)
  · show m'.size = c.msize
    rw [hsz]; exact hs.size
  · simpa using hs.capD

theorem wr_stack (hg : Geom c) (hs : Rel0 c s w) {j : Nat} (hj : j < s.dstack.length)
    (hw : w.mem.write64 (c.dEnd - 8 * s.dstack.length + 8 * j) v = some m') :
    Rel0 c { s with dstack := s.dstack.set j v } { w with mem := m' } :=
  wr_stack_at hg hs hj rfl hw

/-- Update one global. -/
def setG (g : Nat → Val) (i : Nat) (v : Val) : Nat → Val := fun j => if j = i then v else g j

/-- Write virtual register `r`. -/
theorem wr_regs (hg : Geom c) (hs : Rel0 c s w) {r : Nat} (hr : r < c.nregs)
    (hw : w.mem.write64 (c.rf + 8 * r) v = some m') :
    Rel0 c { s with regs := State.setReg s.regs r v } { w with mem := m' } := by
  obtain ⟨hsz, _⟩ := write64_size hw
  refine { sp := hs.sp, rp := hs.rp, stack := ?_, regs := ?_, mem := ?_, rs := ?_,
           irvalid := hs.irvalid, size := ?_, capD := hs.capD, capR := hs.capR }
  · exact keep_stack (s := s) hs hw (by rcases hg.dS_F with h | h <;> omega)
  · intro r' hr'
    by_cases h : r' = r
    · subst h
      simpa [State.setReg] using read64_write64_same hw
    · rw [read64_write64_other hw (by omega)]
      simpa [State.setReg, h] using hs.regs r' hr'
  · exact keep_mem (s := s) hs hw (by rcases hg.dF_M with h | h <;> omega)
  · exact keep_rs (s := s) hs hw (by rcases hg.dF_K with h | h <;> omega)
  · show m'.size = c.msize
    rw [hsz]; exact hs.size

/-- Write IR memory word `a`, mirroring an IR store. -/
theorem wr_mem (hg : Geom c) (hs : Rel0 c s w) {a : W} {im : WordDialect.Memory 64}
    (hv : s.mem.write? a v = some im)
    (hw : w.mem.write64 (c.mb + 8 * a.toNat) v = some m') :
    Rel0 c { s with mem := im } { w with mem := m' } := by
  obtain ⟨hsz, _⟩ := write64_size hw
  have hvalid : s.mem.valid a = true := by
    by_cases hh : s.mem.valid a = true
    · exact hh
    · have := (Memory.write?_none_iff s.mem a v).mpr (by simpa using hh); rw [hv] at this; simp at this
  have hlt : a.toNat < c.M := by
    have := hs.irvalid a
    rw [hvalid] at this
    simpa using this.symm
  refine { sp := hs.sp, rp := hs.rp, stack := ?_, regs := ?_, mem := ?_, rs := ?_, irvalid := ?_,
           size := ?_, capD := hs.capD, capR := hs.capR }
  · exact keep_stack (s := s) hs hw (by rcases hg.dS_M with h | h <;> omega)
  · exact keep_regs (s := s) hs hw (by rcases hg.dF_M with h | h <;> omega)
  · intro a' ha'
    by_cases h : a' = a.toNat
    · subst h
      rw [read64_write64_same hw, BitVec.ofNat_toNat, BitVec.setWidth_eq]
      have := (Memory.read?_some (Memory.read_write_same hv)).2
      rw [this]
    · rw [read64_write64_other hw (by omega)]
      have hne : BitVec.ofNat 64 a' ≠ a := by
        intro e
        apply h
        have h2 := congrArg BitVec.toNat e
        have hM : a' < 2 ^ 64 := by have := hg.mb_le; have := hg.msize_lt; omega
        simp [BitVec.toNat_ofNat, Nat.mod_eq_of_lt hM] at h2
        exact h2
      rw [Memory.cell_write_other hv hne]
      exact hs.mem a' ha'
  · exact keep_rs (s := s) hs hw (by rcases hg.dM_K with h | h <;> omega)
  · intro a'; rw [Memory.write?_valid hv]; exact hs.irvalid a'
  · show m'.size = c.msize
    rw [hsz]; exact hs.size

/-- Adjust the data-stack pointer upward by `n` words (popping `n` elements). -/
theorem adj_sp (hg : Geom c) (hs : Rel0 c s w) {n : Nat} (hn : n ≤ s.dstack.length) :
    Rel0 c { s with dstack := s.dstack.drop n }
      { w with globals := setG w.globals spG (.i32 (ofN (c.dEnd - 8 * (s.dstack.length - n)))) } := by
  have hcap := hs.capD
  refine { sp := ?_, rp := ?_, stack := ?_, regs := hs.regs, mem := hs.mem, rs := hs.rs,
           irvalid := hs.irvalid, size := hs.size, capD := ?_, capR := hs.capR }
  · simp [setG, spG]
  · have : rpG ≠ spG := by decide
    simpa [setG, this] using hs.rp
  · intro i x hi
    simp only [List.length_drop]
    rw [List.getElem?_drop] at hi
    have := hs.stack (n + i) x hi
    have e : c.dEnd - 8 * (s.dstack.length - n) + 8 * i = c.dEnd - 8 * s.dstack.length + 8 * (n + i) := by
      omega
    rw [e]; exact this
  · simp only [List.length_drop]; omega

/-- Push: the stack pointer moved down one word and the new top written. -/
theorem push_rel (hg : Geom c) (hs : Rel0 c s w)
    (hfit : c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd)
    (hw : w.mem.write64 (c.dEnd - 8 * (s.dstack.length + 1)) v = some m') :
    Rel0 c { s with dstack := v :: s.dstack }
      { w with mem := m', globals := setG w.globals spG (.i32 (ofN (c.dEnd - 8 * (s.dstack.length + 1)))) } := by
  have hcap := hs.capD
  obtain ⟨hsz, _⟩ := write64_size hw
  refine { sp := ?_, rp := ?_, stack := ?_, regs := ?_, mem := ?_, rs := ?_, irvalid := hs.irvalid,
           size := ?_, capD := ?_, capR := hs.capR }
  · simp [setG, spG]
  · have : rpG ≠ spG := by decide
    simpa [setG, this] using hs.rp
  · intro i x hi
    simp only [List.length_cons] at hi ⊢
    cases i with
    | zero =>
      simp at hi; subst hi
      simpa using read64_write64_same hw
    | succ i =>
      simp only [List.getElem?_cons_succ] at hi
      have hik : i < s.dstack.length := by
        have := (List.getElem?_eq_some_iff.mp hi).1; simpa using this
      have e : c.dEnd - 8 * (s.dstack.length + 1) + 8 * (i + 1) = c.dEnd - 8 * s.dstack.length + 8 * i := by
        omega
      rw [e, read64_write64_other hw (by omega)]
      exact hs.stack i x hi
  · exact keep_regs (s := s) hs hw (by rcases hg.dS_F with h | h <;> omega)
  · exact keep_mem (s := s) hs hw (by rcases hg.dS_M with h | h <;> omega)
  · exact keep_rs (s := s) hs hw (by rcases hg.dS_K with h | h <;> omega)
  · show m'.size = c.msize
    rw [hsz]; exact hs.size
  · simp only [List.length_cons]; omega

/-- Call: the return-stack pointer moved down and the return index written. -/
theorem push_rs (hg : Geom c) (hs : Rel0 c s w) {a : Nat}
    (hfit : c.rBase + 8 * (s.rstack.length + 1) ≤ c.rEnd)
    (hw : w.mem.write64 (c.rEnd - 8 * (s.rstack.length + 1)) (BitVec.ofNat 64 a) = some m') :
    Rel0 c { s with rstack := a :: s.rstack }
      { w with mem := m', globals := setG w.globals rpG (.i32 (ofN (c.rEnd - 8 * (s.rstack.length + 1)))) } := by
  have hcap := hs.capR
  obtain ⟨hsz, _⟩ := write64_size hw
  refine { sp := ?_, rp := ?_, stack := ?_, regs := ?_, mem := ?_, rs := ?_, irvalid := hs.irvalid,
           size := ?_, capD := hs.capD, capR := ?_ }
  · have : spG ≠ rpG := by decide
    simpa [setG, this] using hs.sp
  · simp [setG, rpG]
  · exact keep_stack (s := s) hs hw (by rcases hg.dS_K with h | h <;> omega)
  · exact keep_regs (s := s) hs hw (by rcases hg.dF_K with h | h <;> omega)
  · exact keep_mem (s := s) hs hw (by rcases hg.dM_K with h | h <;> omega)
  · intro i x hi
    simp only [List.length_cons] at hi ⊢
    cases i with
    | zero =>
      simp at hi; subst hi
      simpa using read64_write64_same hw
    | succ i =>
      simp only [List.getElem?_cons_succ] at hi
      have hik : i < s.rstack.length := by
        have := (List.getElem?_eq_some_iff.mp hi).1; simpa using this
      have e : c.rEnd - 8 * (s.rstack.length + 1) + 8 * (i + 1) = c.rEnd - 8 * s.rstack.length + 8 * i := by
        omega
      rw [e, read64_write64_other hw (by omega)]
      exact hs.rs i x hi
  · show m'.size = c.msize
    rw [hsz]; exact hs.size
  · simp only [List.length_cons]; omega

/-- Return: the return-stack pointer moved up one entry. -/
theorem pop_rs (hs : Rel0 c s w) {a : Nat} {rs : List Nat} (hr : s.rstack = a :: rs) :
    Rel0 c { s with rstack := rs }
      { w with globals := setG w.globals rpG (.i32 (ofN (c.rEnd - 8 * rs.length))) } := by
  have hcap := hs.capR
  rw [hr] at hcap
  simp only [List.length_cons] at hcap
  refine { sp := ?_, rp := ?_, stack := hs.stack, regs := hs.regs, mem := hs.mem, rs := ?_,
           irvalid := hs.irvalid, size := hs.size, capD := hs.capD, capR := ?_ }
  · have : spG ≠ rpG := by decide
    simpa [setG, this] using hs.sp
  · simp [setG, rpG]
  · intro i x hi
    have h := hs.rs (i + 1) x (by simpa [hr] using hi)
    rw [hr] at h
    simp only [List.length_cons] at h
    have e : c.rEnd - 8 * (rs.length + 1) + 8 * (i + 1) = c.rEnd - 8 * rs.length + 8 * i := by omega
    rw [e] at h
    exact h
  · show c.rBase + 8 * rs.length ≤ c.rEnd
    omega

end Write

end Wasm
end WordDialect
