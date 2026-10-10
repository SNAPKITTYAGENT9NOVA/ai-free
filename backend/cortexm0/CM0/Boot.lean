import CM0.Init

/-!
# CM0.Boot

Booting from flash, proved. A Cortex-M runs from flash: the vector table and code are there, and
`.data` (IR memory, the register file and the semihosting block) is linked to RAM with its load
address in flash. The reset handler first copies `.data` to RAM with the ten-instruction loop
`Emit.copyCode`, printed from the model like the lowered program, then runs the prologue.

`Init.lean` assumes RAM already holds the image (`Loader.Holds`). Here that assumption becomes a
theorem: from facts about flash only (`FlashHolds`: flash holds the `.data` image word by word,
the `.data` area in RAM is addressable, the two do not overlap), the copy loop runs and reaches
a state where `Loader.Holds` is true (`copy_holds`). `boot_correct` composes it with
`binary_correct`: from the flash image, the copy loop, the prologue and the lowered code reach
the IR outcome from `State.init` on the memory image, or exit with `overflow`.

* `copy_loop`: the loop invariant. After `j` of `n` words, RAM holds the first `j` image words,
  every address outside the RAM area reads as before (so flash still holds the image), and
  validity is unchanged.
* `copy_run`: the whole loop, including `n = 0`.
-/

namespace WordDialect
namespace CM0
namespace Emit

open Reg

theorem ofInt_four : BitVec.ofInt 32 4 = ofN 4 := by decide

theorem ofInt_m1 : BitVec.ofInt 32 (-1) = ofN (2 ^ 32 - 1) := by decide

