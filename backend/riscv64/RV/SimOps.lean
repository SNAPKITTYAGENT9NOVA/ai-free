import RV.SimBin

/-!
# RV.SimOps

Per-instruction simulation theorems. Each states, for an IR instruction `i` whose lowered code
is placed at `base`:
* success: from a related state, the RISC-V model reaches a state related to the IR result;
* trap: when the IR traps with `t`, the RISC-V model exits with `t`.
-/

namespace WordDialect
namespace RV

open Reg

/-- Operand-count trap: any lowering that starts with `uf n` exits with `stackUnderflow`. -/
theorem sim_uf_trap {c : Cfg} {p : Prog 64} {s : State 64} {x : M} {code : List (Instr Nat)}
    {L : Layout} {base n : Nat} {rest : List (Instr Nat)} (hg : Geom c) (hs : Rel0 c p s x)
    (hL : L.dEnd = ofN c.dEnd) (hn : 0 < n) (hn3 : n ≤ 3) (hk : s.dstack.length < n)
    (hpc : x.pc = base) (hat : RAt code base (uf L n base ++ rest)) :
    RExec code x (.trapped .stackUnderflow) :=
  uf_trap hg hs hL hn hn3 hk hpc (rat_append.mp hat).1

macro "mid_tac" : tactic =>
  `(tactic| (intro m a b ha hb
             simp [rseq, exec, M.arith, M.mov, M.setReg, M.adv, ha, hb, MidSpec]))

theorem sim_bin_instr {c : Cfg} {p : Prog 64} {s : State 64} {x : M} {code : List (Instr Nat)}
    {L : Layout} {base : Nat} {off : Nat → Nat} (hg : Geom c) (hL : L.dEnd = ofN c.dEnd)
    (hs : Rel0 c p s x) (hpc : x.pc = base) (i : WordDialect.Instr 64) (mid : List (Instr Nat))
    (rr : Reg) (hrr : rr = t0 ∨ rr = t1 ∨ rr = t2 ∨ rr = t3) (f : W → W → W)
    (hmid : MidSpec mid rr f) (hstr : ∀ j ∈ mid, j.straightR = true)
    (hlow : lowerInstr L base off i = uf L 2 base ++
      ([.load t1 s1 0, .load t0 s1 8] ++ mid ++ [.store s1 8 rr, .addImm s1 8]))
    (hsize : isize i = 3 + (4 + mid.length))
    (hat : RAt code base (lowerInstr L base off i)) {b a : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    ∃ x', RSteps code x x' ∧ Rel0 c p { s with dstack := f a b :: d } x' ∧
      x'.pc = base + isize i := by
  rw [hlow] at hat
  obtain ⟨x', h1, h2, h3⟩ := sim_bin_ok hg hL hs hpc mid rr hrr f hmid hstr hat hd
  exact ⟨x', h1, h2, by rw [h3, hsize]; omega⟩

theorem sim_uf2_trap {c : Cfg} {p : Prog 64} {s : State 64} {x : M} {code : List (Instr Nat)}
    {L : Layout} {base : Nat} {off : Nat → Nat} (hg : Geom c) (hL : L.dEnd = ofN c.dEnd)
    (hs : Rel0 c p s x) (hpc : x.pc = base) (i : WordDialect.Instr 64) (rest : List (Instr Nat))
    (hlow : lowerInstr L base off i = uf L 2 base ++ rest)
    (hat : RAt code base (lowerInstr L base off i)) (hk : s.dstack.length < 2) :
    RExec code x (.trapped .stackUnderflow) := by
  rw [hlow] at hat
  exact sim_uf_trap hg hs hL (by decide) (by decide) hk hpc hat

/-! ### Middle computations -/

theorem midspec_arith (i : Instr Nat) (f : W → W → W)
    (h : ∀ m : M, exec i m = .next (m.arith t0 (f (m.regs t0) (m.regs t1)))) :
    MidSpec [i] t0 f := by
  intro m a b ha hb
  refine ⟨m.arith t0 (f (m.regs t0) (m.regs t1)), by simp [rseq, h], ?_⟩
  simp [M.arith, M.setReg, ha, hb]

theorem midspec_add : MidSpec [.add t0 t1] t0 (· + ·) :=
  midspec_arith _ _ (fun m => by simp [exec])
theorem midspec_sub : MidSpec [.sub t0 t1] t0 (· - ·) :=
  midspec_arith _ _ (fun m => by simp [exec])
theorem midspec_mul : MidSpec [.mul t0 t1] t0 (· * ·) :=
  midspec_arith _ _ (fun m => by simp [exec])
theorem midspec_and : MidSpec [.and t0 t1] t0 (· &&& ·) :=
  midspec_arith _ _ (fun m => by simp [exec])
theorem midspec_or : MidSpec [.or t0 t1] t0 (· ||| ·) :=
  midspec_arith _ _ (fun m => by simp [exec])
theorem midspec_xor : MidSpec [.xor t0 t1] t0 (· ^^^ ·) :=
  midspec_arith _ _ (fun m => by simp [exec])

/-- `sll`/`srl` use the amount modulo 64; the mask `0 - (b <u 64)` (all ones or zero) gives
the IR's zero result for amounts of 64 or more. -/
theorem mask_lt (b : W) :
    0#64 - Word.ofBool (b.ult (BitVec.ofNat 64 64)) =
      if b.toNat < 64 then BitVec.allOnes 64 else 0#64 := by
  by_cases h : b.toNat < 64
  · have : b.ult (BitVec.ofNat 64 64) = true := by simp [BitVec.ult, h]
    rw [this, if_pos h]; simp [Word.ofBool, BitVec.neg_one_eq_allOnes]
  · have : b.ult (BitVec.ofNat 64 64) = false := by simp [BitVec.ult]; omega
    rw [this, if_neg h]; simp [Word.ofBool]

theorem midspec_shl : MidSpec [.sll t0 t1, .sltiu t2 t1 64, .neg t2, .and t0 t2] t0 Word.shl := by
  intro m a b ha hb
  simp only [rseq, exec, M.arith, M.setReg]
  refine ⟨_, rfl, ?_, rfl, ?_⟩
  · simp only [ite_true, show (t2 = t0) = False by decide,
      show (t1 = t0) = False by decide, show (t0 = t2) = False by decide, ite_false, ha, hb]
    rw [mask_lt b, Word.shl]
    by_cases h : b.toNat < 64
    · rw [if_pos h, if_pos h, BitVec.and_allOnes, Nat.mod_eq_of_lt h]
    · rw [if_neg h, if_neg h, BitVec.and_zero]
  · simp

theorem ushiftRight_ge (a : W) (n : Nat) (h : 64 ≤ n) : a >>> n = 0#64 := by
  apply BitVec.eq_of_toNat_eq
  rw [BitVec.toNat_ushiftRight, Nat.shiftRight_eq_div_pow]
  have : a.toNat < 2 ^ n := Nat.lt_of_lt_of_le a.isLt (Nat.pow_le_pow_right (by omega) h)
  simp [Nat.div_eq_of_lt this]

theorem midspec_shr : MidSpec [.srl t0 t1, .sltiu t2 t1 64, .neg t2, .and t0 t2] t0 Word.shr := by
  intro m a b ha hb
  simp only [rseq, exec, M.arith, M.setReg]
  refine ⟨_, rfl, ?_, rfl, ?_⟩
  · simp only [ite_true, show (t2 = t0) = False by decide,
      show (t1 = t0) = False by decide, show (t0 = t2) = False by decide, ite_false, ha, hb]
    rw [mask_lt b, Word.shr]
    by_cases h : b.toNat < 64
    · rw [if_pos h, BitVec.and_allOnes, Nat.mod_eq_of_lt h]
    · rw [if_neg h, BitVec.and_zero, ushiftRight_ge a _ (by omega : 64 ≤ b.toNat)]
  · simp

/-- Base RV64 has no rotate: `rotl` is two shifts and an `or` (the second shift amount is
`-b` modulo 64, as `neg` then `srl` computes it). -/
theorem rotl_shifts (a b : W) :
    (a <<< (b.toNat % 64)) ||| (a >>> ((18446744073709551616 - b.toNat) % 64)) =
      a.rotateLeft b.toNat := by
  have hb := b.isLt
  rw [BitVec.rotateLeft_def]
  by_cases h0 : b.toNat % 64 = 0
  · rw [h0, show (18446744073709551616 - b.toNat) % 64 = 0 by omega, Nat.sub_zero,
      ushiftRight_ge a 64 (by omega), BitVec.shiftLeft_zero, BitVec.ushiftRight_zero, BitVec.or_self,
      BitVec.or_zero]
  · rw [show (18446744073709551616 - b.toNat) % 64 = 64 - b.toNat % 64 by omega]

theorem midspec_rotl :
    MidSpec [.movRR t2 t0, .sll t0 t1, .neg t1, .srl t2 t1, .or t0 t2] t0 Word.rotl := by
  intro m a b ha hb
  simp only [rseq, exec, M.arith, M.mov, M.adv, M.setReg]
  refine ⟨_, rfl, ?_, rfl, ?_⟩
  · simp [ha, hb, Word.rotl, rotl_shifts]
  · simp

/-- `rotr` likewise: `srl` by `n`, `sll` by `-n`. -/
theorem rotr_shifts (a b : W) :
    (a >>> (b.toNat % 64)) ||| (a <<< ((18446744073709551616 - b.toNat) % 64)) =
      a.rotateRight b.toNat := by
  have hb := b.isLt
  rw [BitVec.rotateRight_def]
  by_cases h0 : b.toNat % 64 = 0
  · rw [h0, show (18446744073709551616 - b.toNat) % 64 = 0 by omega, Nat.sub_zero]
    have h64 : a <<< 64 = 0#64 := by
      apply BitVec.eq_of_toNat_eq; simp [BitVec.toNat_shiftLeft, Nat.shiftLeft_eq]
    rw [h64, BitVec.shiftLeft_zero, BitVec.ushiftRight_zero, BitVec.or_zero, BitVec.or_self]
  · rw [show (18446744073709551616 - b.toNat) % 64 = 64 - b.toNat % 64 by omega]

theorem midspec_rotr :
    MidSpec [.movRR t2 t0, .srl t0 t1, .neg t1, .sll t2 t1, .or t0 t2] t0 Word.rotr := by
  intro m a b ha hb
  simp only [rseq, exec, M.arith, M.mov, M.adv, M.setReg]
  refine ⟨_, rfl, ?_, rfl, ?_⟩
  · simp [ha, hb, Word.rotr, rotr_shifts]
  · simp

/-! ### Instruction theorems -/

section Ops
variable {c : Cfg} {p : Prog 64} {s : State 64} {x : M} {code : List (Instr Nat)} {L : Layout}
  {base : Nat} {off : Nat → Nat}

theorem sim_add_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : RAt code base (lowerInstr L base off .add)) {b a : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    ∃ x', RSteps code x x' ∧ Rel0 c p { s with dstack := (a + b) :: d } x' ∧
      x'.pc = base + isize (.add : WordDialect.Instr 64) :=
  sim_bin_instr hg hL hs hpc .add [.add t0 t1] t0 (by simp) (· + ·) midspec_add
    (by simp [Instr.straightR]) rfl (by simp [isize, ufSize]) hat hd

theorem sim_sub_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : RAt code base (lowerInstr L base off .sub)) {b a : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    ∃ x', RSteps code x x' ∧ Rel0 c p { s with dstack := (a - b) :: d } x' ∧
      x'.pc = base + isize (.sub : WordDialect.Instr 64) :=
  sim_bin_instr hg hL hs hpc .sub [.sub t0 t1] t0 (by simp) (· - ·) midspec_sub
    (by simp [Instr.straightR]) rfl (by simp [isize, ufSize]) hat hd

theorem sim_mul_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : RAt code base (lowerInstr L base off .mul)) {b a : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    ∃ x', RSteps code x x' ∧ Rel0 c p { s with dstack := (a * b) :: d } x' ∧
      x'.pc = base + isize (.mul : WordDialect.Instr 64) :=
  sim_bin_instr hg hL hs hpc .mul [.mul t0 t1] t0 (by simp) (· * ·) midspec_mul
    (by simp [Instr.straightR]) rfl (by simp [isize, ufSize]) hat hd

theorem sim_and_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : RAt code base (lowerInstr L base off .and)) {b a : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    ∃ x', RSteps code x x' ∧ Rel0 c p { s with dstack := (a &&& b) :: d } x' ∧
      x'.pc = base + isize (.and : WordDialect.Instr 64) :=
  sim_bin_instr hg hL hs hpc .and [.and t0 t1] t0 (by simp) (· &&& ·) midspec_and
    (by simp [Instr.straightR]) rfl (by simp [isize, ufSize]) hat hd

theorem sim_or_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : RAt code base (lowerInstr L base off .or)) {b a : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    ∃ x', RSteps code x x' ∧ Rel0 c p { s with dstack := (a ||| b) :: d } x' ∧
      x'.pc = base + isize (.or : WordDialect.Instr 64) :=
  sim_bin_instr hg hL hs hpc .or [.or t0 t1] t0 (by simp) (· ||| ·) midspec_or
    (by simp [Instr.straightR]) rfl (by simp [isize, ufSize]) hat hd

theorem sim_xor_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : RAt code base (lowerInstr L base off .xor)) {b a : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    ∃ x', RSteps code x x' ∧ Rel0 c p { s with dstack := (a ^^^ b) :: d } x' ∧
      x'.pc = base + isize (.xor : WordDialect.Instr 64) :=
  sim_bin_instr hg hL hs hpc .xor [.xor t0 t1] t0 (by simp) (· ^^^ ·) midspec_xor
    (by simp [Instr.straightR]) rfl (by simp [isize, ufSize]) hat hd

theorem sim_shl_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : RAt code base (lowerInstr L base off .shl)) {b a : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    ∃ x', RSteps code x x' ∧ Rel0 c p { s with dstack := Word.shl a b :: d } x' ∧
      x'.pc = base + isize (.shl : WordDialect.Instr 64) :=
  sim_bin_instr hg hL hs hpc .shl _ t0 (by simp) Word.shl midspec_shl
    (by simp [Instr.straightR]) rfl (by simp [isize, ufSize]) hat hd

theorem sim_shr_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : RAt code base (lowerInstr L base off .shr)) {b a : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    ∃ x', RSteps code x x' ∧ Rel0 c p { s with dstack := Word.shr a b :: d } x' ∧
      x'.pc = base + isize (.shr : WordDialect.Instr 64) :=
  sim_bin_instr hg hL hs hpc .shr _ t0 (by simp) Word.shr midspec_shr
    (by simp [Instr.straightR]) rfl (by simp [isize, ufSize]) hat hd

theorem sim_rotl_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : RAt code base (lowerInstr L base off .rotl)) {b a : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    ∃ x', RSteps code x x' ∧ Rel0 c p { s with dstack := Word.rotl a b :: d } x' ∧
      x'.pc = base + isize (.rotl : WordDialect.Instr 64) :=
  sim_bin_instr hg hL hs hpc .rotl _ t0 (by simp) Word.rotl midspec_rotl
    (by simp [Instr.straightR]) rfl (by simp [isize, ufSize]) hat hd

theorem sim_rotr_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : RAt code base (lowerInstr L base off .rotr)) {b a : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    ∃ x', RSteps code x x' ∧ Rel0 c p { s with dstack := Word.rotr a b :: d } x' ∧
      x'.pc = base + isize (.rotr : WordDialect.Instr 64) :=
  sim_bin_instr hg hL hs hpc .rotr _ t0 (by simp) Word.rotr midspec_rotr
    (by simp [Instr.straightR]) rfl (by simp [isize, ufSize]) hat hd

end Ops

end RV
end WordDialect
