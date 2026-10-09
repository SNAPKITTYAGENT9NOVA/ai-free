/-!
# Forth.DoubleMath

Natural-number facts behind the double-cell words. A double-cell number is a pair of `n`-bit
words `(hi, lo)` standing for `hi * N + lo`, with `N = 2^n`. The lemmas say what the word-level
steps of the shift-and-add multiplication and the restoring division do to that value:

* `dshl`: shifting the pair left by one bit doubles it (when the top bit of `hi` is clear);
* `addc`: adding a word to `lo` with the carry `lo + x <u x` adds it to the pair;
* `bit_of_shifted`, `div_pow_succ`: the bit shifted out at the top of `x * 2^k` is the next
  bit of `x` from the top, which extends `x / 2^(m+1)` to `x / 2^m`.
-/

namespace WordDialect
namespace Forth
namespace DoubleMath

theorem iteT {c : Prop} [Decidable c] {α : Sort _} {a b : α} (h : c) : ite c a b = a := by simp [h]
theorem iteF {c : Prop} [Decidable c] {α : Sort _} {a b : α} (h : ¬c) : ite c a b = b := by simp [h]

theorem two_pow_succ' (n : Nat) (hn : 0 < n) : 2 ^ n = 2 * 2 ^ (n - 1) := by
  rw [← Nat.pow_succ']; congr 1; omega

/-- Shifting a double-cell pair left by one: the new high word is `2 hi + (lo / H)`, the new low
word `2 lo mod N`. -/
theorem dshl {N H hi lo : Nat} (hN : N = 2 * H) (hhi : hi < H) (hlo : lo < N) :
    ((2 * hi) % N + lo / H) % N * N + (2 * lo) % N = 2 * (hi * N + lo) := by
  have h2hi : (2 * hi) % N = 2 * hi := Nat.mod_eq_of_lt (by omega)
  rw [h2hi]
  by_cases hl : lo < H
  · have hd : lo / H = 0 := Nat.div_eq_of_lt hl
    have hm : (2 * lo) % N = 2 * lo := Nat.mod_eq_of_lt (by omega)
    rw [hd, hm, Nat.add_zero, Nat.mod_eq_of_lt (by omega)]
    rw [Nat.mul_add, Nat.mul_assoc]
  · have hd : lo / H = 1 := by
      apply Nat.div_eq_of_lt_le <;> omega
    have hm : (2 * lo) % N = 2 * lo - N := by
      rw [Nat.mod_eq_sub_mod (by omega), Nat.mod_eq_of_lt (by omega)]
    rw [hd, hm, Nat.mod_eq_of_lt (by omega), Nat.add_mul, Nat.one_mul, Nat.mul_add, Nat.mul_assoc]
    omega

/-- Adding `x` to the low word with carry `(lo + x) mod N <u x`. -/
theorem addc {N lo x : Nat} (hlo : lo < N) (hx : x < N) :
    (lo + x) % N + (if (lo + x) % N < x then 1 else 0) * N = lo + x := by
  by_cases h : lo + x < N
  · rw [Nat.mod_eq_of_lt h]
    split <;> omega
  · have hm : (lo + x) % N = lo + x - N := by
      rw [Nat.mod_eq_sub_mod (by omega), Nat.mod_eq_of_lt (by omega)]
    rw [hm]
    split <;> omega

/-- The bit at position `n - 1` of `x * 2^k` (mod `2^n`) is bit `n - 1 - k` of `x`. -/
theorem bit_of_shifted (x k m : Nat) :
    x * 2 ^ k % 2 ^ (m + 1 + k) / 2 ^ (m + k) = x / 2 ^ m % 2 := by
  rw [Nat.pow_add, Nat.pow_add 2 m k, Nat.mul_mod_mul_right,
    Nat.mul_div_mul_right _ _ (Nat.two_pow_pos k), Nat.pow_succ, Nat.mod_mul_right_div_self]

theorem div_pow_succ (x m : Nat) : x / 2 ^ m = 2 * (x / 2 ^ (m + 1)) + x / 2 ^ m % 2 := by
  have h1 := Nat.div_add_mod (x / 2 ^ m) 2
  have h2 : x / 2 ^ (m + 1) = x / 2 ^ m / 2 := by rw [Nat.pow_succ, Nat.div_div_eq_div_mul]
  omega

theorem bit_le_one (x m : Nat) : x / 2 ^ m % 2 ≤ 1 := by
  have := Nat.mod_lt (x / 2 ^ m) (by decide : 2 > 0); omega

/-- `x / 2^(n-k) < 2^k` for `x < 2^n`. -/
theorem div_lt_pow {x n k : Nat} (hx : x < 2 ^ n) (hk : k ≤ n) : x / 2 ^ (n - k) < 2 ^ k := by
  apply Nat.div_lt_of_lt_mul
  rw [← Nat.pow_add, Nat.sub_add_cancel hk]; exact hx

/-- **One step of the shift-and-add multiplication** (most significant bit of `B` first). The
pair `(hi, lo)` holds `A * (B / 2^(n-k))`; the step doubles it (`lo1`, `hi1`), adds `A` times the
next bit of `B` (the top bit of `B * 2^k`) with a carry `c`, and then holds
`A * (B / 2^(n-(k+1)))`. -/
theorem umstar_step {n k A B hi lo : Nat} (hn : 0 < n) (hk : k < n) (hA : A < 2 ^ n)
    (hB : B < 2 ^ n) (hlo : lo < 2 ^ n) (hinv : hi * 2 ^ n + lo = A * (B / 2 ^ (n - k))) :
    let N := 2 ^ n
    let H := 2 ^ (n - 1)
    let lo1 := (2 * lo) % N
    let hi1 := ((2 * hi) % N + lo / H) % N
    let X := (A * (B * 2 ^ k % N / H)) % N
    let L := (X + lo1) % N
    let c := if L < X then 1 else 0
    (c + hi1) % N * N + L = A * (B / 2 ^ (n - (k + 1))) := by
  intro N H lo1 hi1 X L c
  have hN : N = 2 * H := two_pow_succ' n hn
  -- the next bit of `B`
  change hi * N + lo = _ at hinv
  have hbit : B * 2 ^ k % N / H = B / 2 ^ (n - (k + 1)) % 2 := by
    have := bit_of_shifted B k (n - (k + 1))
    rwa [show n - (k + 1) + 1 + k = n by omega, show n - (k + 1) + k = n - 1 by omega] at this
  have hsplit : B / 2 ^ (n - (k + 1)) = 2 * (B / 2 ^ (n - k)) + B / 2 ^ (n - (k + 1)) % 2 := by
    have e : n - (k + 1) + 1 = n - k := by omega
    have := div_pow_succ B (n - (k + 1)); rw [e] at this; exact this
  have hb1 := bit_le_one B (n - (k + 1))
  generalize hQ : B / 2 ^ (n - k) = Q at hinv hsplit
  generalize hbt : B / 2 ^ (n - (k + 1)) % 2 = bt at hbit hsplit hb1
  have hQlt : Q < 2 ^ k := hQ ▸ div_lt_pow hB (Nat.le_of_lt hk)
  have hHk : 2 ^ k ≤ H := Nat.pow_le_pow_right (by decide) (by omega)
  -- `hi < 2^k ≤ H`
  have hAQ : A * Q < N * 2 ^ k := Nat.mul_lt_mul_of_lt_of_le hA (Nat.le_of_lt hQlt) (Nat.two_pow_pos k)
  have hhi : hi < H := by
    have : hi * N < 2 ^ k * N := by rw [Nat.mul_comm (2 ^ k)]; omega
    exact Nat.lt_of_lt_of_le (Nat.lt_of_mul_lt_mul_right this) hHk
  have hd := dshl hN hhi hlo
  change hi1 * N + lo1 = 2 * (hi * N + lo) at hd
  -- the addend
  have hX : X = A * bt := by
    show A * (B * 2 ^ k % N / H) % N = A * bt
    rw [hbit]
    rcases (by omega : bt = 0 ∨ bt = 1) with h | h <;> subst h
    · simp
    · simp only [Nat.mul_one]; exact Nat.mod_eq_of_lt hA
  have hXlt : X < N := by rw [hX]; rcases (by omega : bt = 0 ∨ bt = 1) with h | h <;> subst h <;> simp <;> omega
  have hlo1 : lo1 < N := Nat.mod_lt _ (Nat.two_pow_pos n)
  have hac := addc (N := N) hlo1 hXlt
  rw [Nat.add_comm lo1 X] at hac
  change L + c * N = X + lo1 at hac
  -- total stays below `N * N`
  have htot : A * (2 * Q + bt) < N * N := by
    have h1 : 2 * Q + bt < 2 ^ (k + 1) := by rw [Nat.pow_succ]; omega
    have h2 : 2 ^ (k + 1) ≤ N := Nat.pow_le_pow_right (by decide) hk
    exact Nat.mul_lt_mul_of_lt_of_le hA (by omega) (by omega)
  have hexp : A * (2 * Q + bt) = 2 * (A * Q) + A * bt := by
    rw [Nat.mul_add, Nat.mul_left_comm]
  have hc : c + hi1 < N := by
    have : (c + hi1) * N < N * N := by
      rw [Nat.add_mul]
      have : c * N + hi1 * N + L = A * (2 * Q + bt) := by
        show c * N + hi1 * N + L = _
        omega
      rw [Nat.mul_comm N N]; omega
    exact Nat.lt_of_mul_lt_mul_right this
  rw [hsplit, Nat.mod_eq_of_lt hc, Nat.add_mul]
  omega

/-- The top `n + k` bits of the double-cell number `hi * 2^n + lo`. -/
theorem top_bits {n k hi lo : Nat} (hk : k ≤ n) :
    (hi * 2 ^ n + lo) / 2 ^ (n - k) = hi * 2 ^ k + lo / 2 ^ (n - k) := by
  have e : 2 ^ n = 2 ^ k * 2 ^ (n - k) := by rw [← Nat.pow_add]; congr 1; omega
  rw [e, ← Nat.mul_assoc, Nat.add_comm, Nat.add_mul_div_right _ _ (Nat.two_pow_pos _), Nat.add_comm]

/-- **One step of the restoring division.** With `D_k` the top `n + k` bits of the dividend,
the remainder register holds `D_k % U` and the quotient register `D_k / U`; `L` holds the low word
shifted left by `k`. The step shifts `(R, L)` left by one, subtracts `U` when the shifted value
reaches it (or overflowed, `t = 1`), and appends that bit `cc` to the quotient. -/
theorem umdiv_step {n k U hi lo R Q L : Nat} (hn : 0 < n) (hk : k < n) (hU : 0 < U)
    (hUN : U < 2 ^ n) (hlo : lo < 2 ^ n) (hhi : hi < U)
    (hR : R = (hi * 2 ^ n + lo) / 2 ^ (n - k) % U) (hQ : Q = (hi * 2 ^ n + lo) / 2 ^ (n - k) / U)
    (hL : L = lo * 2 ^ k % 2 ^ n) :
    let N := 2 ^ n
    let H := 2 ^ (n - 1)
    let r2 := ((2 * R) % N + L / H) % N
    let cc := if R / H = 1 ∨ U ≤ r2 then 1 else 0
    (N - (cc * U) % N + r2) % N = (hi * 2 ^ n + lo) / 2 ^ (n - (k + 1)) % U ∧
      ((2 * Q) % N + cc) % N = (hi * 2 ^ n + lo) / 2 ^ (n - (k + 1)) / U := by
  intro N H r2 cc
  have hN : N = 2 * H := two_pow_succ' n hn
  change U < N at hUN
  -- the next dividend bit
  have hbit : L / H = lo / 2 ^ (n - (k + 1)) % 2 := by
    rw [hL]
    have := bit_of_shifted lo k (n - (k + 1))
    rwa [show n - (k + 1) + 1 + k = n by omega, show n - (k + 1) + k = n - 1 by omega] at this
  have hb1 := bit_le_one lo (n - (k + 1))
  rw [top_bits (Nat.le_of_lt hk)] at hR hQ
  rw [top_bits (by omega : k + 1 ≤ n)]
  have hsplit : lo / 2 ^ (n - (k + 1)) = 2 * (lo / 2 ^ (n - k)) + lo / 2 ^ (n - (k + 1)) % 2 := by
    have e : n - (k + 1) + 1 = n - k := by omega
    have := div_pow_succ lo (n - (k + 1)); rw [e] at this; exact this
  generalize hDk : hi * 2 ^ k + lo / 2 ^ (n - k) = Dk at hR hQ
  generalize hbt : lo / 2 ^ (n - (k + 1)) % 2 = bt at hbit hsplit hb1
  have hnext : hi * 2 ^ (k + 1) + lo / 2 ^ (n - (k + 1)) = 2 * Dk + bt := by
    rw [hsplit, ← hDk, Nat.pow_succ, Nat.mul_comm (2 ^ k) 2, Nat.mul_left_comm]; omega
  rw [hnext]
  -- Dk = Q * U + R with R < U
  have hRU : R < U := hR ▸ Nat.mod_lt _ hU
  have hDQR : Dk = U * Q + R := by rw [hR, hQ]; exact (Nat.div_add_mod Dk U).symm
  -- the quotient fits: D_{k+1} / U < N
  have hfit : (2 * Dk + bt) / U < N := by
    have hle : 2 * Dk + bt ≤ hi * 2 ^ n + lo := by
      rw [← hnext]
      have := Nat.div_le_self (hi * 2 ^ n + lo) (2 ^ (n - (k + 1)))
      rwa [top_bits (by omega : k + 1 ≤ n)] at this
    have hD : hi * 2 ^ n + lo < U * 2 ^ n := by
      have : (hi + 1) * 2 ^ n ≤ U * 2 ^ n := Nat.mul_le_mul_right _ hhi
      rw [Nat.add_mul, Nat.one_mul] at this; omega
    apply Nat.div_lt_of_lt_mul; show _ < U * 2 ^ n; omega
  -- V = 2R + bt < 2U
  have hV : 2 * R + bt < 2 * U := by omega
  have hHU : R / H = 1 → U ≤ 2 * R + bt := by
    intro h
    have : H ≤ R := by
      rcases Nat.lt_or_ge R H with hc | hc
      · rw [Nat.div_eq_of_lt hc] at h; cases h
      · exact hc
    omega
  -- the values of the machine step
  have hcc : cc = (if U ≤ 2 * R + bt then 1 else 0) ∧
      r2 = (if R / H = 1 then 2 * R + bt - N else 2 * R + bt) := by
    by_cases ht : H ≤ R
    · have htd : R / H = 1 := by apply Nat.div_eq_of_lt_le <;> omega
      have h2 : (2 * R) % N = 2 * R - N := by
        rw [Nat.mod_eq_sub_mod (by omega), Nat.mod_eq_of_lt (by omega)]
      have hr2 : r2 = 2 * R + bt - N := by
        show ((2 * R) % N + L / H) % N = _
        rw [h2, hbit, Nat.mod_eq_of_lt (by omega)]; omega
      refine ⟨?_, by rw [iteT htd]; exact hr2⟩
      show (if R / H = 1 ∨ U ≤ r2 then 1 else 0) = _
      rw [iteT (.inl htd), iteT (by omega)]
    · have htd : R / H = 0 := Nat.div_eq_of_lt (by omega)
      have hr2 : r2 = 2 * R + bt := by
        show ((2 * R) % N + L / H) % N = _
        rw [Nat.mod_eq_of_lt (by omega : 2 * R < N), hbit, Nat.mod_eq_of_lt (by omega)]
      refine ⟨?_, by rw [iteF (by omega)]; exact hr2⟩
      show (if R / H = 1 ∨ U ≤ r2 then 1 else 0) = _
      rw [hr2]; simp [htd]
  obtain ⟨hcc1, hr2⟩ := hcc
  -- D_{k+1} = U * (2Q + c) + (V - c U)
  by_cases hge : U ≤ 2 * R + bt
  · rw [iteT hge] at hcc1
    have hdiv : (2 * Dk + bt) / U = 2 * Q + 1 ∧ (2 * Dk + bt) % U = 2 * R + bt - U := by
      have e : 2 * Dk + bt = (2 * R + bt - U) + U * (2 * Q + 1) := by
        rw [hDQR, show U * (2 * Q + 1) = 2 * (U * Q) + U by
          rw [Nat.mul_add, Nat.mul_one, Nat.mul_left_comm]]
        omega
      rw [e, Nat.add_mul_div_left _ _ hU, Nat.add_mul_mod_self_left, Nat.div_eq_of_lt (by omega),
        Nat.mod_eq_of_lt (by omega)]
      omega
    rw [hdiv.1, hdiv.2, hcc1]
    refine ⟨?_, ?_⟩
    · rw [Nat.one_mul, Nat.mod_eq_of_lt hUN]
      by_cases ht : R / H = 1
      · rw [iteT ht] at hr2; rw [hr2]
        have hHR : H ≤ R := by
          rcases Nat.lt_or_ge R H with hc | hc
          · rw [Nat.div_eq_of_lt hc] at ht; cases ht
          · exact hc
        have : N - U + (2 * R + bt - N) = 2 * R + bt - U := by omega
        rw [this, Nat.mod_eq_of_lt (by omega)]
      · rw [iteF ht] at hr2; rw [hr2]
        rw [show N - U + (2 * R + bt) = (2 * R + bt - U) + N by omega, Nat.add_mod_right,
          Nat.mod_eq_of_lt (by omega)]
    · have : 2 * Q + 1 < N := hdiv.1 ▸ hfit
      rw [Nat.mod_eq_of_lt (by omega : 2 * Q < N), Nat.mod_eq_of_lt this]
  · rw [iteF hge] at hcc1
    have ht : ¬ R / H = 1 := fun h => hge (hHU h)
    rw [iteF ht] at hr2
    have hdiv : (2 * Dk + bt) / U = 2 * Q ∧ (2 * Dk + bt) % U = 2 * R + bt := by
      have e : 2 * Dk + bt = (2 * R + bt) + U * (2 * Q) := by
        rw [hDQR, show U * (2 * Q) = 2 * (U * Q) by rw [Nat.mul_left_comm]]; omega
      rw [e, Nat.add_mul_div_left _ _ hU, Nat.add_mul_mod_self_left, Nat.div_eq_of_lt (by omega),
        Nat.mod_eq_of_lt (by omega)]
      omega
    rw [hdiv.1, hdiv.2, hcc1, hr2]
    refine ⟨?_, ?_⟩
    · rw [Nat.zero_mul, Nat.zero_mod, Nat.sub_zero,
        show N + (2 * R + bt) = (2 * R + bt) + N by omega, Nat.add_mod_right,
        Nat.mod_eq_of_lt (by omega)]
    · have : 2 * Q < N := hdiv.1 ▸ hfit
      rw [Nat.mod_eq_of_lt this, Nat.add_zero, Nat.mod_eq_of_lt this]

/-! ## `SM/REM` -/

/-- The absolute value of a negative two-digit number `(h - N) * N + l`. -/
theorem natAbs_dd {N h l x y : Nat} (hx : x * N + y + (h * N + l) = N * N) :
    x * N + y = (((h : Int) - (N : Int)) * N + l).natAbs := by
  have e : ((h : Int) - N) * N + l = -((x * N + y : Nat) : Int) := by
    have := congrArg (fun z : Nat => (z : Int)) hx
    push_cast at this
    push_cast; rw [Int.sub_mul]; omega
  rw [e, Int.natAbs_neg, Int.natAbs_natCast]

/-- Truncated division by the absolute values. -/
theorem tdiv_natAbs (D V : Int) :
    D.tdiv V = if (D < 0 ↔ V < 0) then ((D.natAbs / V.natAbs : Nat) : Int)
      else -((D.natAbs / V.natAbs : Nat) : Int) := by
  rcases D with m | m <;> rcases V with k | k <;>
    simp [Int.tdiv, Int.natAbs, Int.negSucc_lt_zero] <;> omega

/-- The truncated remainder takes the dividend's sign. -/
theorem tmod_natAbs (D V : Int) :
    D.tmod V = if D < 0 then -((D.natAbs % V.natAbs : Nat) : Int)
      else ((D.natAbs % V.natAbs : Nat) : Int) := by
  rcases D with m | m <;> rcases V with k | k <;>
    simp [Int.tmod, Int.natAbs, Int.negSucc_lt_zero] <;> omega

/-- The overflow test of `SM/REM`, in terms of the unsigned division of the absolute values. -/
theorem smrem_cond {D V : Int} {N H : Nat} (hN : N = 2 * H) (hH : 0 < H) {sq : Bool}
    (hsq : sq = true ↔ ¬(D < 0 ↔ V < 0)) :
    (V ≠ 0 ∧ -(H : Int) ≤ D.tdiv V ∧ D.tdiv V < H) ↔
      (D.natAbs < V.natAbs * N ∧
        (D.natAbs / V.natAbs < H ∨ (D.natAbs / V.natAbs = H ∧ sq = true))) := by
  rw [tdiv_natAbs]
  have hV : V ≠ 0 ↔ 0 < V.natAbs := by omega
  rw [hV]
  rcases Nat.eq_zero_or_pos V.natAbs with hb | hb
  · simp [hb]
  have key := Nat.div_lt_iff_lt_mul (x := D.natAbs) (y := N) hb
  rw [Nat.mul_comm, ← key]
  generalize D.natAbs / V.natAbs = q
  by_cases hs : (D < 0 ↔ V < 0)
  · have : sq = false := by cases sq <;> simp_all
    rw [iteT hs, this]; simp; omega
  · have : sq = true := hsq.mpr hs
    rw [iteF hs, this]; simp; omega

end DoubleMath
end Forth
end WordDialect
