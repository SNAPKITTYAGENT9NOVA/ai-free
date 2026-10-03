import Wasm.Isa

/-!
# Wasm.Mem

Byte-level memory facts: a write of eight bytes is read back by a read at the same address, and
leaves every read at a disjoint address unchanged. These replace any "word cell" memory assumption.
-/

namespace WordDialect
namespace Wasm

theorem rdBytes_congr {b b' : Nat → Nat} {a : Nat} :
    ∀ {n : Nat}, (∀ i, i < n → b (a + i) = b' (a + i)) → rdBytes b a n = rdBytes b' a n := by
  intro n
  induction n with
  | zero => intro _; rfl
  | succ n ih =>
    intro h
    simp only [rdBytes]
    rw [ih (fun i hi => h i (by omega)), h n (by omega)]

theorem rdBytes_pow (v : Nat) : ∀ n : Nat,
    rdBytes (fun p => (v / 256 ^ p) % 256) 0 n = v % 256 ^ n := by
  intro n
  induction n with
  | zero => simp [rdBytes, Nat.mod_one]
  | succ n ih =>
    simp only [rdBytes, Nat.zero_add]
    rw [ih, Nat.pow_succ, Nat.mod_mul]
    simp [Nat.mod_mod, Nat.mul_comm]

theorem write64_size {m m' : WMem} {a : Nat} {v : W} (h : m.write64 a v = some m') :
    m'.size = m.size ∧ a + 8 ≤ m.size := by
  unfold WMem.write64 at h
  split at h
  · rename_i hlt; simp at h; subst h; exact ⟨rfl, hlt⟩
  · simp at h

theorem write64_some {m : WMem} {a : Nat} {v : W} (h : a + 8 ≤ m.size) :
    ∃ m', m.write64 a v = some m' := by
  simp [WMem.write64, h]

theorem read64_write64_same {m m' : WMem} {a : Nat} {v : W} (h : m.write64 a v = some m') :
    m'.read64 a = some v := by
  obtain ⟨hs, hlt⟩ := write64_size h
  unfold WMem.write64 at h
  rw [if_pos hlt] at h
  simp at h
  subst h
  unfold WMem.read64
  rw [if_pos (by simpa using hlt)]
  congr 1
  have hc : rdBytes (fun p => if a ≤ p ∧ p < a + 8 then (v.toNat / 256 ^ (p - a)) % 256 else m.bytes p) a 8
      = rdBytes (fun p => (v.toNat / 256 ^ p) % 256) 0 8 := by
    rw [show rdBytes (fun p => (v.toNat / 256 ^ p) % 256) 0 8 =
        rdBytes (fun p => (v.toNat / 256 ^ (p - a)) % 256) a 8 from ?_]
    · apply rdBytes_congr
      intro i hi
      have h1 : a ≤ a + i := by omega
      have h2 : a + i < a + 8 := by omega
      simp [h1, h2]
    · simp only [rdBytes]
      simp [Nat.add_sub_cancel_left]
  rw [hc, rdBytes_pow]
  have : v.toNat < 256 ^ 8 := by have := v.isLt; simpa using this
  rw [Nat.mod_eq_of_lt this]
  simp

theorem read64_write64_other {m m' : WMem} {a b : Nat} {v : W} (h : m.write64 a v = some m')
    (hd : b + 8 ≤ a ∨ a + 8 ≤ b) : m'.read64 b = m.read64 b := by
  obtain ⟨hs, hlt⟩ := write64_size h
  unfold WMem.write64 at h
  rw [if_pos hlt] at h
  simp at h
  subst h
  unfold WMem.read64
  simp only []
  by_cases hb : b + 8 ≤ m.size
  · rw [if_pos hb, if_pos hb]
    congr 2
    apply rdBytes_congr
    intro i hi
    have : ¬ (a ≤ b + i ∧ b + i < a + 8) := by omega
    simp [this]
  · rw [if_neg hb, if_neg hb]

end Wasm
end WordDialect
