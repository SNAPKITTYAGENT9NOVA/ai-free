import Wasm.SimAlu

/-!
# Wasm.SimAlu2

Shifts (a count of 64 or more yields 0), `div` and `sdiv` (zero guard; `sdiv` by -1 avoids the
`INT64_MIN / -1` trap of `i64.div_s`), and `not`.
-/

namespace WordDialect
namespace Wasm

section Sim

variable {c : Cfg} {s : State 64} {w : WState} {fs : Funcs}

theorem ctl_shiftBody (op : WI) (hop : op.isCtl = false) : ∀ i ∈ shiftBody op, i.isCtl = false :=
  allSimple_spec (by simp only [allSimple, shiftBody, ldS, spAdd, List.all_append, List.all_cons, List.all_nil, hop, Bool.not_false, Bool.and_true, Bool.true_and]; decide)

theorem shiftBody_split (op : WI) : shiftBody op =
    ([.globalGet spG, .i64const 0#64] ++ ldS 8 ++ ldS 0) ++ [op] ++
      (ldS 0 ++ [.i64const 64#64, .i64geu, .select, .i64store 8] ++ spAdd 8) := by
  simp [shiftBody, List.append_assoc]

theorem sim_shift_gen (hg : Geom c) (hs : Rel0 c s w) (hst : w.stack = []) {a b : W} {d : List W}
    {pre : List WI} (hpre : Run fs pre w (.normal w)) (hd : s.dstack = b :: a :: d)
    {op : WI} (hctl : op.isCtl = false) {z y : W}
    (hop : ∀ (u : WState) (r : List Val), u.stack = .i64 b :: .i64 a :: r →
      execL [op] u = some { u with stack := .i64 z :: r })
    (hy : y = if (64#64).ule b then 0#64 else z) (nxt : Nat) :
    ∃ w', Run fs (pre ++ (shiftBody op ++ [i32c nxt])) w (.normal w') ∧
      Rel0 c { s with dstack := y :: d } w' ∧ w'.stack = [.i32 (ofN nxt)] := by
  have hlen : s.dstack.length = d.length + 2 := by simp [hd]
  have hX := sp_lt hg hs
  have hr1 : w.mem.read64 (c.dEnd - 8 * s.dstack.length + 8) = some a := by
    have := hs.stack 1 a (by simp [hd]); simpa using this
  have hr0 : w.mem.read64 (c.dEnd - 8 * s.dstack.length) = some b := by
    have := hs.stack 0 b (by simp [hd]); simpa using this
  refine sim_bin_core hg hs hst hpre hd (ctl_shiftBody op hctl) ?_ nxt
  intro m' hm'
  have hsp8 : ofN (c.dEnd - 8 * s.dstack.length) + 8#32 = ofN (c.dEnd - 8 * s.dstack.length + 8) :=
    ofN_add _ _
  have h1 : execL ([.globalGet spG, .i64const 0#64] ++ ldS 8 ++ ldS 0) w = some { w with stack := .i64 b :: .i64 a :: .i64 0#64 :: .i32 (ofN (c.dEnd - 8 * s.dstack.length)) :: w.stack } := by
    simp [ldS, execL, stepI, hs.sp, ofN_toNat hX, hr0, hr1]
  have hop' := hop { w with stack := .i64 b :: .i64 a :: .i64 0#64 :: .i32 (ofN (c.dEnd - 8 * s.dstack.length)) :: w.stack } (.i64 0#64 :: .i32 (ofN (c.dEnd - 8 * s.dstack.length)) :: w.stack) rfl
  have h3 : execL (ldS 0 ++ [.i64const 64#64, .i64geu, .select, .i64store 8] ++ spAdd 8) { w with stack := .i64 z :: .i64 0#64 :: .i32 (ofN (c.dEnd - 8 * s.dstack.length)) :: w.stack } = some { w with mem := m', globals := setG w.globals spG (.i32 (ofN (c.dEnd - 8 * s.dstack.length + 8))) } := by
    subst hy
    by_cases hc : (64#64).ule b = true
    · have hm2 : w.mem.write64 (c.dEnd - 8 * s.dstack.length + 8) 0#64 = some m' := by simpa [hc] using hm'
      simp [ldS, spAdd, execL, stepI, bin32, cmp64, hs.sp, ofN_toNat hX, hr0, bool32, hc, hm2, i32c, hsp8]
      rfl
    · have hc' : (64#64).ule b = false := by simpa using hc
      have hm2 : w.mem.write64 (c.dEnd - 8 * s.dstack.length + 8) z = some m' := by simpa [hc'] using hm'
      simp [ldS, spAdd, execL, stepI, bin32, cmp64, hs.sp, ofN_toNat hX, hr0, bool32, hc', hm2, i32c, hsp8]
      rfl
  rw [shiftBody_split, execL_append, execL_append, h1]
  simp only [Option.bind_some]
  rw [hop']
  simp only [Option.bind_some]
  exact h3

theorem ule64_iff (b : W) : ((64#64).ule b = true) ↔ 64 ≤ b.toNat := by
  simp [BitVec.ule_eq_decide]

theorem sim_shl (n k : Nat) (hg : Geom c) (hs : Rel0 c s w) (hst : w.stack = []) {a b : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    Sim1 c fs (lowerInstr c.layout n k .shl) { s with dstack := Word.shl a b :: d } w (k + 1) := by
  have := sim_shift_gen (fs := fs) hg hs hst (uf2_pass hg hs hd) hd (op := .i64shl) rfl
    (z := a <<< (b.toNat % 64)) (y := Word.shl a b)
    (by intro u r h; simp [execL, stepI, bin64, h])
    (by
      by_cases hc : 64 ≤ b.toNat
      · simp [(ule64_iff b).mpr hc, Word.shl, show ¬ b.toNat < 64 by omega]
      · have : ¬ ((64#64).ule b = true) := fun h => hc ((ule64_iff b).mp h)
        simp [this, Word.shl, show b.toNat < 64 by omega, Nat.mod_eq_of_lt (show b.toNat < 64 by omega)]) (k + 1)
  simpa [lowerInstr, shiftOp, List.append_assoc] using this

theorem ushiftRight_ge {a : W} {m : Nat} (h : 64 ≤ m) : a >>> m = 0#64 := by
  apply BitVec.eq_of_toNat_eq
  simp only [BitVec.toNat_ushiftRight, Nat.shiftRight_eq_div_pow]
  have : a.toNat < 2 ^ m := Nat.lt_of_lt_of_le a.isLt (Nat.pow_le_pow_right (by omega) h)
  simp [Nat.div_eq_of_lt this]

theorem sim_shr (n k : Nat) (hg : Geom c) (hs : Rel0 c s w) (hst : w.stack = []) {a b : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    Sim1 c fs (lowerInstr c.layout n k .shr) { s with dstack := Word.shr a b :: d } w (k + 1) := by
  have := sim_shift_gen (fs := fs) hg hs hst (uf2_pass hg hs hd) hd (op := .i64shru) rfl
    (z := a >>> (b.toNat % 64)) (y := Word.shr a b)
    (by intro u r h; simp [execL, stepI, bin64, h])
    (by
      by_cases hc : 64 ≤ b.toNat
      · simp [(ule64_iff b).mpr hc, Word.shr, ushiftRight_ge hc]
      · have : ¬ ((64#64).ule b = true) := fun h => hc ((ule64_iff b).mp h)
        simp [this, Word.shr, Nat.mod_eq_of_lt (show b.toNat < 64 by omega)]) (k + 1)
  simpa [lowerInstr, shiftOp, List.append_assoc] using this

/-- The zero guard, passing case. -/
theorem zg_pass (hg : Geom c) (hs : Rel0 c s w) {b : W} {d : List W} (hd : s.dstack = b :: d) (hne : b ≠ 0#64) :
    Run fs zeroGuard w (.normal w) := by
  have hX := sp_lt hg hs
  have hr0 : w.mem.read64 (c.dEnd - 8 * s.dstack.length) = some b := by
    have := hs.stack 0 b (by simp [hd]); simpa using this
  have h1 : execL (ldS 0 ++ [.i64eqz]) w = some { w with stack := .i32 (bool32 false) :: w.stack } := by
    simp [ldS, execL, stepI, hs.sp, ofN_toNat hX, hr0, bool32, hne]
  have h2 : Run fs (ldS 0 ++ [.i64eqz]) w (.normal { w with stack := .i32 (bool32 false) :: w.stack }) :=
    run_of_execL (by simp [ldS, WI.isCtl]) h1
  have h3 := run_ite_false (fs := fs) (thn := [.exitTrap 3]) (w := { w with stack := .i32 (bool32 false) :: w.stack }) (r := w.stack) (by simp [bool32])
  simpa [zeroGuard, List.append_assoc] using run_append _ h2 h3

/-- The zero guard, trapping case. -/
theorem zg_trap (hg : Geom c) (hs : Rel0 c s w) {d : List W} (hd : s.dstack = 0#64 :: d) :
    Run fs zeroGuard w (.exit 3) := by
  have hX := sp_lt hg hs
  have hr0 : w.mem.read64 (c.dEnd - 8 * s.dstack.length) = some 0#64 := by
    have := hs.stack 0 0#64 (by simp [hd]); simpa using this
  have h1 : execL (ldS 0 ++ [.i64eqz]) w = some { w with stack := .i32 (bool32 true) :: w.stack } := by
    simp [ldS, execL, stepI, hs.sp, ofN_toNat hX, hr0, bool32]
  have h2 : Run fs (ldS 0 ++ [.i64eqz]) w (.normal { w with stack := .i32 (bool32 true) :: w.stack }) :=
    run_of_execL (by simp [ldS, WI.isCtl]) h1
  have h3 := run_ite_exit (fs := fs) (w := { w with stack := .i32 (bool32 true) :: w.stack }) (r := w.stack) (c := bool32 true) (k := 3) rfl (by simp [bool32])
  simpa [zeroGuard, List.append_assoc] using run_append _ h2 h3

end Sim

end Wasm
end WordDialect
