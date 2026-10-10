import CM0.SimBin

/-!
# CM0.SimOps

Per-instruction simulation theorems. Each states, for an IR instruction `i` whose lowered code
is placed at `base`:
* success: from a related state, the ARMv6-M model reaches a state related to the IR result;
* trap: when the IR traps with `t`, the ARMv6-M model exits with `t`.
-/

namespace WordDialect
namespace CM0

open Reg

/-- Operand-count trap: any lowering that starts with `uf n` exits with `stackUnderflow`. -/
theorem sim_uf_trap {c : Cfg} {p : Prog 32} {s : State 32} {x : M} {code : List (Instr Nat)}
    {L : Layout} {base n : Nat} {rest : List (Instr Nat)} (hg : Geom c) (hs : Rel0 c p s x)
    (hL : L.dEnd = ofN c.dEnd) (hn : 0 < n) (hn3 : n ≤ 3) (hk : s.dstack.length < n)
    (hpc : x.pc = base) (hat : RAt code base (uf L n base ++ rest)) :
    RExec code x (.trapped .stackUnderflow) :=
  uf_trap hg hs hL hn hn3 hk hpc (rat_append.mp hat).1

macro "mid_tac" : tactic =>
  `(tactic| (intro m a b ha hb
             simp [rseq, exec, M.arith, M.mov, M.setReg, M.adv, ha, hb, MidSpec]))

theorem sim_bin_instr {c : Cfg} {p : Prog 32} {s : State 32} {x : M} {code : List (Instr Nat)}
    {L : Layout} {base : Nat} {off : Nat → Nat} (hg : Geom c) (hL : L.dEnd = ofN c.dEnd)
    (hs : Rel0 c p s x) (hpc : x.pc = base) (i : WordDialect.Instr 32) (mid : List (Instr Nat))
    (rr : Reg) (hrr : rr = r0 ∨ rr = r1 ∨ rr = r2 ∨ rr = r3) (f : W → W → W)
    (hmid : MidSpec mid rr f) (hstr : ∀ j ∈ mid, j.straightR = true)
    (hlow : lowerInstr L base off i = uf L 2 base ++
      ([.load r1 r4 0, .load r0 r4 4] ++ mid ++ [.store r4 4 rr, .addImm r4 4]))
    (hsize : isize i = 3 + (4 + mid.length))
    (hat : RAt code base (lowerInstr L base off i)) {b a : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    ∃ x', RSteps code x x' ∧ Rel0 c p { s with dstack := f a b :: d } x' ∧
      x'.pc = base + isize i := by
  rw [hlow] at hat
  obtain ⟨x', h1, h2, h3⟩ := sim_bin_ok hg hL hs hpc mid rr hrr f hmid hstr hat hd
  exact ⟨x', h1, h2, by rw [h3, hsize]; omega⟩

theorem sim_uf2_trap {c : Cfg} {p : Prog 32} {s : State 32} {x : M} {code : List (Instr Nat)}
    {L : Layout} {base : Nat} {off : Nat → Nat} (hg : Geom c) (hL : L.dEnd = ofN c.dEnd)
    (hs : Rel0 c p s x) (hpc : x.pc = base) (i : WordDialect.Instr 32) (rest : List (Instr Nat))
    (hlow : lowerInstr L base off i = uf L 2 base ++ rest)
    (hat : RAt code base (lowerInstr L base off i)) (hk : s.dstack.length < 2) :
    RExec code x (.trapped .stackUnderflow) := by
  rw [hlow] at hat
  exact sim_uf_trap hg hs hL (by decide) (by decide) hk hpc hat

/-! ### Middle computations -/

theorem midspec_arith (i : Instr Nat) (f : W → W → W)
    (h : ∀ m : M, exec i m = .next (m.arith r0 (f (m.regs r0) (m.regs r1)))) :
    MidSpec [i] r0 f := by
  intro m a b ha hb
  refine ⟨m.arith r0 (f (m.regs r0) (m.regs r1)), by simp [rseq, h], ?_⟩
  simp [M.arith, M.setReg, ha, hb]

theorem midspec_add : MidSpec [.add r0 r1] r0 (· + ·) :=
  midspec_arith _ _ (fun m => by simp [exec])
theorem midspec_sub : MidSpec [.sub r0 r1] r0 (· - ·) :=
  midspec_arith _ _ (fun m => by simp [exec])
theorem midspec_mul : MidSpec [.mul r0 r1] r0 (· * ·) :=
  midspec_arith _ _ (fun m => by simp [exec])
theorem midspec_and : MidSpec [.and r0 r1] r0 (· &&& ·) :=
  midspec_arith _ _ (fun m => by simp [exec])
theorem midspec_or : MidSpec [.or r0 r1] r0 (· ||| ·) :=
  midspec_arith _ _ (fun m => by simp [exec])
theorem midspec_xor : MidSpec [.xor r0 r1] r0 (· ^^^ ·) :=
  midspec_arith _ _ (fun m => by simp [exec])

/-- The mask `0 - (b <u 32)` (all ones or zero) gives the IR's zero result for amounts of 32 or
more. (A register shift alone is not enough: it uses the bottom byte of the amount, so an amount
of 256 would shift by 0.) -/
theorem mask_lt (b : W) :
    0#32 - Word.ofBool (b.ult (BitVec.ofNat 32 32)) =
      if b.toNat < 32 then BitVec.allOnes 32 else 0#32 := by
  by_cases h : b.toNat < 32
  · have : b.ult (BitVec.ofNat 32 32) = true := by simp [BitVec.ult, h]
    rw [this, if_pos h]; simp [Word.ofBool, BitVec.neg_one_eq_allOnes]
  · have : b.ult (BitVec.ofNat 32 32) = false := by simp [BitVec.ult]; omega
    rw [this, if_neg h]; simp [Word.ofBool]

theorem midspec_shl : MidSpec [.lsl r0 r1, .sltiu r2 r1 32, .neg r2, .and r0 r2] r0 Word.shl := by
  intro m a b ha hb
  simp only [rseq, exec, M.arith, M.setReg]
  refine ⟨_, rfl, ?_, rfl, ?_⟩
  · simp only [ite_true, show (r2 = r0) = False by decide,
      show (r1 = r0) = False by decide, show (r0 = r2) = False by decide, ite_false, ha, hb]
    rw [mask_lt b, Word.shl]
    by_cases h : b.toNat < 32
    · rw [if_pos h, if_pos h, BitVec.and_allOnes, Nat.mod_eq_of_lt (by omega : b.toNat < 256)]
    · rw [if_neg h, if_neg h, BitVec.and_zero]
  · simp

theorem ushiftRight_ge (a : W) (n : Nat) (h : 32 ≤ n) : a >>> n = 0#32 := by
  apply BitVec.eq_of_toNat_eq
  rw [BitVec.toNat_ushiftRight, Nat.shiftRight_eq_div_pow]
  have : a.toNat < 2 ^ n := Nat.lt_of_lt_of_le a.isLt (Nat.pow_le_pow_right (by omega) h)
  simp [Nat.div_eq_of_lt this]

theorem midspec_shr : MidSpec [.lsr r0 r1, .sltiu r2 r1 32, .neg r2, .and r0 r2] r0 Word.shr := by
  intro m a b ha hb
  simp only [rseq, exec, M.arith, M.setReg]
  refine ⟨_, rfl, ?_, rfl, ?_⟩
  · simp only [ite_true, show (r2 = r0) = False by decide,
      show (r1 = r0) = False by decide, show (r0 = r2) = False by decide, ite_false, ha, hb]
    rw [mask_lt b, Word.shr]
    by_cases h : b.toNat < 32
    · rw [if_pos h, BitVec.and_allOnes, Nat.mod_eq_of_lt (by omega : b.toNat < 256)]
    · rw [if_neg h, BitVec.and_zero, ushiftRight_ge a _ (by omega : 32 ≤ b.toNat)]
  · simp

theorem shiftLeft_32 (a : W) : a <<< 32 = 0#32 := by
  apply BitVec.eq_of_toNat_eq; simp [BitVec.toNat_shiftLeft, Nat.shiftLeft_eq]

/-- `ror` by a register rotates by the bottom byte of the amount, which is the IR's rotation by
the whole amount, since both reduce it modulo 32. -/
theorem ror_reg (a b : W) : a.rotateRight (b.toNat % 256) = a.rotateRight b.toNat := by
  rw [BitVec.rotateRight_def, BitVec.rotateRight_def,
    show b.toNat % 256 % 32 = b.toNat % 32 by omega]

/-- ARMv6-M has no rotate-left: `rotl` by `b` is `ror` by `-b`. -/
theorem ror_neg (a b : W) : a.rotateRight ((0#32 - b).toNat % 256) = a.rotateLeft b.toNat := by
  have hb := b.isLt
  rw [BitVec.rotateRight_def, BitVec.rotateLeft_def, BitVec.toNat_sub]
  simp only [BitVec.toNat_ofNat, Nat.zero_mod, Nat.add_zero]
  by_cases h0 : b.toNat % 32 = 0
  · rw [h0, show (2 ^ 32 - b.toNat) % 2 ^ 32 % 256 % 32 = 0 by omega, Nat.sub_zero,
      shiftLeft_32, ushiftRight_ge a 32 (by omega), BitVec.shiftLeft_zero, BitVec.ushiftRight_zero,
      BitVec.or_zero]
  · rw [show (2 ^ 32 - b.toNat) % 2 ^ 32 % 256 % 32 = 32 - b.toNat % 32 by omega,
      show 32 - (32 - b.toNat % 32) = b.toNat % 32 by omega, BitVec.or_comm]

theorem midspec_rotl : MidSpec [.neg r1, .ror r0 r1] r0 Word.rotl := by
  intro m a b ha hb
  simp only [rseq, exec, M.arith, M.setReg]
  refine ⟨_, rfl, ?_, rfl, ?_⟩
  · simp only [ite_true, show (r0 = r1) = False by decide, ite_false, ha, hb, Word.rotl]
    exact ror_neg a b
  · simp

theorem midspec_rotr : MidSpec [.ror r0 r1] r0 Word.rotr := by
  intro m a b ha hb
  simp only [rseq, exec, M.arith, M.setReg]
  refine ⟨_, rfl, ?_, rfl, ?_⟩
  · simp [ha, hb, Word.rotr, ror_reg]
  · simp

/-! ### Instruction theorems -/

section Ops
variable {c : Cfg} {p : Prog 32} {s : State 32} {x : M} {code : List (Instr Nat)} {L : Layout}
  {base : Nat} {off : Nat → Nat}

theorem sim_add_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : RAt code base (lowerInstr L base off .add)) {b a : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    ∃ x', RSteps code x x' ∧ Rel0 c p { s with dstack := (a + b) :: d } x' ∧
      x'.pc = base + isize (.add : WordDialect.Instr 32) :=
  sim_bin_instr hg hL hs hpc .add [.add r0 r1] r0 (by simp) (· + ·) midspec_add
    (by simp [Instr.straightR]) rfl (by simp [isize, ufSize]) hat hd

theorem sim_sub_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : RAt code base (lowerInstr L base off .sub)) {b a : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    ∃ x', RSteps code x x' ∧ Rel0 c p { s with dstack := (a - b) :: d } x' ∧
      x'.pc = base + isize (.sub : WordDialect.Instr 32) :=
  sim_bin_instr hg hL hs hpc .sub [.sub r0 r1] r0 (by simp) (· - ·) midspec_sub
    (by simp [Instr.straightR]) rfl (by simp [isize, ufSize]) hat hd

theorem sim_mul_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : RAt code base (lowerInstr L base off .mul)) {b a : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    ∃ x', RSteps code x x' ∧ Rel0 c p { s with dstack := (a * b) :: d } x' ∧
      x'.pc = base + isize (.mul : WordDialect.Instr 32) :=
  sim_bin_instr hg hL hs hpc .mul [.mul r0 r1] r0 (by simp) (· * ·) midspec_mul
    (by simp [Instr.straightR]) rfl (by simp [isize, ufSize]) hat hd

theorem sim_and_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : RAt code base (lowerInstr L base off .and)) {b a : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    ∃ x', RSteps code x x' ∧ Rel0 c p { s with dstack := (a &&& b) :: d } x' ∧
      x'.pc = base + isize (.and : WordDialect.Instr 32) :=
  sim_bin_instr hg hL hs hpc .and [.and r0 r1] r0 (by simp) (· &&& ·) midspec_and
    (by simp [Instr.straightR]) rfl (by simp [isize, ufSize]) hat hd

theorem sim_or_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : RAt code base (lowerInstr L base off .or)) {b a : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    ∃ x', RSteps code x x' ∧ Rel0 c p { s with dstack := (a ||| b) :: d } x' ∧
      x'.pc = base + isize (.or : WordDialect.Instr 32) :=
  sim_bin_instr hg hL hs hpc .or [.or r0 r1] r0 (by simp) (· ||| ·) midspec_or
    (by simp [Instr.straightR]) rfl (by simp [isize, ufSize]) hat hd

theorem sim_xor_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : RAt code base (lowerInstr L base off .xor)) {b a : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    ∃ x', RSteps code x x' ∧ Rel0 c p { s with dstack := (a ^^^ b) :: d } x' ∧
      x'.pc = base + isize (.xor : WordDialect.Instr 32) :=
  sim_bin_instr hg hL hs hpc .xor [.xor r0 r1] r0 (by simp) (· ^^^ ·) midspec_xor
    (by simp [Instr.straightR]) rfl (by simp [isize, ufSize]) hat hd

theorem sim_shl_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : RAt code base (lowerInstr L base off .shl)) {b a : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    ∃ x', RSteps code x x' ∧ Rel0 c p { s with dstack := Word.shl a b :: d } x' ∧
      x'.pc = base + isize (.shl : WordDialect.Instr 32) :=
  sim_bin_instr hg hL hs hpc .shl _ r0 (by simp) Word.shl midspec_shl
    (by simp [Instr.straightR]) rfl (by simp [isize, ufSize]) hat hd

theorem sim_shr_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : RAt code base (lowerInstr L base off .shr)) {b a : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    ∃ x', RSteps code x x' ∧ Rel0 c p { s with dstack := Word.shr a b :: d } x' ∧
      x'.pc = base + isize (.shr : WordDialect.Instr 32) :=
  sim_bin_instr hg hL hs hpc .shr _ r0 (by simp) Word.shr midspec_shr
    (by simp [Instr.straightR]) rfl (by simp [isize, ufSize]) hat hd

theorem sim_rotl_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : RAt code base (lowerInstr L base off .rotl)) {b a : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    ∃ x', RSteps code x x' ∧ Rel0 c p { s with dstack := Word.rotl a b :: d } x' ∧
      x'.pc = base + isize (.rotl : WordDialect.Instr 32) :=
  sim_bin_instr hg hL hs hpc .rotl _ r0 (by simp) Word.rotl midspec_rotl
    (by simp [Instr.straightR]) rfl (by simp [isize, ufSize]) hat hd

theorem sim_rotr_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : RAt code base (lowerInstr L base off .rotr)) {b a : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    ∃ x', RSteps code x x' ∧ Rel0 c p { s with dstack := Word.rotr a b :: d } x' ∧
      x'.pc = base + isize (.rotr : WordDialect.Instr 32) :=
  sim_bin_instr hg hL hs hpc .rotr _ r0 (by simp) Word.rotr midspec_rotr
    (by simp [Instr.straightR]) rfl (by simp [isize, ufSize]) hat hd

end Ops

end CM0
end WordDialect