theorem add_ofInt_m1 (k : Nat) (hk : 0 < k) (hk' : k < 2 ^ 32) :
    ofN k + BitVec.ofInt 32 (-1) = ofN (k - 1) := by
  rw [ofInt_m1, ofN_add]
  apply BitVec.eq_of_toNat_eq
  simp only [ofN, BitVec.toNat_ofNat]
  omega

theorem ofN_eq_zero {k : Nat} (hk : k < 2 ^ 32) : ofN k = 0#32 ↔ k = 0 := by
  constructor
  · intro h
    have := congrArg BitVec.toNat h
    simp [ofN, BitVec.toNat_ofNat, Nat.mod_eq_of_lt hk] at this
    exact this
  · rintro rfl; rfl

@[simp] theorem M.setReg_pc (m : M) (r : Reg) (v : W) : (m.setReg r v).pc = m.pc := rfl
@[simp] theorem M.setReg_mem (m : M) (r : Reg) (v : W) : (m.setReg r v).mem = m.mem := rfl

theorem ofN_add4 (a : Nat) (j : Nat) : ofN (a + 4 * j) + 4#32 = ofN (a + 4 * (j + 1)) := by
  rw [show (4#32 : W) = ofN 4 from rfl, ofN_add]; congr 1

section Loop

variable {lma vma n : Nat} {img : Nat → W} {x0 : M}

/-- Addresses outside the RAM area `[vma, vma + 4n)` read as in the initial state. -/
def Frame (vma n : Nat) (x0 m : M) : Prop :=
  ∀ A, A < 2 ^ 32 → (A < vma ∨ vma + 4 * n ≤ A) → m.mem.read? (ofN A) = x0.mem.read? (ofN A)

/-- One pass through the loop body, from index 4 to index 9 (just before `bnez`). -/
theorem copy_body (hV : vma + 4 * n ≤ 2 ^ 32) (hL : lma + 4 * n ≤ 2 ^ 32) {j : Nat} (hj : j < n)
    {m : M} (hpc : m.pc = 4) (h1 : m.regs r1 = ofN (lma + 4 * j))
    (h2 : m.regs r2 = ofN (vma + 4 * j)) {v : W}
    (hread : m.mem.read? (ofN (lma + 4 * j)) = some v)
    (hvalid : m.mem.valid (ofN (vma + 4 * j)) = true) :
    ∃ m', RSteps (copyCode (ofN lma) (ofN vma) n) m m' ∧ m'.pc = 9 ∧
      m'.regs r1 = ofN (lma + 4 * (j + 1)) ∧ m'.regs r2 = ofN (vma + 4 * (j + 1)) ∧
      m'.regs r3 = m.regs r3 + BitVec.ofInt 32 (-1) ∧
      m.mem.write? (ofN (vma + 4 * j)) v = some m'.mem := by
  obtain ⟨mem', hw⟩ : ∃ mem', m.mem.write? (ofN (vma + 4 * j)) v = some mem' := by
    cases h : m.mem.write? (ofN (vma + 4 * j)) v with
    | none => rw [Memory.write?_none_iff] at h; rw [h] at hvalid; cases hvalid
    | some mem' => exact ⟨mem', rfl⟩
  let code := copyCode (ofN lma) (ofN vma) n
  let m1 := m.mov r0 v
  have s1 : step code m = .next m1 := by
    simp only [code, step, hpc, copyCode]
    simp [exec, M.ea, h1, hread, m1]
  let m2 : M := { m1.adv with mem := mem' }
  have s2 : step code m1 = .next m2 := by
    have : m1.pc = 5 := by simp [m1, M.mov, M.adv, hpc]
    simp only [code, step, this, copyCode]
    have hr2 : m1.regs r2 = ofN (vma + 4 * j) := by simp [m1, M.mov, M.setReg, M.adv, h2]
    have hr0 : m1.regs r0 = v := by simp [m1, M.mov, M.setReg, M.adv]
    have hm : m1.mem = m.mem := by simp [m1, M.mov, M.setReg, M.adv]
    simp [exec, M.ea, hr2, hr0, hm, hw, m2]
  let m3 := m2.arith r1 (m2.regs r1 + BitVec.ofInt 32 4)
  have s3 : step code m2 = .next m3 := by
    have : m2.pc = 6 := by simp [m2, m1, M.mov, M.adv, hpc]
    simp only [code, step, this, copyCode]; rfl
  let m4 := m3.arith r2 (m3.regs r2 + BitVec.ofInt 32 4)
  have s4 : step code m3 = .next m4 := by
    have : m3.pc = 7 := by simp [m3, m2, m1, M.arith, M.mov, M.adv, hpc]
    simp only [code, step, this, copyCode]; rfl
  let m5 := m4.arith r3 (m4.regs r3 + BitVec.ofInt 32 (-1))
  have s5 : step code m4 = .next m5 := by
    have : m4.pc = 8 := by simp [m4, m3, m2, m1, M.arith, M.mov, M.adv, hpc]
    simp only [code, step, this, copyCode]; rfl
  refine ⟨m5, .cons s1 (.cons s2 (.cons s3 (.cons s4 (.single s5)))), ?_, ?_, ?_, ?_, ?_⟩
  · simp [m5, m4, m3, m2, m1, M.arith, M.mov, M.adv, hpc]
  · simp [m5, m4, m3, m2, m1, M.arith, M.mov, M.adv, M.setReg, h1, ofN_add4]
  · simp [m5, m4, m3, m2, m1, M.arith, M.mov, M.adv, M.setReg, h2, ofN_add4]
  · simp [m5, m4, m3, m2, m1, M.arith, M.mov, M.adv, M.setReg]
  · simpa [m5, m4, m3, m2, m1, M.arith, M.mov, M.adv, M.setReg] using hw

/-- The loop invariant, by induction on the number `k` of words left. -/
theorem copy_loop (hV : vma + 4 * n ≤ 2 ^ 32) (hL : lma + 4 * n ≤ 2 ^ 32)
    (hd : lma + 4 * n ≤ vma ∨ vma + 4 * n ≤ lma)
    (hval : ∀ i, i < n → x0.mem.valid (ofN (vma + 4 * i)) = true)
    (hsrc : ∀ i, i < n → x0.mem.read? (ofN (lma + 4 * i)) = some (img i)) :
    ∀ k j (m : M), j + k = n → 0 < k → m.pc = 4 →
      m.regs r1 = ofN (lma + 4 * j) → m.regs r2 = ofN (vma + 4 * j) → m.regs r3 = ofN k →
      m.mem.valid = x0.mem.valid →
      (∀ i, i < j → m.mem.read? (ofN (vma + 4 * i)) = some (img i)) → Frame vma n x0 m →
      ∃ m', RSteps (copyCode (ofN lma) (ofN vma) n) m m' ∧ m'.pc = 10 ∧
        m'.mem.valid = x0.mem.valid ∧
        (∀ i, i < n → m'.mem.read? (ofN (vma + 4 * i)) = some (img i)) ∧ Frame vma n x0 m' := by
  intro k
  induction k with
  | zero => intro j m _ hk; omega
  | succ k ih =>
    intro j m hjk _ hpc h1 h2 h3 hv hdone hfr
    have hj : j < n := by omega
    have hread : m.mem.read? (ofN (lma + 4 * j)) = some (img j) := by
      rw [hfr _ (by omega) (by omega)]; exact hsrc j hj
    have hvalid : m.mem.valid (ofN (vma + 4 * j)) = true := by rw [hv]; exact hval j hj
    obtain ⟨m5, hs5, hpc5, h15, h25, h35, hw⟩ := copy_body hV hL hj hpc h1 h2 hread hvalid
    have hk : k + 1 < 2 ^ 32 := by omega
    have h35' : m5.regs r3 = ofN k := by
      rw [h35, h3, add_ofInt_m1 (k + 1) (by omega) hk]; rfl
    have hv5 : m5.mem.valid = x0.mem.valid := by rw [Memory.write?_valid hw, hv]
    have hdone5 : ∀ i, i < j + 1 → m5.mem.read? (ofN (vma + 4 * i)) = some (img i) := by
      intro i hi
      rw [read_write_nat hw (by omega) (by omega)]
      by_cases he : vma + 4 * j = vma + 4 * i
      · rw [if_pos he]; have : i = j := by omega
        subst this; rfl
      · rw [if_neg he]; exact hdone i (by omega)
    have hfr5 : Frame vma n x0 m5 := by
      intro A hA hout
      rw [read_write_nat hw (by omega) hA, if_neg (by omega)]
      exact hfr A hA hout
    let code := copyCode (ofN lma) (ofN vma) n
    by_cases hk0 : k = 0
    · -- last word: `bnez` falls through to index 10
      subst hk0
      let m6 := m5.adv
      have s6 : step code m5 = .next m6 := by
        simp only [code, step, hpc5, copyCode]
        have hz : ofN 0 = 0#32 := rfl
        simp [exec, h35', m6, hz]
      refine ⟨m6, hs5.trans (.single s6), by simp [m6, M.adv, hpc5], by simpa [m6, M.adv] using hv5,
        ?_, ?_⟩
      · intro i hi; simpa [m6, M.adv] using hdone5 i (by omega)
      · intro A hA hout; simpa [m6, M.adv] using hfr5 A hA hout
    · -- more words: `bnez` jumps back to index 4
      let m6 : M := { m5 with pc := 4 }
      have s6 : step code m5 = .next m6 := by
        simp only [code, step, hpc5, copyCode]
        have hne : ¬ ofN k = 0#32 := fun h => hk0 ((ofN_eq_zero (by omega : k < 2 ^ 32)).mp h)
        simp [exec, h35', m6, hne]
      obtain ⟨m', hs', hpc', hv', hall, hfr'⟩ := ih (j + 1) m6 (by omega) (by omega) rfl
        (by simpa [m6] using h15) (by simpa [m6] using h25) (by simpa [m6] using h35')
        (by simpa [m6] using hv5) (by simpa [m6] using hdone5) (fun A hA hout => by simpa [m6] using hfr5 A hA hout)
      exact ⟨m', hs5.trans (.cons s6 hs'), hpc', hv', hall, hfr'⟩

/-- The whole copy loop from index 0: it reaches index 10 with RAM holding the `n` image
words, validity unchanged, and every address outside the RAM area unchanged. -/
theorem copy_run (hV : vma + 4 * n ≤ 2 ^ 32) (hL : lma + 4 * n ≤ 2 ^ 32)
    (hd : lma + 4 * n ≤ vma ∨ vma + 4 * n ≤ lma)
    (hval : ∀ i, i < n → x0.mem.valid (ofN (vma + 4 * i)) = true)
    (hsrc : ∀ i, i < n → x0.mem.read? (ofN (lma + 4 * i)) = some (img i)) (hpc : x0.pc = 0) :
    ∃ m', RSteps (copyCode (ofN lma) (ofN vma) n) x0 m' ∧ m'.pc = 10 ∧
      m'.mem.valid = x0.mem.valid ∧
      (∀ i, i < n → m'.mem.read? (ofN (vma + 4 * i)) = some (img i)) ∧ Frame vma n x0 m' := by
  let code := copyCode (ofN lma) (ofN vma) n
  let m1 := x0.mov r1 (ofN lma)
  let m2 := m1.mov r2 (ofN vma)
  let m3 := m2.mov r3 (BitVec.ofNat 32 n)
  have s1 : step code x0 = .next m1 := by simp only [code, step, hpc, copyCode]; rfl
  have s2 : step code m1 = .next m2 := by
    have : m1.pc = 1 := by simp [m1, M.mov, M.adv, hpc]
    simp only [code, step, this, copyCode]; rfl
  have s3 : step code m2 = .next m3 := by
    have : m2.pc = 2 := by simp [m2, m1, M.mov, M.adv, hpc]
    simp only [code, step, this, copyCode]; rfl
  have hpc3 : m3.pc = 3 := by simp [m3, m2, m1, M.mov, M.adv, hpc]
  have hr3 : m3.regs r3 = ofN n := by simp [m3, M.mov, M.setReg, M.adv]; rfl
  have hmem3 : m3.mem = x0.mem := by simp [m3, m2, m1, M.mov, M.adv, M.setReg]
  have hn : n < 2 ^ 32 := by omega
  by_cases hn0 : n = 0
  · subst hn0
    let m4 : M := { m3 with pc := 10 }
    have s4 : step code m3 = .next m4 := by
      simp only [code, step, hpc3, copyCode]
      have hz : ofN 0 = 0#32 := rfl
      simp [exec, hr3, m4, hz]
    refine ⟨m4, .cons s1 (.cons s2 (.cons s3 (.single s4))), rfl, by simp [m4, hmem3],
      fun i hi => absurd hi (by omega), ?_⟩
    intro A _ _; simp [m4, hmem3]
  · let m4 := m3.adv
    have s4 : step code m3 = .next m4 := by
      simp only [code, step, hpc3, copyCode]
      have hne : ¬ ofN n = 0#32 := fun h => hn0 ((ofN_eq_zero hn).mp h)
      simp [exec, hr3, m4, hne]
    have hpc4 : m4.pc = 4 := by simp [m4, M.adv, hpc3]
    have hm4 : m4.mem = x0.mem := by simp [m4, M.adv, hmem3]
    obtain ⟨m', hs', hpc', hv', hall, hfr'⟩ := copy_loop hV hL hd hval hsrc n 0 m4 (by omega)
      (by omega) hpc4 (by simp [m4, m3, m2, m1, M.adv, M.mov, M.setReg])
      (by simp [m4, m3, m2, m1, M.adv, M.mov, M.setReg]) (by simpa [m4, M.adv] using hr3)
      (by rw [hm4]) (fun i hi => absurd hi (by omega)) (fun A _ _ => by rw [hm4])
    exact ⟨m', .cons s1 (.cons s2 (.cons s3 (.cons s4 hs'))), hpc', hv', hall, hfr'⟩

end Loop

/-! ## From the flash image to the IR outcome -/

/-- What must hold at reset when the image runs from flash: the placement facts of
`Loader.Holds` (`geom`, `valid`), and, instead of RAM already holding the data, that flash holds
the `.data` image word by word at `lma`, that the `.data` area in RAM is addressable, and that
the two do not overlap. `regfile` follows `irmem` in `.data` (`rf_eq`), as `Emit.epilogue` lays
them out. -/
structure FlashHolds (r : Runtime) (ld : Loader) (lma : Nat) (x0 : M) : Prop where
  geom : Geom (cfgOf r ld)
  valid : RegionsValid (cfgOf r ld) x0.mem.valid
  rf_eq : ld.rf = ld.mb + 4 * r.memImage.length
  ram_lt : ld.mb + 4 * dataWords r ≤ 2 ^ 32
  flash_lt : lma + 4 * dataWords r ≤ 2 ^ 32
  disjoint : lma + 4 * dataWords r ≤ ld.mb ∨ ld.mb + 4 * dataWords r ≤ lma
  ram_valid : ∀ i, i < dataWords r → x0.mem.valid (ofN (ld.mb + 4 * i)) = true
  flash : ∀ i, i < dataWords r →
    x0.mem.read? (ofN (lma + 4 * i)) = some (BitVec.ofNat 32 ((dataImage r).getD i 0))

/-- The copy loop establishes `Loader.Holds`: after it, RAM holds the IR memory image and a
zeroed register file. -/
theorem copy_holds {r : Runtime} {ld : Loader} {lma : Nat} {x0 : M} (h : FlashHolds r ld lma x0)
    (hpc : x0.pc = 0) :
    ∃ x1, RSteps (copyCode (ofN lma) (ofN ld.mb) (dataWords r)) x0 x1 ∧ x1.pc = 10 ∧
      ld.Holds r x1 := by
  obtain ⟨x1, hs, hpc1, hv1, hall, _⟩ := copy_run (img := fun i => BitVec.ofNat 32 ((dataImage r).getD i 0))
    h.ram_lt h.flash_lt h.disjoint h.ram_valid h.flash hpc
  have hlen : dataWords r = r.memImage.length + (r.nregs + 3) := by
    simp [dataWords, dataImage]
  refine ⟨x1, hs, hpc1, ⟨h.geom, by rw [hv1]; exact h.valid, ?_, ?_⟩⟩
  · intro k hk
    have e := hall (r.memImage.length + k) (by omega)
    rw [h.rf_eq, show ld.mb + 4 * r.memImage.length + 4 * k = ld.mb + 4 * (r.memImage.length + k)
      by omega, e]
    simp only [dataImage, List.getD_eq_getElem?_getD, List.getElem?_append_right (Nat.le_add_right _ _),
      Nat.add_sub_cancel_left, List.getElem?_replicate, show k < r.nregs + 3 by omega, if_true,
      Option.getD_some]
  · intro a ha
    rw [hall a (by omega)]
    simp [dataImage, List.getD_eq_getElem?_getD, List.getElem?_append_left ha]

/-- **Booting from flash, end to end.** From the reset state, under facts about flash only, the
copy loop runs to its end; from there the prologue runs, and the lowered code reaches the outcome
the IR reaches from `State.init` on the memory image, or exits with `overflow`. -/
theorem boot_correct (r : Runtime) (ld : Loader) (lma : Nat) (p : Prog 32)
    (hlen : 36 * p.length < 2 ^ 32) (hreg : RegsOk (cfgOf r ld) p) {o : Outcome 32}
    (hx : Exec p (State.init (Memory.ofImage r.memImage)) o) {x0 : M}
    (h : FlashHolds r ld lma x0) (hpc : x0.pc = 0) :
    ∃ x1, RSteps (copyCode (ofN lma) (ofN ld.mb) (dataWords r)) x0 x1 ∧ x1.pc = 10 ∧
      rseq (prologueCode r ld) x1 = .next { entryState r ld x1 with pc := x1.pc + 8 } ∧
      (Final (cfgOf r ld) p (lowerProg r.layout p) (entryState r ld x1) o ∨
        RExec (lowerProg r.layout p) (entryState r ld x1) .overflow) := by
  obtain ⟨x1, hs, hpc1, hh⟩ := copy_holds h hpc
  exact ⟨x1, hs, hpc1, binary_correct r ld p hlen hreg hx hh⟩

end Emit
end CM0
end WordDialect
