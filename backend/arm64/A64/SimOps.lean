import A64.SimBin

/-!
# A64.SimOps

Per-instruction simulation theorems. Each states, for an IR instruction `i` whose lowered code
is placed at `base`:
* success: from a related state, the AArch64 model reaches a state related to the IR result;
* trap: when the IR traps with `t`, the AArch64 model exits with `t`.
-/

namespace WordDialect
namespace A64

open Reg

/-- Operand-count trap: any lowering that starts with `uf n` exits with `stackUnderflow`. -/
theorem sim_uf_trap {c : Cfg} {p : Prog 64} {s : State 64} {x : M} {code : List (Instr Nat)}
    {L : Layout} {base n : Nat} {rest : List (Instr Nat)} (hg : Geom c) (hs : Rel0 c p s x)
    (hL : L.dEnd = ofN c.dEnd) (hn : 0 < n) (hn3 : n ≤ 3) (hk : s.dstack.length < n)
    (hpc : x.pc = base) (hat : AAt code base (uf L n base ++ rest)) :
    AExec code x (.trapped .stackUnderflow) :=
  uf_trap hg hs hL hn hn3 hk hpc (aat_append.mp hat).1

macro "mid_tac" : tactic =>
  `(tactic| (intro m a b ha hb
             simp [aseq, exec, M.arith, M.mov, M.setReg, M.adv, ha, hb, MidSpec]))

theorem sim_bin_instr {c : Cfg} {p : Prog 64} {s : State 64} {x : M} {code : List (Instr Nat)}
    {L : Layout} {base : Nat} {off : Nat → Nat} (hg : Geom c) (hL : L.dEnd = ofN c.dEnd)
    (hs : Rel0 c p s x) (hpc : x.pc = base) (i : WordDialect.Instr 64) (mid : List (Instr Nat))
    (rr : Reg) (hrr : rr = x9 ∨ rr = x10 ∨ rr = x11 ∨ rr = x12) (f : W → W → W)
    (hmid : MidSpec mid rr f) (hstr : ∀ j ∈ mid, j.straightA = true)
    (hlow : lowerInstr L base off i = uf L 2 base ++
      ([.load x10 x19 0, .load x9 x19 8] ++ mid ++ [.store x19 8 rr, .addImm x19 8]))
    (hsize : isize i = 4 + (4 + mid.length))
    (hat : AAt code base (lowerInstr L base off i)) {b a : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    ∃ x', ASteps code x x' ∧ Rel0 c p { s with dstack := f a b :: d } x' ∧
      x'.pc = base + isize i := by
  rw [hlow] at hat
  obtain ⟨x', h1, h2, h3⟩ := sim_bin_ok hg hL hs hpc mid rr hrr f hmid hstr hat hd
  exact ⟨x', h1, h2, by rw [h3, hsize]; omega⟩

theorem sim_uf2_trap {c : Cfg} {p : Prog 64} {s : State 64} {x : M} {code : List (Instr Nat)}
    {L : Layout} {base : Nat} {off : Nat → Nat} (hg : Geom c) (hL : L.dEnd = ofN c.dEnd)
    (hs : Rel0 c p s x) (hpc : x.pc = base) (i : WordDialect.Instr 64) (rest : List (Instr Nat))
    (hlow : lowerInstr L base off i = uf L 2 base ++ rest)
    (hat : AAt code base (lowerInstr L base off i)) (hk : s.dstack.length < 2) :
    AExec code x (.trapped .stackUnderflow) := by
  rw [hlow] at hat
  exact sim_uf_trap hg hs hL (by decide) (by decide) hk hpc hat

/-! ### Middle computations -/

theorem midspec_arith (i : Instr Nat) (f : W → W → W)
    (h : ∀ m : M, exec i m = .next (m.arith x9 (f (m.regs x9) (m.regs x10)))) :
    MidSpec [i] x9 f := by
  intro m a b ha hb
  refine ⟨m.arith x9 (f (m.regs x9) (m.regs x10)), by simp [aseq, h], ?_⟩
  simp [M.arith, M.setReg, ha, hb]

theorem midspec_add : MidSpec [.add x9 x10] x9 (· + ·) :=
  midspec_arith _ _ (fun m => by simp [exec])
theorem midspec_sub : MidSpec [.sub x9 x10] x9 (· - ·) :=
  midspec_arith _ _ (fun m => by simp [exec])
theorem midspec_mul : MidSpec [.mul x9 x10] x9 (· * ·) :=
  midspec_arith _ _ (fun m => by simp [exec])
theorem midspec_and : MidSpec [.and x9 x10] x9 (· &&& ·) :=
  midspec_arith _ _ (fun m => by simp [exec])
theorem midspec_or : MidSpec [.or x9 x10] x9 (· ||| ·) :=
  midspec_arith _ _ (fun m => by simp [exec])
theorem midspec_xor : MidSpec [.xor x9 x10] x9 (· ^^^ ·) :=
  midspec_arith _ _ (fun m => by simp [exec])

theorem midspec_shl : MidSpec [.movImm x11 0#64, .shlCl x9, .cmpImm x10 64, .cmov .ae x9 x11]
    x9 Word.shl := by
  intro m a b ha hb
  by_cases h : 64 ≤ BitVec.toNat b
  · have h' : ¬ BitVec.toNat b < 64 := by omega
    simp [aseq, exec, M.arith, M.mov, M.setReg, M.adv, ha, hb, holds_ae, BitVec.ule_eq_decide,
      Word.shl, h, h']
  · have h' : BitVec.toNat b < 64 := by omega
    simp [aseq, exec, M.arith, M.mov, M.setReg, M.adv, ha, hb, holds_ae, BitVec.ule_eq_decide,
      Word.shl, h, h', Nat.mod_eq_of_lt h']

theorem ushiftRight_ge (a : W) (n : Nat) (h : 64 ≤ n) : a >>> n = 0#64 := by
  apply BitVec.eq_of_toNat_eq
  rw [BitVec.toNat_ushiftRight, Nat.shiftRight_eq_div_pow]
  have : a.toNat < 2 ^ n := Nat.lt_of_lt_of_le a.isLt (Nat.pow_le_pow_right (by omega) h)
  simp [Nat.div_eq_of_lt this]

theorem midspec_shr : MidSpec [.movImm x11 0#64, .shrCl x9, .cmpImm x10 64, .cmov .ae x9 x11]
    x9 Word.shr := by
  intro m a b ha hb
  by_cases h : 64 ≤ BitVec.toNat b
  · have h' : ¬ BitVec.toNat b < 64 := by omega
    simp [aseq, exec, M.arith, M.mov, M.setReg, M.adv, ha, hb, holds_ae, BitVec.ule_eq_decide,
      Word.shr, h, h', ushiftRight_ge a _ h]
  · have h' : BitVec.toNat b < 64 := by omega
    simp [aseq, exec, M.arith, M.mov, M.setReg, M.adv, ha, hb, holds_ae, BitVec.ule_eq_decide,
      Word.shr, h, h', Nat.mod_eq_of_lt h']

/-- AArch64 has no rotate-left: `ror` by `-n` is `rol` by `n`. -/
theorem ror_neg (a b : BitVec 64) :
    a.rotateRight ((0#64 - b).toNat % 64) = a.rotateLeft b.toNat := by
  apply BitVec.eq_of_getLsbD_eq
  intro i hi
  rw [BitVec.getLsbD_rotateRight, BitVec.getLsbD_rotateLeft]
  have hb := b.isLt
  have e : (0#64 - b).toNat % 64 % 64 = (64 - b.toNat % 64) % 64 := by
    simp only [BitVec.toNat_sub, BitVec.toNat_ofNat]; omega
  rw [e]
  by_cases h0 : b.toNat % 64 = 0
  · simp only [h0, Nat.sub_zero, Nat.mod_self, Nat.zero_add]
    simp [hi]
  · have e2 : (64 - b.toNat % 64) % 64 = 64 - b.toNat % 64 := Nat.mod_eq_of_lt (by omega)
    rw [e2]
    by_cases h1 : i < b.toNat % 64
    · simp only [show i < 64 - (64 - b.toNat % 64) by omega, h1, ite_true]
      (try congr 1; omega)
    · simp only [show ¬ i < 64 - (64 - b.toNat % 64) by omega, h1, ite_false, hi, decide_true,
        Bool.true_and]
      (try congr 1; omega)

theorem midspec_rotl : MidSpec [.neg x10, .rorCl x9] x9 Word.rotl := by
  intro m a b ha hb
  simp [aseq, exec, M.arith, M.setReg, ha, hb, Word.rotl]
  have hb' := b.isLt
  rw [← BitVec.rotateRight_mod_eq_rotateRight (r := 18446744073709551616 - BitVec.toNat b),
    ← ror_neg]
  congr 1
  simp only [BitVec.toNat_sub, BitVec.toNat_ofNat]
  omega

theorem midspec_rotr : MidSpec [.rorCl x9] x9 Word.rotr := by
  intro m a b ha hb
  simp [aseq, exec, M.arith, M.setReg, ha, hb, Word.rotr, BitVec.rotateRight]

theorem midspec_cmp (cd : WordDialect.Cond) :
    MidSpec [.movImm x11 0#64, .movImm x12 1#64, .cmp x9 x10, .cmov (ccOf cd) x11 x12] x11
      (fun a b => Word.ofBool (cd.eval a b)) := by
  intro m a b ha hb
  cases h : cd.eval a b <;>
    simp [aseq, exec, M.arith, M.mov, M.setReg, M.adv, ha, hb, holds_ccOf, Word.ofBool, h]

/-! ### Instruction theorems -/

section Ops
variable {c : Cfg} {p : Prog 64} {s : State 64} {x : M} {code : List (Instr Nat)} {L : Layout}
  {base : Nat} {off : Nat → Nat}

theorem sim_add_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : AAt code base (lowerInstr L base off .add)) {b a : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    ∃ x', ASteps code x x' ∧ Rel0 c p { s with dstack := (a + b) :: d } x' ∧
      x'.pc = base + isize (.add : WordDialect.Instr 64) :=
  sim_bin_instr hg hL hs hpc .add [.add x9 x10] x9 (by simp) (· + ·) midspec_add
    (by simp [Instr.straightA]) rfl (by simp [isize, ufSize]) hat hd

theorem sim_sub_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : AAt code base (lowerInstr L base off .sub)) {b a : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    ∃ x', ASteps code x x' ∧ Rel0 c p { s with dstack := (a - b) :: d } x' ∧
      x'.pc = base + isize (.sub : WordDialect.Instr 64) :=
  sim_bin_instr hg hL hs hpc .sub [.sub x9 x10] x9 (by simp) (· - ·) midspec_sub
    (by simp [Instr.straightA]) rfl (by simp [isize, ufSize]) hat hd

theorem sim_mul_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : AAt code base (lowerInstr L base off .mul)) {b a : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    ∃ x', ASteps code x x' ∧ Rel0 c p { s with dstack := (a * b) :: d } x' ∧
      x'.pc = base + isize (.mul : WordDialect.Instr 64) :=
  sim_bin_instr hg hL hs hpc .mul [.mul x9 x10] x9 (by simp) (· * ·) midspec_mul
    (by simp [Instr.straightA]) rfl (by simp [isize, ufSize]) hat hd

theorem sim_and_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : AAt code base (lowerInstr L base off .and)) {b a : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    ∃ x', ASteps code x x' ∧ Rel0 c p { s with dstack := (a &&& b) :: d } x' ∧
      x'.pc = base + isize (.and : WordDialect.Instr 64) :=
  sim_bin_instr hg hL hs hpc .and [.and x9 x10] x9 (by simp) (· &&& ·) midspec_and
    (by simp [Instr.straightA]) rfl (by simp [isize, ufSize]) hat hd

theorem sim_or_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : AAt code base (lowerInstr L base off .or)) {b a : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    ∃ x', ASteps code x x' ∧ Rel0 c p { s with dstack := (a ||| b) :: d } x' ∧
      x'.pc = base + isize (.or : WordDialect.Instr 64) :=
  sim_bin_instr hg hL hs hpc .or [.or x9 x10] x9 (by simp) (· ||| ·) midspec_or
    (by simp [Instr.straightA]) rfl (by simp [isize, ufSize]) hat hd

theorem sim_xor_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : AAt code base (lowerInstr L base off .xor)) {b a : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    ∃ x', ASteps code x x' ∧ Rel0 c p { s with dstack := (a ^^^ b) :: d } x' ∧
      x'.pc = base + isize (.xor : WordDialect.Instr 64) :=
  sim_bin_instr hg hL hs hpc .xor [.xor x9 x10] x9 (by simp) (· ^^^ ·) midspec_xor
    (by simp [Instr.straightA]) rfl (by simp [isize, ufSize]) hat hd

theorem sim_shl_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : AAt code base (lowerInstr L base off .shl)) {b a : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    ∃ x', ASteps code x x' ∧ Rel0 c p { s with dstack := Word.shl a b :: d } x' ∧
      x'.pc = base + isize (.shl : WordDialect.Instr 64) :=
  sim_bin_instr hg hL hs hpc .shl _ x9 (by simp) Word.shl midspec_shl
    (by simp [Instr.straightA]) rfl (by simp [isize, ufSize]) hat hd

theorem sim_shr_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : AAt code base (lowerInstr L base off .shr)) {b a : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    ∃ x', ASteps code x x' ∧ Rel0 c p { s with dstack := Word.shr a b :: d } x' ∧
      x'.pc = base + isize (.shr : WordDialect.Instr 64) :=
  sim_bin_instr hg hL hs hpc .shr _ x9 (by simp) Word.shr midspec_shr
    (by simp [Instr.straightA]) rfl (by simp [isize, ufSize]) hat hd

theorem sim_rotl_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : AAt code base (lowerInstr L base off .rotl)) {b a : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    ∃ x', ASteps code x x' ∧ Rel0 c p { s with dstack := Word.rotl a b :: d } x' ∧
      x'.pc = base + isize (.rotl : WordDialect.Instr 64) :=
  sim_bin_instr hg hL hs hpc .rotl _ x9 (by simp) Word.rotl midspec_rotl
    (by simp [Instr.straightA]) rfl (by simp [isize, ufSize]) hat hd

theorem sim_rotr_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : AAt code base (lowerInstr L base off .rotr)) {b a : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    ∃ x', ASteps code x x' ∧ Rel0 c p { s with dstack := Word.rotr a b :: d } x' ∧
      x'.pc = base + isize (.rotr : WordDialect.Instr 64) :=
  sim_bin_instr hg hL hs hpc .rotr _ x9 (by simp) Word.rotr midspec_rotr
    (by simp [Instr.straightA]) rfl (by simp [isize, ufSize]) hat hd

theorem sim_cmp_ok (cd : WordDialect.Cond) (hg : Geom c) (hL : L.dEnd = ofN c.dEnd)
    (hs : Rel0 c p s x) (hpc : x.pc = base) (hat : AAt code base (lowerInstr L base off (.cmp cd)))
    {b a : W} {d : List W} (hd : s.dstack = b :: a :: d) :
    ∃ x', ASteps code x x' ∧
      Rel0 c p { s with dstack := Word.ofBool (cd.eval a b) :: d } x' ∧
      x'.pc = base + isize (.cmp cd : WordDialect.Instr 64) :=
  sim_bin_instr hg hL hs hpc (.cmp cd) _ x11 (by simp) (fun a b => Word.ofBool (cd.eval a b))
    (midspec_cmp cd) (by simp [Instr.straightA]) rfl (by simp [isize, ufSize]) hat hd

end Ops

end A64
end WordDialect
