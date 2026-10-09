import Forth.Semantics

/-!
# Forth.LoopProps

What the `+LOOP` exit test `loopCrossed` means.

* `loopCrossed_eq_saddOverflow`: the loop ends exactly when adding the step to
  `index - limit - 2^(n-1)` overflows as a signed number. Shifting by `2^(n-1)` moves the
  boundary between `limit - 1` and `limit` to the boundary between the largest and the smallest
  signed number, so this is ANS Forth's rule: `+LOOP` ends when the index crosses the boundary
  between the limit minus one and the limit.
* `loopCrossed_one`: with step `1` (and words of at least two bits) the test is the `LOOP` test
  `index + 1 = limit`, so `n LOOP` and `1 +LOOP` agree.
-/

namespace WordDialect
namespace Forth

open IR

theorem msb_succ_iff {n : Nat} (hn : 2 ≤ n) (o : BitVec n) :
    (o.msb && !(o + 1#n).msb) = (o + 1#n == 0#n) := by
  have hN : 2 ^ n = 2 * 2 ^ (n - 1) := by
    rw [← Nat.pow_succ']; congr 1; omega
  have h1 : (1 : Nat) < 2 ^ (n - 1) := Nat.one_lt_two_pow (by omega)
  have ho := o.isLt
  rw [BitVec.msb_eq_decide, BitVec.msb_eq_decide]
  rw [BitVec.toNat_add, BitVec.toNat_ofNat]
  have h1n : 1 % 2 ^ n = 1 := Nat.mod_eq_of_lt (by omega)
  rw [h1n]
  by_cases hlt : o.toNat + 1 < 2 ^ n
  · rw [Nat.mod_eq_of_lt hlt]
    have : (o + 1#n == 0#n) = false := by
      simp only [beq_eq_false_iff_ne, ne_eq]
      intro h
      have := congrArg BitVec.toNat h
      rw [BitVec.toNat_add, BitVec.toNat_ofNat, h1n, Nat.mod_eq_of_lt hlt] at this
      simp at this
    rw [this]
    by_cases hm : 2 ^ (n - 1) ≤ o.toNat <;> simp [hm] <;> omega
  · have he : o.toNat + 1 = 2 ^ n := by omega
    rw [he, Nat.mod_self]
    have : (o + 1#n == 0#n) = true := by
      simp only [beq_iff_eq]
      apply BitVec.eq_of_toNat_eq
      rw [BitVec.toNat_add, BitVec.toNat_ofNat, h1n, he, Nat.mod_self]; simp
    rw [this]
    simp; omega

/-- With step `1`, the `+LOOP` test is the `LOOP` test: the loop ends exactly when
`index + 1 = limit`. -/
theorem loopCrossed_one {n : Nat} (hn : 2 ≤ n) (i l : Word n) :
    loopCrossed i l 1#n = (i + 1#n == l) := by
  have hm1 : (1#n).msb = false := by
    rw [BitVec.msb_eq_decide, BitVec.toNat_ofNat,
      Nat.mod_eq_of_lt (Nat.one_lt_two_pow (n := n) (by omega))]
    simp only [decide_eq_false_iff_not, Nat.not_le]
    exact Nat.one_lt_two_pow (n := n - 1) (by omega)
  simp only [loopCrossed, Cond.eval, BitVec.slt_zero_eq_msb, BitVec.msb_and, BitVec.msb_xor, hm1,
    Bool.xor_false]
  have key := msb_succ_iff hn (i - l)
  rw [BitVec.add_comm (1#n)] 
  have e : (i - l + 1#n == 0#n) = (i + 1#n == l) := by
    have hi : i + 1#n = (i - l + 1#n) + l := by
      conv => lhs; rw [← BitVec.sub_add_cancel i l]
      rw [BitVec.add_assoc, BitVec.add_comm l, ← BitVec.add_assoc]
    apply Bool.eq_iff_iff.mpr
    simp only [beq_iff_eq]
    constructor
    · intro h; rw [hi, h, BitVec.zero_add]
    · intro h
      have h2 : (i - l + 1#n) + l = 0#n + l := by rw [← hi, h, BitVec.zero_add]
      have := congrArg (· - l) h2
      simpa only [BitVec.add_sub_cancel] using this
  rw [← e, ← key]
  cases (i - l).msb <;> cases (i - l + 1#n).msb <;> rfl

theorem msb_add_intMin {n : Nat} (hn : 0 < n) (x : BitVec n) :
    (x + BitVec.intMin n).msb = !x.msb := by
  have hN : 2 ^ n = 2 * 2 ^ (n - 1) := by
    rw [← Nat.pow_succ']; congr 1; omega
  have hx := x.isLt
  have hm : (BitVec.intMin n).toNat = 2 ^ (n - 1) := by
    rw [BitVec.toNat_intMin]; exact Nat.mod_eq_of_lt (by omega)
  rw [BitVec.msb_eq_decide, BitVec.msb_eq_decide, BitVec.toNat_add, hm]
  by_cases hlt : x.toNat < 2 ^ (n - 1)
  · rw [Nat.mod_eq_of_lt (by omega)]; simp [hlt]
  · rw [Nat.mod_eq_sub_mod (by omega), Nat.mod_eq_of_lt (by omega)]
    simp only [Nat.not_lt] at hlt; simp [hlt]; omega

/-- **The `+LOOP` test is ANS Forth's crossing rule**: the loop ends exactly when adding the step
to `index - limit - 2^(n-1)` overflows as a signed number, i.e. when `index` passes from one side
of the boundary between `limit - 1` and `limit` to the other. -/
theorem loopCrossed_eq_saddOverflow {n : Nat} (hn : 0 < n) (i l k : Word n) :
    loopCrossed i l k = (i - l + BitVec.intMin n).saddOverflow k := by
  rw [BitVec.saddOverflow_eq]
  have h2 : i - l + BitVec.intMin n + k = (k + (i - l)) + BitVec.intMin n := by
    rw [BitVec.add_assoc, BitVec.add_comm (BitVec.intMin n), ← BitVec.add_assoc,
      BitVec.add_comm (i - l)]
  rw [h2, msb_add_intMin hn, msb_add_intMin hn]
  simp only [loopCrossed, Cond.eval, BitVec.slt_zero_eq_msb, BitVec.msb_and, BitVec.msb_xor]
  cases (i - l).msb <;> cases k.msb <;> cases (k + (i - l)).msb <;> rfl

end Forth
end WordDialect
