import X86.Lower

/-!
# X86.Flags

The condition-code semantics (`Cc.holds` on `subFlags`) coincides with the IR comparison
predicates (`Cond.eval`). This is the fact that makes `cmp; cmovcc` a correct lowering of IR
`CMP`, for all ten conditions, in all four of `ZF SF CF OF`.
-/

namespace WordDialect
namespace X86

theorem sub_zero_iff (a b : W) : (a - b == 0#64) = (a == b) := by
  have h : (a - b = 0#64) ↔ (a = b) := by
    constructor
    · intro h
      apply BitVec.eq_of_toNat_eq
      have := congrArg BitVec.toNat h
      simp [BitVec.toNat_sub] at this
      have := a.isLt; have := b.isLt
      omega
    · intro h; subst h; simp
  by_cases h' : a = b
  · simp [h']
  · have hne : ¬ (a - b = 0#64) := fun hh => h' (h.mp hh)
    rw [beq_eq_false_iff_ne.mpr hne, beq_eq_false_iff_ne.mpr h']

theorem holds_e (a b : W) : Cc.e.holds (subFlags a b) = (a == b) := by
  unfold Cc.holds subFlags; exact sub_zero_iff a b

theorem holds_ne (a b : W) : Cc.ne.holds (subFlags a b) = (a != b) := by
  unfold Cc.holds subFlags
  simp only [sub_zero_iff]
  rfl

theorem holds_b (a b : W) : Cc.b.holds (subFlags a b) = a.ult b := by
  unfold Cc.holds subFlags; rfl

theorem holds_ae (a b : W) : Cc.ae.holds (subFlags a b) = b.ule a := by
  unfold Cc.holds subFlags
  simp only [BitVec.ult_eq_decide, BitVec.ule_eq_decide]
  by_cases h : a.toNat < b.toNat <;> simp [h] <;> omega

theorem holds_be (a b : W) : Cc.be.holds (subFlags a b) = a.ule b := by
  unfold Cc.holds subFlags
  simp only [sub_zero_iff, BitVec.ult_eq_decide, BitVec.ule_eq_decide]
  by_cases h2 : a = b
  · subst h2; simp
  · have h3 : a.toNat ≠ b.toNat := fun h => h2 (BitVec.eq_of_toNat_eq h)
    have h4 : (a == b) = false := beq_eq_false_iff_ne.mpr h2
    by_cases h1 : a.toNat < b.toNat
    · simp [h1, h4]; omega
    · simp [h1, h4]
      omega

theorem holds_a (a b : W) : Cc.a.holds (subFlags a b) = b.ult a := by
  unfold Cc.holds subFlags
  simp only [sub_zero_iff, BitVec.ult_eq_decide]
  by_cases h2 : a = b
  · subst h2; simp
  · have h3 : a.toNat ≠ b.toNat := fun h => h2 (BitVec.eq_of_toNat_eq h)
    have h4 : (a == b) = false := beq_eq_false_iff_ne.mpr h2
    by_cases h1 : a.toNat < b.toNat
    · simp [h1, h4]; omega
    · simp [h1, h4]
      omega

theorem holds_signed_core (a b : W) :
    ((a - b).msb != (a.msb != b.msb && a.msb != (a - b).msb)) = a.slt b := by
  have ha := a.isLt; have hb := b.isLt
  simp only [BitVec.msb_eq_decide, BitVec.slt_eq_decide, BitVec.toInt_eq_toNat_cond,
    BitVec.toNat_sub]
  by_cases c1 : 2 ^ (64 - 1) ≤ a.toNat <;> by_cases c2 : 2 ^ (64 - 1) ≤ b.toNat <;>
  by_cases c3 : 2 ^ (64 - 1) ≤ (2 ^ 64 - b.toNat + a.toNat) % 2 ^ 64 <;>
  simp [c1, c2, c3] <;> omega

theorem holds_l (a b : W) : Cc.l.holds (subFlags a b) = a.slt b := by
  unfold Cc.holds subFlags; simp only []; exact holds_signed_core a b
theorem beq_eq_not_bne (x y : Bool) : (x == y) = !(x != y) := by
  cases x <;> cases y <;> rfl

theorem holds_ge (a b : W) : Cc.ge.holds (subFlags a b) = b.sle a := by
  unfold Cc.holds subFlags
  simp only []
  have hc := holds_signed_core a b
  rw [beq_eq_not_bne, hc, BitVec.slt_eq_decide, BitVec.sle_eq_decide]
  by_cases h : a.toInt < b.toInt <;> simp [h] <;> omega

