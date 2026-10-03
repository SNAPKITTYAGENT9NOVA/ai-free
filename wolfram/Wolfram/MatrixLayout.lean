import WordDialect
import WordIR

/-!
# Wolfram.MatrixLayout

Mathematical and memory-level vocabulary for matrix lowering.

* A matrix is a function `Nat → Nat → Int`; `dotSum A B i j t = Σ_{l<t} A i l * B l j`.
* In memory a `rows × cols` matrix at `base` is row-major: element `(i, j)` is the word at
  address `base + i*cols + j`, holding `ofInt` of the entry (so entries are exact integers
  reduced modulo `2^n`).
* `CWritten mem0 mem bC val cnt` says `mem` is `mem0` with exactly the first `cnt` words of the
  destination region replaced by `val`.
-/

namespace WordDialect
namespace Wolfram

open IR

/-- `Σ_{l<t} A i l * B l j`. -/
def dotSum (A B : Nat → Nat → Int) (i j : Nat) : Nat → Int
  | 0 => 0
  | t + 1 => dotSum A B i j t + A i t * B t j

/-- Row-major matrix `M` of size `rows × cols` stored at `base`. -/
def MatAt {n : Nat} (mem : Memory n) (base rows cols : Nat) (M : Nat → Nat → Int) : Prop :=
  ∀ i j, i < rows → j < cols →
    mem.read? (BitVec.ofNat n (base + i * cols + j)) = some (BitVec.ofInt n (M i j))

theorem ofNat_inj {n : Nat} {a b : Nat} (ha : a < 2 ^ n) (hb : b < 2 ^ n)
    (h : BitVec.ofNat n a = BitVec.ofNat n b) : a = b := by
  have := congrArg BitVec.toNat h
  simpa [BitVec.toNat_ofNat, Nat.mod_eq_of_lt ha, Nat.mod_eq_of_lt hb] using this

def CWritten {n : Nat} (mem0 mem : Memory n) (bC : Nat) (val : Nat → Word n) (cnt : Nat) : Prop :=
  mem.valid = mem0.valid ∧
  (∀ q, q < cnt → mem.read? (BitVec.ofNat n (bC + q)) = some (val q)) ∧
  (∀ a, (∀ q, q < cnt → a ≠ BitVec.ofNat n (bC + q)) → mem.read? a = mem0.read? a)

theorem cwritten_zero {n : Nat} (mem0 : Memory n) (bC : Nat) (val : Nat → Word n) :
    CWritten mem0 mem0 bC val 0 :=
  ⟨rfl, fun q hq => absurd hq (Nat.not_lt_zero q), fun _ _ => rfl⟩

/-- Writing the next destination word extends the written prefix by one. -/
theorem cwritten_step {n : Nat} {mem0 mem mem' : Memory n} {bC cnt : Nat}
    {val : Nat → Word n} (hb : bC + cnt < 2 ^ n)
    (h : CWritten mem0 mem bC val cnt)
    (hw : mem.write? (BitVec.ofNat n (bC + cnt)) (val cnt) = some mem') :
    CWritten mem0 mem' bC val (cnt + 1) := by
  obtain ⟨hv, hr, ho⟩ := h
  refine ⟨(Memory.write?_valid hw).trans hv, ?_, ?_⟩
  · intro q hq
    by_cases hqc : q = cnt
    · subst hqc; exact Memory.read_write_same hw
    · have hq' : q < cnt := by omega
      have hne : BitVec.ofNat n (bC + q) ≠ BitVec.ofNat n (bC + cnt) := by
        intro heq
        have := ofNat_inj (by omega) hb heq
        omega
      rw [Memory.read_write_other hw hne]
      exact hr q hq'
  · intro a ha
    have hne : a ≠ BitVec.ofNat n (bC + cnt) := ha cnt (by omega)
    rw [Memory.read_write_other hw hne]
    exact ho a (fun q hq => ha q (by omega))

/-- A source cell outside the destination region is read unchanged. -/
theorem cwritten_read_other {n : Nat} {mem0 mem : Memory n} {bC cnt : Nat}
    {val : Nat → Word n} (h : CWritten mem0 mem bC val cnt) {a : Nat} (ha : a < 2 ^ n)
    (hc : bC + cnt ≤ 2 ^ n) (hdisj : bC + cnt ≤ a ∨ a < bC) :
    mem.read? (BitVec.ofNat n a) = mem0.read? (BitVec.ofNat n a) := by
  apply h.2.2
  intro q hq heq
  have := ofNat_inj ha (by omega) heq
  omega

end Wolfram
end WordDialect
