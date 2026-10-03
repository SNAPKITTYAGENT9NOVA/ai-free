import X86.SimBin

/-!
# X86.SimOps

Per-instruction simulation theorems. Each states, for an IR instruction `i` whose lowered code
is placed at `base`:
* success: from a related state, the x86 model reaches a state related to the IR result;
* trap: when the IR traps with `t`, the x86 model exits with `t`.
-/

namespace WordDialect
namespace X86

open Reg

/-- Operand-count trap: any lowering that starts with `uf n` exits with `stackUnderflow`. -/
theorem sim_uf_trap {c : Cfg} {p : Prog 64} {s : State 64} {x : M} {code : List (Instr Nat)}
    {L : Layout} {base n : Nat} {rest : List (Instr Nat)} (hg : Geom c) (hs : Rel0 c p s x)
    (hL : L.dEnd = ofN c.dEnd) (hn : 0 < n) (hn3 : n ≤ 3) (hk : s.dstack.length < n)
    (hpc : x.pc = base) (hat : XAt code base (uf L n base ++ rest)) :
    XExec code x (.trapped .stackUnderflow) :=
  uf_trap hg hs hL hn hn3 hk hpc (xat_append.mp hat).1

macro "mid_tac" : tactic =>
  `(tactic| (intro m a b ha hb
             simp [xseq, exec, M.arith, M.mov, M.setReg, M.adv, ha, hb, MidSpec]))

theorem sim_bin_instr {c : Cfg} {p : Prog 64} {s : State 64} {x : M} {code : List (Instr Nat)}
    {L : Layout} {base : Nat} {off : Nat → Nat} (hg : Geom c) (hL : L.dEnd = ofN c.dEnd)
    (hs : Rel0 c p s x) (hpc : x.pc = base) (i : WordDialect.Instr 64) (mid : List (Instr Nat))
    (rr : Reg) (hrr : rr = rax ∨ rr = rcx ∨ rr = rdx ∨ rr = rbx) (f : W → W → W)
    (hmid : MidSpec mid rr f) (hstr : ∀ j ∈ mid, j.straightX = true)
    (hlow : lowerInstr L base off i = uf L 2 base ++
      ([.load rcx r15 0, .load rax r15 8] ++ mid ++ [.store r15 8 rr, .addImm r15 8]))
    (hsize : isize i = 4 + (4 + mid.length))
    (hat : XAt code base (lowerInstr L base off i)) {b a : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    ∃ x', XSteps code x x' ∧ Rel0 c p { s with dstack := f a b :: d } x' ∧
      x'.pc = base + isize i := by
  rw [hlow] at hat
  obtain ⟨x', h1, h2, h3⟩ := sim_bin_ok hg hL hs hpc mid rr hrr f hmid hstr hat hd
  exact ⟨x', h1, h2, by rw [h3, hsize]; omega⟩

theorem sim_uf2_trap {c : Cfg} {p : Prog 64} {s : State 64} {x : M} {code : List (Instr Nat)}
    {L : Layout} {base : Nat} {off : Nat → Nat} (hg : Geom c) (hL : L.dEnd = ofN c.dEnd)
    (hs : Rel0 c p s x) (hpc : x.pc = base) (i : WordDialect.Instr 64) (rest : List (Instr Nat))
    (hlow : lowerInstr L base off i = uf L 2 base ++ rest)
    (hat : XAt code base (lowerInstr L base off i)) (hk : s.dstack.length < 2) :
    XExec code x (.trapped .stackUnderflow) := by
  rw [hlow] at hat
  exact sim_uf_trap hg hs hL (by decide) (by decide) hk hpc hat

/-! ### Middle computations -/

theorem midspec_arith (i : Instr Nat) (f : W → W → W)
    (h : ∀ m : M, exec i m = .next (m.arith rax (f (m.regs rax) (m.regs rcx)))) :
    MidSpec [i] rax f := by
  intro m a b ha hb
  refine ⟨m.arith rax (f (m.regs rax) (m.regs rcx)), by simp [xseq, h], ?_⟩
  simp [M.arith, M.setReg, ha, hb]

theorem midspec_add : MidSpec [.add rax rcx] rax (· + ·) :=
  midspec_arith _ _ (fun m => by simp [exec])
theorem midspec_sub : MidSpec [.sub rax rcx] rax (· - ·) :=
  midspec_arith _ _ (fun m => by simp [exec])
theorem midspec_mul : MidSpec [.imul rax rcx] rax (· * ·) :=
  midspec_arith _ _ (fun m => by simp [exec])
theorem midspec_and : MidSpec [.and rax rcx] rax (· &&& ·) :=
  midspec_arith _ _ (fun m => by simp [exec])
theorem midspec_or : MidSpec [.or rax rcx] rax (· ||| ·) :=
  midspec_arith _ _ (fun m => by simp [exec])
theorem midspec_xor : MidSpec [.xor rax rcx] rax (· ^^^ ·) :=
  midspec_arith _ _ (fun m => by simp [exec])

theorem midspec_shl : MidSpec [.movImm rdx 0#64, .shlCl rax, .cmpImm rcx 64, .cmov .ae rax rdx]
    rax Word.shl := by
  intro m a b ha hb
  by_cases h : 64 ≤ BitVec.toNat b
  · have h' : ¬ BitVec.toNat b < 64 := by omega
    simp [xseq, exec, M.arith, M.mov, M.setReg, M.adv, ha, hb, holds_ae, BitVec.ule_eq_decide,
      Word.shl, h, h']
  · have h' : BitVec.toNat b < 64 := by omega
    simp [xseq, exec, M.arith, M.mov, M.setReg, M.adv, ha, hb, holds_ae, BitVec.ule_eq_decide,
      Word.shl, h, h', Nat.mod_eq_of_lt h']

theorem ushiftRight_ge (a : W) (n : Nat) (h : 64 ≤ n) : a >>> n = 0#64 := by
  apply BitVec.eq_of_toNat_eq
  rw [BitVec.toNat_ushiftRight, Nat.shiftRight_eq_div_pow]
  have : a.toNat < 2 ^ n := Nat.lt_of_lt_of_le a.isLt (Nat.pow_le_pow_right (by omega) h)
  simp [Nat.div_eq_of_lt this]

theorem midspec_shr : MidSpec [.movImm rdx 0#64, .shrCl rax, .cmpImm rcx 64, .cmov .ae rax rdx]
    rax Word.shr := by
  intro m a b ha hb
  by_cases h : 64 ≤ BitVec.toNat b
  · have h' : ¬ BitVec.toNat b < 64 := by omega
    simp [xseq, exec, M.arith, M.mov, M.setReg, M.adv, ha, hb, holds_ae, BitVec.ule_eq_decide,
      Word.shr, h, h', ushiftRight_ge a _ h]
  · have h' : BitVec.toNat b < 64 := by omega
    simp [xseq, exec, M.arith, M.mov, M.setReg, M.adv, ha, hb, holds_ae, BitVec.ule_eq_decide,
      Word.shr, h, h', Nat.mod_eq_of_lt h']

theorem midspec_rotl : MidSpec [.rolCl rax] rax Word.rotl := by
  intro m a b ha hb
  simp [xseq, exec, M.arith, M.setReg, ha, hb, Word.rotl, BitVec.rotateLeft]

theorem midspec_rotr : MidSpec [.rorCl rax] rax Word.rotr := by
  intro m a b ha hb
  simp [xseq, exec, M.arith, M.setReg, ha, hb, Word.rotr, BitVec.rotateRight]

theorem midspec_cmp (cd : WordDialect.Cond) :
    MidSpec [.movImm rdx 0#64, .movImm rbx 1#64, .cmp rax rcx, .cmov (ccOf cd) rdx rbx] rdx
      (fun a b => Word.ofBool (cd.eval a b)) := by
  intro m a b ha hb
  cases h : cd.eval a b <;>
    simp [xseq, exec, M.arith, M.mov, M.setReg, M.adv, ha, hb, holds_ccOf, Word.ofBool, h]

/-! ### Instruction theorems -/

section Ops
variable {c : Cfg} {p : Prog 64} {s : State 64} {x : M} {code : List (Instr Nat)} {L : Layout}
  {base : Nat} {off : Nat → Nat}

theorem sim_add_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : XAt code base (lowerInstr L base off .add)) {b a : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    ∃ x', XSteps code x x' ∧ Rel0 c p { s with dstack := (a + b) :: d } x' ∧
      x'.pc = base + isize (.add : WordDialect.Instr 64) :=
  sim_bin_instr hg hL hs hpc .add [.add rax rcx] rax (by simp) (· + ·) midspec_add
    (by simp [Instr.straightX]) rfl (by simp [isize, ufSize]) hat hd

theorem sim_sub_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : XAt code base (lowerInstr L base off .sub)) {b a : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    ∃ x', XSteps code x x' ∧ Rel0 c p { s with dstack := (a - b) :: d } x' ∧
      x'.pc = base + isize (.sub : WordDialect.Instr 64) :=
  sim_bin_instr hg hL hs hpc .sub [.sub rax rcx] rax (by simp) (· - ·) midspec_sub
    (by simp [Instr.straightX]) rfl (by simp [isize, ufSize]) hat hd

theorem sim_mul_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : XAt code base (lowerInstr L base off .mul)) {b a : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    ∃ x', XSteps code x x' ∧ Rel0 c p { s with dstack := (a * b) :: d } x' ∧
      x'.pc = base + isize (.mul : WordDialect.Instr 64) :=
  sim_bin_instr hg hL hs hpc .mul [.imul rax rcx] rax (by simp) (· * ·) midspec_mul
    (by simp [Instr.straightX]) rfl (by simp [isize, ufSize]) hat hd

theorem sim_and_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : XAt code base (lowerInstr L base off .and)) {b a : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    ∃ x', XSteps code x x' ∧ Rel0 c p { s with dstack := (a &&& b) :: d } x' ∧
      x'.pc = base + isize (.and : WordDialect.Instr 64) :=
  sim_bin_instr hg hL hs hpc .and [.and rax rcx] rax (by simp) (· &&& ·) midspec_and
    (by simp [Instr.straightX]) rfl (by simp [isize, ufSize]) hat hd

theorem sim_or_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : XAt code base (lowerInstr L base off .or)) {b a : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    ∃ x', XSteps code x x' ∧ Rel0 c p { s with dstack := (a ||| b) :: d } x' ∧
      x'.pc = base + isize (.or : WordDialect.Instr 64) :=
  sim_bin_instr hg hL hs hpc .or [.or rax rcx] rax (by simp) (· ||| ·) midspec_or
    (by simp [Instr.straightX]) rfl (by simp [isize, ufSize]) hat hd

theorem sim_xor_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : XAt code base (lowerInstr L base off .xor)) {b a : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    ∃ x', XSteps code x x' ∧ Rel0 c p { s with dstack := (a ^^^ b) :: d } x' ∧
      x'.pc = base + isize (.xor : WordDialect.Instr 64) :=
  sim_bin_instr hg hL hs hpc .xor [.xor rax rcx] rax (by simp) (· ^^^ ·) midspec_xor
    (by simp [Instr.straightX]) rfl (by simp [isize, ufSize]) hat hd

theorem sim_shl_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : XAt code base (lowerInstr L base off .shl)) {b a : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    ∃ x', XSteps code x x' ∧ Rel0 c p { s with dstack := Word.shl a b :: d } x' ∧
      x'.pc = base + isize (.shl : WordDialect.Instr 64) :=
  sim_bin_instr hg hL hs hpc .shl _ rax (by simp) Word.shl midspec_shl
    (by simp [Instr.straightX]) rfl (by simp [isize, ufSize]) hat hd

theorem sim_shr_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : XAt code base (lowerInstr L base off .shr)) {b a : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    ∃ x', XSteps code x x' ∧ Rel0 c p { s with dstack := Word.shr a b :: d } x' ∧
      x'.pc = base + isize (.shr : WordDialect.Instr 64) :=
  sim_bin_instr hg hL hs hpc .shr _ rax (by simp) Word.shr midspec_shr
    (by simp [Instr.straightX]) rfl (by simp [isize, ufSize]) hat hd

theorem sim_rotl_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : XAt code base (lowerInstr L base off .rotl)) {b a : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    ∃ x', XSteps code x x' ∧ Rel0 c p { s with dstack := Word.rotl a b :: d } x' ∧
      x'.pc = base + isize (.rotl : WordDialect.Instr 64) :=
  sim_bin_instr hg hL hs hpc .rotl _ rax (by simp) Word.rotl midspec_rotl
    (by simp [Instr.straightX]) rfl (by simp [isize, ufSize]) hat hd

theorem sim_rotr_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : XAt code base (lowerInstr L base off .rotr)) {b a : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    ∃ x', XSteps code x x' ∧ Rel0 c p { s with dstack := Word.rotr a b :: d } x' ∧
      x'.pc = base + isize (.rotr : WordDialect.Instr 64) :=
  sim_bin_instr hg hL hs hpc .rotr _ rax (by simp) Word.rotr midspec_rotr
    (by simp [Instr.straightX]) rfl (by simp [isize, ufSize]) hat hd

theorem sim_cmp_ok (cd : WordDialect.Cond) (hg : Geom c) (hL : L.dEnd = ofN c.dEnd)
    (hs : Rel0 c p s x) (hpc : x.pc = base) (hat : XAt code base (lowerInstr L base off (.cmp cd)))
    {b a : W} {d : List W} (hd : s.dstack = b :: a :: d) :
    ∃ x', XSteps code x x' ∧
      Rel0 c p { s with dstack := Word.ofBool (cd.eval a b) :: d } x' ∧
      x'.pc = base + isize (.cmp cd : WordDialect.Instr 64) :=
  sim_bin_instr hg hL hs hpc (.cmp cd) _ rdx (by simp) (fun a b => Word.ofBool (cd.eval a b))
    (midspec_cmp cd) (by simp [Instr.straightX]) rfl (by simp [isize, ufSize]) hat hd

end Ops

end X86
end WordDialect
