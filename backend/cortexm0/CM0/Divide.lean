import CM0.Run

/-!
# CM0.Divide

Division on a core without a divide instruction, proved. ARMv6-M has no `udiv`/`sdiv`, so the
lowering divides with the loop `udivCode` (restoring division, one quotient bit per round):

    r2 := 0; r3 := 31
    loop: if (r0 >>> r3) ≥ r1 then { r0 := r0 - (r1 <<< r3); r2 := r2 + (1 <<< r3) }
          if r3 = 0 then exit; r3 := r3 - 1; goto loop

* `udiv_loop`: the invariant. Before the round for bit `i`, `a = r2 · b + r0` and
  `r0 < b · 2^(i+1)` (as natural numbers). A round keeps it for `i - 1`: the test
  `(r0 >>> i) ≥ b` is `r0 ≥ b · 2^i`, and when it holds `b <<< i` and `r2 + 2^i` do not wrap.
  After the round for bit 0, `r0 < b`, so `r2 = a / b`.
* `udiv_seq`: `udivSeq` leaves `a.udiv b` in `r0`.
* `sdiv_seq`: `sdivSeq` leaves `a.sdiv b` in `r0`: it divides the absolute values and negates
  when the signs differ, which is `BitVec.sdiv` case by case on the two sign bits.

Each sequence changes only scratch registers (`r0 r1 r2 r3 r7 r10`) and no memory.
-/

namespace WordDialect
namespace CM0

open Reg

/-- The registers a division sequence may change. -/
def DivScratch (r : Reg) : Prop := r = r0 ∨ r = r1 ∨ r = r2 ∨ r = r3 ∨ r = r7 ∨ r = r10

/-- The registers the loop `udivCode` changes. -/
def LoopScratch (r : Reg) : Prop := r = r0 ∨ r = r2 ∨ r = r3 ∨ r = r7

theorem zero_sle (x : W) : (0#32).sle x = !x.msb := by
  rw [BitVec.sle_eq_decide, BitVec.msb_eq_toInt]
  by_cases h : x.toInt < 0 <;> simp [h] <;> omega

theorem toNat_ofNat_lt {i : Nat} (h : i < 2 ^ 32) : (BitVec.ofNat 32 i).toNat = i := by
  simp [BitVec.toNat_ofNat, Nat.mod_eq_of_lt h]

theorem ofNat_m1 : BitVec.ofInt 32 (-1) = BitVec.ofNat 32 (2 ^ 32 - 1) := by decide

theorem ofNat_pred {i : Nat} (h0 : 0 < i) (h : i < 2 ^ 32) :
    BitVec.ofNat 32 i + BitVec.ofInt 32 (-1) = BitVec.ofNat 32 (i - 1) := by
  rw [ofNat_m1, ← BitVec.ofNat_add]
  apply BitVec.eq_of_toNat_eq
  simp only [BitVec.toNat_ofNat]
  omega

theorem ofNat_eq_zero {i : Nat} (h : i < 2 ^ 32) : BitVec.ofNat 32 i = 0#32 ↔ i = 0 := by
  constructor
  · intro e; have := congrArg BitVec.toNat e; rwa [toNat_ofNat_lt h] at this
  · rintro rfl; rfl

/-- The comparison in a round: `(r >>> i) <u b` exactly when `r < b · 2^i`. -/
theorem ult_shift (r b : W) (i : Nat) :
    (r >>> i).ult b = decide (r.toNat < b.toNat * 2 ^ i) := by
  simp only [BitVec.ult, BitVec.toNat_ushiftRight, Nat.shiftRight_eq_div_pow]
  exact decide_eq_decide.mpr (Nat.div_lt_iff_lt_mul (Nat.two_pow_pos i))

theorem shl_toNat_of_le (b : W) (i : Nat) (h : b.toNat * 2 ^ i < 2 ^ 32) :
    (b <<< i).toNat = b.toNat * 2 ^ i := by
  simp [BitVec.toNat_shiftLeft, Nat.shiftLeft_eq, Nat.mod_eq_of_lt h]

theorem sub_toNat_of_le (r t : W) (h : t.toNat ≤ r.toNat) : (r - t).toNat = r.toNat - t.toNat := by
  rw [BitVec.toNat_sub]
  have := r.isLt; have := t.isLt
  omega

theorem add_toNat_of_lt (q t : W) (h : q.toNat + t.toNat < 2 ^ 32) :
    (q + t).toNat = q.toNat + t.toNat := by
  rw [BitVec.toNat_add, Nat.mod_eq_of_lt h]

section Loop

variable {code : List (Instr Nat)} {q : Nat}

/-- One round, from the top of the loop (index `q + 2`) to the loop test (index `q + 11`), for
bit `i`: it keeps `a = r2 · b + r0` and brings `r0` below `b · 2^i`. -/
theorem udiv_round
    (f2 : code[q + 2]? = some (.movRR r7 r0)) (f3 : code[q + 3]? = some (.lsr r7 r3))
    (f4 : code[q + 4]? = some (.bcc .ult r7 r1 (q + 11))) (f5 : code[q + 5]? = some (.movRR r7 r1))
    (f6 : code[q + 6]? = some (.lsl r7 r3)) (f7 : code[q + 7]? = some (.sub r0 r7))
    (f8 : code[q + 8]? = some (.movImm r7 1#32)) (f9 : code[q + 9]? = some (.lsl r7 r3))
    (f10 : code[q + 10]? = some (.add r2 r7))
    {b : W} (hbpos : 0 < b.toNat) {a : Nat} (ha : a < 2 ^ 32) {i : Nat} (hi : i < 32) {m : M}
    (hpc : m.pc = q + 2) (h1 : m.regs r1 = b) (h3 : m.regs r3 = BitVec.ofNat 32 i)
    (hinv : a = (m.regs r2).toNat * b.toNat + (m.regs r0).toNat)
    (hlt : (m.regs r0).toNat < b.toNat * 2 ^ (i + 1)) :
    ∃ m', RSteps code m m' ∧ m'.pc = q + 11 ∧ m'.regs r1 = b ∧ m'.regs r3 = BitVec.ofNat 32 i ∧
      a = (m'.regs r2).toNat * b.toNat + (m'.regs r0).toNat ∧
      (m'.regs r0).toNat < b.toNat * 2 ^ i ∧ m'.mem = m.mem ∧
      ∀ r, ¬ LoopScratch r → m'.regs r = m.regs r := by
  have hi32 : i % 256 = i := Nat.mod_eq_of_lt (by omega)
  have h3n : (m.regs r3).toNat % 256 = i := by rw [h3, toNat_ofNat_lt (by omega), hi32]
  let R := m.regs r0
  let Q := m.regs r2
  let m1 := m.mov r7 R
  have s2 : step code m = .next m1 := by rw [rstep_of_fetch (by rw [hpc]; exact f2)]; rfl
  let m2 := m1.arith r7 (R >>> i)
  have s3 : step code m1 = .next m2 := by
    have : m1.pc = q + 3 := by simp [m1, M.mov, M.adv, M.setReg, hpc]
    rw [rstep_of_fetch (by rw [this]; exact f3)]
    have e7 : m1.regs r7 = R := by simp [m1, M.mov, M.adv, M.setReg]
    have e3 : (m1.regs r3).toNat % 256 = i := by
      have : m1.regs r3 = m.regs r3 := by simp [m1, M.mov, M.adv, M.setReg]
      rw [this, h3n]
    simp only [exec]; rw [e7, e3]
  have hm2pc : m2.pc = q + 4 := by simp [m2, m1, M.mov, M.adv, M.setReg, M.arith, hpc]
  have hm2r7 : m2.regs r7 = R >>> i := by simp [m2, M.arith, M.setReg]
  have hm2r1 : m2.regs r1 = b := by simp [m2, m1, M.arith, M.mov, M.adv, M.setReg, h1]
  have hfr2 : ∀ r, ¬ LoopScratch r → m2.regs r = m.regs r := by
    intro r hr
    have : r ≠ r7 := fun e => hr (by simp [LoopScratch, e])
    simp [m2, m1, M.arith, M.mov, M.adv, M.setReg, this]
  have hcond : Cond.eval .ult (m2.regs r7) (m2.regs r1) = decide (R.toNat < b.toNat * 2 ^ i) := by
    rw [hm2r7, hm2r1]; exact ult_shift R b i
  by_cases hskip : R.toNat < b.toNat * 2 ^ i
  · -- the bit is 0: skip to the test
    let m3 : M := { m2 with pc := q + 11 }
    have s4 : step code m2 = .next m3 := by
      rw [rstep_of_fetch (by rw [hm2pc]; exact f4)]
      simp only [exec, hcond, hskip, decide_true, ite_true]; rfl
    refine ⟨m3, .cons s2 (.cons s3 (.single s4)), rfl, hm2r1, ?_, ?_, hskip, ?_, ?_⟩
    · show m2.regs r3 = _
      simp [m2, m1, M.arith, M.mov, M.adv, M.setReg, h3]
    · show a = (m2.regs r2).toNat * b.toNat + (m2.regs r0).toNat
      have e2 : m2.regs r2 = Q := by simp [m2, m1, M.arith, M.mov, M.adv, M.setReg, Q]
      have e0 : m2.regs r0 = R := by simp [m2, m1, M.arith, M.mov, M.adv, M.setReg, R]
      rw [e2, e0]; exact hinv
    · simp [m3, m2, m1, M.arith, M.mov, M.adv, M.setReg]
    · intro r hr; exact hfr2 r hr
  · -- the bit is 1: subtract `b <<< i`, add `1 <<< i`
    have hge : b.toNat * 2 ^ i ≤ R.toNat := by omega
    have hRlt := R.isLt
    let m3 := m2.adv
    have s4 : step code m2 = .next m3 := by
      rw [rstep_of_fetch (by rw [hm2pc]; exact f4)]
      simp only [exec, hcond, hskip, decide_false]; rfl
    let m4 := m3.mov r7 b
    have s5 : step code m3 = .next m4 := by
      have : m3.pc = q + 5 := by simp [m3, M.adv, hm2pc]
      rw [rstep_of_fetch (by rw [this]; exact f5)]
      simp [exec, m4, m3, M.adv, hm2r1]
    let m5 := m4.arith r7 (b <<< i)
    have s6 : step code m4 = .next m5 := by
      have : m4.pc = q + 6 := by simp [m4, m3, M.mov, M.adv, M.setReg, hm2pc]
      rw [rstep_of_fetch (by rw [this]; exact f6)]
      have e3 : m4.regs r3 = BitVec.ofNat 32 i := by
        simp [m4, m3, m2, m1, M.mov, M.adv, M.arith, M.setReg, h3]
      have e3n : (m4.regs r3).toNat % 256 = i := by rw [e3, toNat_ofNat_lt (by omega), hi32]
      have e7 : m4.regs r7 = b := by simp [m4, M.mov, M.adv, M.setReg]
      simp only [exec]; rw [e3n, e7]
    let m6 := m5.arith r0 (R - b <<< i)
    have s7 : step code m5 = .next m6 := by
      have : m5.pc = q + 7 := by simp [m5, m4, m3, M.mov, M.adv, M.arith, M.setReg, hm2pc]
      rw [rstep_of_fetch (by rw [this]; exact f7)]
      have e0 : m5.regs r0 = R := by simp [m5, m4, m3, m2, m1, M.mov, M.adv, M.arith, M.setReg, R]
      have e7 : m5.regs r7 = b <<< i := by simp [m5, M.arith, M.setReg]
      simp only [exec]; rw [e0, e7]
    let m7 := m6.mov r7 1#32
    have s8 : step code m6 = .next m7 := by
      have : m6.pc = q + 8 := by simp [m6, m5, m4, m3, M.mov, M.adv, M.arith, M.setReg, hm2pc]
      rw [rstep_of_fetch (by rw [this]; exact f8)]; rfl
    let m8 := m7.arith r7 (1#32 <<< i)
    have s9 : step code m7 = .next m8 := by
      have : m7.pc = q + 9 := by simp [m7, m6, m5, m4, m3, M.mov, M.adv, M.arith, M.setReg, hm2pc]
      rw [rstep_of_fetch (by rw [this]; exact f9)]
      have e3 : m7.regs r3 = BitVec.ofNat 32 i := by
        simp [m7, m6, m5, m4, m3, m2, m1, M.mov, M.adv, M.arith, M.setReg, h3]
      have e3n : (m7.regs r3).toNat % 256 = i := by rw [e3, toNat_ofNat_lt (by omega), hi32]
      have e7 : m7.regs r7 = 1#32 := by simp [m7, M.mov, M.adv, M.setReg]
      simp only [exec]; rw [e3n, e7]
    let m9 := m8.arith r2 (Q + 1#32 <<< i)
    have s10 : step code m8 = .next m9 := by
      have : m8.pc = q + 10 := by
        simp [m8, m7, m6, m5, m4, m3, M.mov, M.adv, M.arith, M.setReg, hm2pc]
      rw [rstep_of_fetch (by rw [this]; exact f10)]
      have e2 : m8.regs r2 = Q := by
        simp [m8, m7, m6, m5, m4, m3, m2, m1, M.mov, M.adv, M.arith, M.setReg, Q]
      have e7 : m8.regs r7 = 1#32 <<< i := by simp [m8, M.arith, M.setReg]
      simp only [exec]; rw [e2, e7]
    have e9r0 : m9.regs r0 = R - b <<< i := by
      simp [m9, m8, m7, m6, M.mov, M.adv, M.arith, M.setReg]
    have e9r2 : m9.regs r2 = Q + 1#32 <<< i := by simp [m9, M.arith, M.setReg]
    -- arithmetic
    have hpow : 2 ^ i < 2 ^ 32 := Nat.pow_lt_pow_right (by omega) hi
    have hbsh : (b <<< i).toNat = b.toNat * 2 ^ i := shl_toNat_of_le b i (by omega)
    have hR' : (R - b <<< i).toNat = R.toNat - b.toNat * 2 ^ i := by
      rw [sub_toNat_of_le R _ (by rw [hbsh]; exact hge), hbsh]
    have h1sh : (1#32 <<< i).toNat = 2 ^ i := by
      rw [shl_toNat_of_le 1#32 i (by simpa using hpow)]; simp
    have hQb : (Q.toNat + 2 ^ i) ≤ (Q.toNat + 2 ^ i) * b.toNat := Nat.le_mul_of_pos_right _ hbpos
    have hdist : (Q.toNat + 2 ^ i) * b.toNat = Q.toNat * b.toNat + b.toNat * 2 ^ i := by
      rw [Nat.add_mul, Nat.mul_comm (2 ^ i)]
    have hinv' : a = Q.toNat * b.toNat + R.toNat := hinv
    have hQ' : (Q + 1#32 <<< i).toNat = Q.toNat + 2 ^ i := by
      rw [add_toNat_of_lt Q _ (by rw [h1sh]; omega), h1sh]
    have hpow2 : 2 ^ (i + 1) = 2 * 2 ^ i := by rw [Nat.pow_succ, Nat.mul_comm]
    have hlt' : R.toNat < b.toNat * 2 ^ (i + 1) := hlt
    rw [hpow2, Nat.mul_left_comm] at hlt'
    refine ⟨m9, .cons s2 (.cons s3 (.cons s4 (.cons s5 (.cons s6 (.cons s7 (.cons s8 (.cons s9
      (.single s10)))))))), ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩
    · simp [m9, m8, m7, m6, m5, m4, m3, M.mov, M.adv, M.arith, M.setReg, hm2pc]
    · simp [m9, m8, m7, m6, m5, m4, m3, M.mov, M.adv, M.arith, M.setReg, hm2r1]
    · simp [m9, m8, m7, m6, m5, m4, m3, m2, m1, M.mov, M.adv, M.arith, M.setReg, h3]
    · rw [e9r2, e9r0, hQ', hR', hdist]; omega
    · rw [e9r0, hR']; omega
    · simp [m9, m8, m7, m6, m5, m4, m3, m2, m1, M.mov, M.adv, M.arith, M.setReg]
    · intro r hr
      have h7 : r ≠ r7 := fun e => hr (by simp [LoopScratch, e])
      have h0 : r ≠ r0 := fun e => hr (by simp [LoopScratch, e])
      have h2 : r ≠ r2 := fun e => hr (by simp [LoopScratch, e])
      simp [m9, m8, m7, m6, m5, m4, m3, m2, m1, M.mov, M.adv, M.arith, M.setReg, h7, h0, h2]

/-- **The loop invariant.** From the top of the round for bit `i`, the loop reaches its exit
with `r2 = a / b`. -/
theorem udiv_loop (hat : RAt code q (udivCode q)) {b : W} (hb : b ≠ 0#32) {a : Nat}
    (ha : a < 2 ^ 32) :
    ∀ i (m : M), i < 32 → m.pc = q + 2 → m.regs r1 = b → m.regs r3 = BitVec.ofNat 32 i →
      a = (m.regs r2).toNat * b.toNat + (m.regs r0).toNat →
      (m.regs r0).toNat < b.toNat * 2 ^ (i + 1) →
      ∃ m', RSteps code m m' ∧ m'.pc = q + 14 ∧ (m'.regs r2).toNat = a / b.toNat ∧
        m'.mem = m.mem ∧ ∀ r, ¬ LoopScratch r → m'.regs r = m.regs r := by
  have hbpos : 0 < b.toNat := by
    rcases Nat.eq_zero_or_pos b.toNat with h | h
    · exact absurd (BitVec.eq_of_toNat_eq (by simpa using h)) hb
    · exact h
  simp only [udivCode, RAt] at hat
  obtain ⟨_, _, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12, f13, _⟩ := hat
  have f2' : code[q + 2]? = some (.movRR r7 r0) := by simpa using f2
  have f3' : code[q + 3]? = some (.lsr r7 r3) := by simpa using f3
  have f4' : code[q + 4]? = some (.bcc .ult r7 r1 (q + 11)) := by simpa using f4
  have f5' : code[q + 5]? = some (.movRR r7 r1) := by simpa using f5
  have f6' : code[q + 6]? = some (.lsl r7 r3) := by simpa using f6
  have f7' : code[q + 7]? = some (.sub r0 r7) := by simpa using f7
  have f8' : code[q + 8]? = some (.movImm r7 1#32) := by simpa using f8
  have f9' : code[q + 9]? = some (.lsl r7 r3) := by simpa using f9
  have f10' : code[q + 10]? = some (.add r2 r7) := by simpa using f10
  have f11' : code[q + 11]? = some (.beqz r3 (q + 14)) := by simpa using f11
  have f12' : code[q + 12]? = some (.addImm r3 (-1)) := by simpa using f12
  have f13' : code[q + 13]? = some (.jmp (q + 2)) := by simpa using f13
  intro i
  induction i with
  | zero =>
    intro m hi hpc h1 h3 hinv hlt
    obtain ⟨m1, hs1, hpc1, _, h31, hinv1, hlt1, hm1, hfr1⟩ :=
      udiv_round f2' f3' f4' f5' f6' f7' f8' f9' f10' hbpos ha hi hpc h1 h3 hinv hlt
    -- `r3 = 0`: leave the loop
    let m2 : M := { m1 with pc := q + 14 }
    have s11 : step code m1 = .next m2 := by
      rw [rstep_of_fetch (by rw [hpc1]; exact f11')]
      simp only [exec, h31]; rfl
    refine ⟨m2, hs1.trans (.single s11), rfl, ?_, hm1, hfr1⟩
    show (m1.regs r2).toNat = a / b.toNat
    have hlt1' : (m1.regs r0).toNat < b.toNat := by simpa using hlt1
    symm
    apply Nat.div_eq_of_lt_le
    · omega
    · rw [Nat.add_mul, Nat.one_mul]; omega
  | succ k ih =>
    intro m hi hpc h1 h3 hinv hlt
    obtain ⟨m1, hs1, hpc1, h11, h31, hinv1, hlt1, hm1, hfr1⟩ :=
      udiv_round f2' f3' f4' f5' f6' f7' f8' f9' f10' hbpos ha hi hpc h1 h3 hinv hlt
    -- `r3 ≠ 0`: count down and go round again
    let m2 := m1.adv
    have hne : ¬ BitVec.ofNat 32 (k + 1) = 0#32 := fun e => by
      have := (ofNat_eq_zero (by omega : k + 1 < 2 ^ 32)).mp e; omega
    have s11 : step code m1 = .next m2 := by
      rw [rstep_of_fetch (by rw [hpc1]; exact f11')]
      simp only [exec, h31, hne, ite_false]; rfl
    let m3 := m2.arith r3 (BitVec.ofNat 32 k)
    have s12 : step code m2 = .next m3 := by
      have : m2.pc = q + 12 := by simp [m2, M.adv, hpc1]
      rw [rstep_of_fetch (by rw [this]; exact f12')]
      have e3 : m2.regs r3 = BitVec.ofNat 32 (k + 1) := by simp [m2, M.adv, h31]
      simp only [exec]; rw [e3, ofNat_pred (by omega) (by omega)]; rfl
    let m4 : M := { m3 with pc := q + 2 }
    have s13 : step code m3 = .next m4 := by
      have : m3.pc = q + 13 := by simp [m3, m2, M.adv, M.arith, hpc1]
      rw [rstep_of_fetch (by rw [this]; exact f13')]; rfl
    have e0 : m4.regs r0 = m1.regs r0 := by simp [m4, m3, m2, M.adv, M.arith, M.setReg]
    have e2 : m4.regs r2 = m1.regs r2 := by simp [m4, m3, m2, M.adv, M.arith, M.setReg]
    obtain ⟨m', hs', hpc', hq', hm', hfr'⟩ := ih m4 (by omega) rfl
      (by simp [m4, m3, m2, M.adv, M.arith, M.setReg, h11])
      (by simp [m4, m3, M.arith, M.setReg]) (by rw [e0, e2]; exact hinv1)
      (by rw [e0]; exact hlt1)
    refine ⟨m', hs1.trans (.cons s11 (.cons s12 (.cons s13 hs'))), hpc', hq', ?_, ?_⟩
    · rw [hm', ← hm1]; simp [m4, m3, m2, M.adv, M.arith, M.setReg]
    · intro r hr
      have h3' : r ≠ r3 := fun e => hr (by simp [LoopScratch, e])
      rw [hfr' r hr, ← hfr1 r hr]; simp [m4, m3, m2, M.adv, M.arith, M.setReg, h3']

/-- The loop alone: `udivCode` at `q`, entered with `r0 = a` and `r1 = b ≠ 0`, ends at `q + 14`
with `r2 = a.udiv b`, having changed only `r0 r2 r3 r7`. -/
theorem udiv_code (hat : RAt code q (udivCode q)) {m : M} (hpc : m.pc = q) {a b : W}
    (h0 : m.regs r0 = a) (h1 : m.regs r1 = b) (hb : b ≠ 0#32) :
    ∃ m', RSteps code m m' ∧ m'.pc = q + 14 ∧ m'.regs r2 = a.udiv b ∧ m'.mem = m.mem ∧
      ∀ r, ¬ LoopScratch r → m'.regs r = m.regs r := by
  have hbpos : 0 < b.toNat := by
    rcases Nat.eq_zero_or_pos b.toNat with h | h
    · exact absurd (BitVec.eq_of_toNat_eq (by simpa using h)) hb
    · exact h
  have hat' := hat
  simp only [udivCode, RAt] at hat'
  obtain ⟨f0, f1, _⟩ := hat'
  let m1 := m.mov r2 0#32
  have s0 : step code m = .next m1 := by rw [rstep_of_fetch (by rw [hpc]; exact f0)]; rfl
  let m2 := m1.mov r3 31#32
  have s1 : step code m1 = .next m2 := by
    have : m1.pc = q + 1 := by simp [m1, M.mov, M.adv, M.setReg, hpc]
    rw [rstep_of_fetch (by rw [this]; exact f1)]; rfl
  have ha := a.isLt
  obtain ⟨m3, hs3, hpc3, hq3, hm3, hfr3⟩ := udiv_loop hat hb (a := a.toNat) ha 31 m2 (by omega)
    (by simp [m2, m1, M.mov, M.adv, M.setReg, hpc]) (by simp [m2, m1, M.mov, M.adv, M.setReg, h1])
    (by simp [m2, M.mov, M.adv, M.setReg])
    (by simp [m2, m1, M.mov, M.adv, M.setReg, h0])
    (by
      have : (m2.regs r0).toNat = a.toNat := by simp [m2, m1, M.mov, M.adv, M.setReg, h0]
      rw [this]
      have : 2 ^ 32 ≤ b.toNat * 2 ^ (31 + 1) := Nat.le_mul_of_pos_left _ hbpos
      omega)
  refine ⟨m3, .cons s0 (.cons s1 hs3), hpc3, ?_, ?_, ?_⟩
  · apply BitVec.eq_of_toNat_eq
    rw [hq3]; exact BitVec.toNat_udiv.symm
  · simp [hm3, m2, m1, M.mov, M.adv, M.setReg]
  · intro r hr
    have h2' : r ≠ r2 := fun e => hr (by simp [LoopScratch, e])
    have h3' : r ≠ r3 := fun e => hr (by simp [LoopScratch, e])
    simp [hfr3 r hr, m2, m1, M.mov, M.adv, M.setReg, h2', h3']

/-- **Unsigned division.** `udivSeq` at `q`, entered with `r0 = a` and `r1 = b ≠ 0`, ends at
`q + 15` with `r0 = a.udiv b`, having changed only scratch registers. -/
theorem udiv_seq (hat : RAt code q (udivSeq q)) {m : M} (hpc : m.pc = q) {a b : W}
    (h0 : m.regs r0 = a) (h1 : m.regs r1 = b) (hb : b ≠ 0#32) :
    ∃ m', RSteps code m m' ∧ m'.pc = q + 15 ∧ m'.regs r0 = a.udiv b ∧ m'.mem = m.mem ∧
      ∀ r, ¬ DivScratch r → m'.regs r = m.regs r := by
  obtain ⟨hatc, hatt⟩ := rat_append.mp hat
  obtain ⟨m3, hs3, hpc3, hq3, hm3, hfr3⟩ := udiv_code hatc hpc h0 h1 hb
  obtain ⟨f14⟩ : code[q + 14]? = some (.movRR r0 r2) ∧ True := by
    simpa [udivCode, RAt] using hatt
  let m4 := m3.mov r0 (m3.regs r2)
  have s14 : step code m3 = .next m4 := by rw [rstep_of_fetch (by rw [hpc3]; exact f14)]; rfl
  refine ⟨m4, hs3.trans (.single s14), ?_, ?_, ?_, ?_⟩
  · simp [m4, M.mov, M.adv, M.setReg, hpc3]
  · simp [m4, M.mov, M.adv, M.setReg, hq3]
  · simp [m4, M.mov, M.adv, M.setReg, hm3]
  · intro r hr
    have h0' : r ≠ r0 := fun e => hr (by simp [DivScratch, e])
    have hl : ¬ LoopScratch r := by
      rintro (e | e | e | e) <;> exact hr (by simp [DivScratch, e])
    simp [m4, M.mov, M.adv, M.setReg, h0', hfr3 r hl]

/-- The absolute value the sequence computes: `neg` when the sign bit is set. -/
def absW (x : W) : W := if x.msb then 0#32 - x else x

theorem absW_ne_zero {x : W} (h : x ≠ 0#32) : absW x ≠ 0#32 := by
  unfold absW; split
  · intro e; apply h
    have : -x = 0#32 := by rw [← BitVec.zero_sub]; exact e
    exact BitVec.neg_eq_zero_iff.mp this
  · exact h

/-- Dividing the absolute values and negating when the signs differ is `BitVec.sdiv`. -/
theorem sdiv_by_abs (a b : W) :
    (if (a ^^^ b).msb then 0#32 - (absW a).udiv (absW b) else (absW a).udiv (absW b)) =
      a.sdiv b := by
  unfold absW BitVec.sdiv
  rw [BitVec.msb_xor]
  cases a.msb <;> cases b.msb <;> simp [BitVec.zero_sub] <;> rfl

/-- **Signed division.** `sdivSeq` at `q`, entered with `r0 = a` and `r1 = b ≠ 0`, ends at
`q + 27` with `r0 = a.sdiv b`, having changed only scratch registers. -/
theorem sdiv_seq (hat : RAt code q (sdivSeq q)) {m : M} (hpc : m.pc = q) {a b : W}
    (h0 : m.regs r0 = a) (h1 : m.regs r1 = b) (hb : b ≠ 0#32) :
    ∃ m', RSteps code m m' ∧ m'.pc = q + 27 ∧ m'.regs r0 = a.sdiv b ∧ m'.mem = m.mem ∧
      ∀ r, ¬ DivScratch r → m'.regs r = m.regs r := by
  obtain ⟨hpre, hrest⟩ := rat_append.mp (by simpa [sdivSeq, List.append_assoc] using hat :
    RAt code q ([.movRR r3 r0, .xor r3 r1, .movRR r10 r3, .movImm r2 0#32,
      .bcc .sge r0 r2 (q + 6), .neg r0, .bcc .sge r1 r2 (q + 8), .neg r1] ++
      (udivCode (q + 8) ++ [.movRR r3 r10, .movImm r7 0#32, .bcc .sge r3 r7 (q + 26), .neg r2,
        .movRR r0 r2])))
  obtain ⟨hloop, hpost⟩ := rat_append.mp hrest
  simp only [RAt, List.length_cons, List.length_nil] at hpre hpost
  obtain ⟨f0, f1, f2, f3, f4, f5, f6, f7, _⟩ := hpre
  have hlen : (udivCode (q + 8)).length = 14 := by simp [udivCode]
  rw [hlen] at hpost
  obtain ⟨g0, g1, g2, g3, g4, _⟩ := hpost
  -- the sign of the result, kept in `r10`
  let m1 := m.mov r3 a
  have s0 : step code m = .next m1 := by
    rw [rstep_of_fetch (by rw [hpc]; exact f0)]; simp only [exec, h0]; rfl
  let m2 := m1.arith r3 (a ^^^ b)
  have s1 : step code m1 = .next m2 := by
    have : m1.pc = q + 1 := by simp [m1, M.mov, M.adv, M.setReg, hpc]
    rw [rstep_of_fetch (by simpa [this] using f1)]
    have e3 : m1.regs r3 = a := by simp [m1, M.mov, M.adv, M.setReg]
    have e1 : m1.regs r1 = b := by simp [m1, M.mov, M.adv, M.setReg, h1]
    simp only [exec]; rw [e3, e1]
  let m3 := m2.mov r10 (a ^^^ b)
  have s2 : step code m2 = .next m3 := by
    have : m2.pc = q + 2 := by simp [m2, m1, M.mov, M.adv, M.setReg, M.arith, hpc]
    rw [rstep_of_fetch (by simpa [this] using f2)]
    have e3 : m2.regs r3 = a ^^^ b := by simp [m2, M.arith, M.setReg]
    simp only [exec]; rw [e3]
  let m4 := m3.mov r2 0#32
  have s3 : step code m3 = .next m4 := by
    have : m3.pc = q + 3 := by simp [m3, m2, m1, M.mov, M.adv, M.setReg, M.arith, hpc]
    rw [rstep_of_fetch (by simpa [this] using f3)]; rfl
  have hm4pc : m4.pc = q + 4 := by simp [m4, m3, m2, m1, M.mov, M.adv, M.setReg, M.arith, hpc]
  have hm4r0 : m4.regs r0 = a := by simp [m4, m3, m2, m1, M.mov, M.adv, M.setReg, M.arith, h0]
  have hm4r1 : m4.regs r1 = b := by simp [m4, m3, m2, m1, M.mov, M.adv, M.setReg, M.arith, h1]
  have hm4r2 : m4.regs r2 = 0#32 := by simp [m4, M.mov, M.adv, M.setReg]
  -- `r0 := |a|`
  obtain ⟨m6, hs6, hpc6, h6r0, h6o⟩ : ∃ m6, RSteps code m4 m6 ∧ m6.pc = q + 6 ∧
      m6.regs r0 = absW a ∧ (∀ r, r ≠ r0 → m6.regs r = m4.regs r) ∧ m6.mem = m4.mem := by
    by_cases ha : a.msb
    · let m5 := m4.adv
      have s4 : step code m4 = .next m5 := by
        rw [rstep_of_fetch (by simpa [hm4pc] using f4)]
        simp [exec, Cond.eval, hm4r0, hm4r2, zero_sle, ha, m5]
      let m6 := m5.arith r0 (0#32 - a)
      have s5 : step code m5 = .next m6 := by
        have : m5.pc = q + 5 := by simp [m5, M.adv, hm4pc]
        rw [rstep_of_fetch (by simpa [this] using f5)]
        have e0 : m5.regs r0 = a := by simp [m5, M.adv, hm4r0]
        simp only [exec]; rw [e0]
      refine ⟨m6, .cons s4 (.single s5), by simp [m6, m5, M.arith, M.adv, hm4pc], ?_, ?_, ?_⟩
      · simp [m6, M.arith, M.setReg, absW, ha]
      · intro r hr; simp [m6, m5, M.arith, M.adv, M.setReg, hr]
      · simp [m6, m5, M.arith, M.adv, M.setReg]
    · let m6 : M := { m4 with pc := q + 6 }
      have s4 : step code m4 = .next m6 := by
        rw [rstep_of_fetch (by simpa [hm4pc] using f4)]
        simp [exec, Cond.eval, hm4r0, hm4r2, zero_sle, ha, m6]
      exact ⟨m6, .single s4, rfl, by simp [m6, hm4r0, absW, ha], fun r _ => rfl, rfl⟩
  -- `r1 := |b|`
  have hm6r1 : m6.regs r1 = b := by rw [h6o.1 r1 (by decide), hm4r1]
  have hm6r2 : m6.regs r2 = 0#32 := by rw [h6o.1 r2 (by decide), hm4r2]
  obtain ⟨m8, hs8, hpc8, h8r1, h8o, h8m⟩ : ∃ m8, RSteps code m6 m8 ∧ m8.pc = q + 8 ∧
      m8.regs r1 = absW b ∧ (∀ r, r ≠ r1 → m8.regs r = m6.regs r) ∧ m8.mem = m6.mem := by
    by_cases hbm : b.msb
    · let m7 := m6.adv
      have s6 : step code m6 = .next m7 := by
        rw [rstep_of_fetch (by simpa [hpc6] using f6)]
        simp [exec, Cond.eval, hm6r1, hm6r2, zero_sle, hbm, m7]
      let m8 := m7.arith r1 (0#32 - b)
      have s7 : step code m7 = .next m8 := by
        have : m7.pc = q + 7 := by simp [m7, M.adv, hpc6]
        rw [rstep_of_fetch (by simpa [this] using f7)]
        have e1 : m7.regs r1 = b := by simp [m7, M.adv, hm6r1]
        simp only [exec]; rw [e1]
      refine ⟨m8, .cons s6 (.single s7), by simp [m8, m7, M.arith, M.adv, hpc6], ?_, ?_, ?_⟩
      · simp [m8, M.arith, M.setReg, absW, hbm]
      · intro r hr; simp [m8, m7, M.arith, M.adv, M.setReg, hr]
      · simp [m8, m7, M.arith, M.adv, M.setReg]
    · let m8 : M := { m6 with pc := q + 8 }
      have s6 : step code m6 = .next m8 := by
        rw [rstep_of_fetch (by simpa [hpc6] using f6)]
        simp [exec, Cond.eval, hm6r1, hm6r2, zero_sle, hbm, m8]
      exact ⟨m8, .single s6, rfl, by simp [m8, hm6r1, absW, hbm], fun r _ => rfl, rfl⟩
  have h8r0 : m8.regs r0 = absW a := by rw [h8o r0 (by decide), h6r0]
  -- divide the absolute values
  obtain ⟨m9, hs9, hpc9, h9r2, h9m, h9fr⟩ :=
    udiv_code hloop hpc8 h8r0 h8r1 (absW_ne_zero hb)
  have h9r10 : m9.regs r10 = a ^^^ b := by
    rw [h9fr r10 (by simp [LoopScratch]), h8o r10 (by decide), h6o.1 r10 (by decide)]
    simp [m4, m3, M.mov, M.adv, M.setReg]
  -- negate when the signs differ
  let Q := (absW a).udiv (absW b)
  let m10 := m9.mov r3 (a ^^^ b)
  have s22 : step code m9 = .next m10 := by
    rw [rstep_of_fetch (by simpa [hpc9] using g0)]; simp only [exec, h9r10]; rfl
  let m11 := m10.mov r7 0#32
  have s23 : step code m10 = .next m11 := by
    have : m10.pc = q + 8 + 14 + 1 := by simp [m10, M.mov, M.adv, M.setReg, hpc9]
    rw [rstep_of_fetch (by simpa [this] using g1)]; rfl
  have hm11pc : m11.pc = q + 8 + 14 + 2 := by simp [m11, m10, M.mov, M.adv, M.setReg, hpc9]
  have hm11r3 : m11.regs r3 = a ^^^ b := by simp [m11, m10, M.mov, M.adv, M.setReg]
  have hm11r7 : m11.regs r7 = 0#32 := by simp [m11, M.mov, M.adv, M.setReg]
  have hm11r2 : m11.regs r2 = Q := by simp [m11, m10, M.mov, M.adv, M.setReg, h9r2, Q]
  obtain ⟨m13, hs13, hpc13, h13r2, h13o, h13m⟩ : ∃ m13, RSteps code m11 m13 ∧ m13.pc = q + 26 ∧
      m13.regs r2 = (if (a ^^^ b).msb then 0#32 - Q else Q) ∧
      (∀ r, r ≠ r2 → m13.regs r = m11.regs r) ∧ m13.mem = m11.mem := by
    by_cases hs : (a ^^^ b).msb
    · let m12 := m11.adv
      have s24 : step code m11 = .next m12 := by
        rw [rstep_of_fetch (by simpa [hm11pc] using g2)]
        simp [exec, Cond.eval, hm11r3, hm11r7, zero_sle, hs, m12]
      let m13 := m12.arith r2 (0#32 - Q)
      have s25 : step code m12 = .next m13 := by
        have : m12.pc = q + 8 + 14 + 3 := by simp [m12, M.adv, hm11pc]
        rw [rstep_of_fetch (by simpa [this] using g3)]
        have e2 : m12.regs r2 = Q := by simp [m12, M.adv, hm11r2]
        simp only [exec]; rw [e2]
      refine ⟨m13, .cons s24 (.single s25), by simp [m13, m12, M.arith, M.adv, hm11pc],
        ?_, ?_, ?_⟩
      · simp [m13, M.arith, M.setReg, hs]
      · intro r hr; simp [m13, m12, M.arith, M.adv, M.setReg, hr]
      · simp [m13, m12, M.arith, M.adv, M.setReg]
    · let m13 : M := { m11 with pc := q + 26 }
      have s24 : step code m11 = .next m13 := by
        rw [rstep_of_fetch (by simpa [hm11pc] using g2)]
        simp [exec, Cond.eval, hm11r3, hm11r7, zero_sle, hs, m13]
      exact ⟨m13, .single s24, rfl, by simp [m13, hm11r2, hs], fun r _ => rfl, rfl⟩
  let m14 := m13.mov r0 (m13.regs r2)
  have s26 : step code m13 = .next m14 := by
    rw [rstep_of_fetch (by simpa [hpc13] using g4)]; rfl
  refine ⟨m14, .cons s0 (.cons s1 (.cons s2 (.cons s3 (hs6.trans (hs8.trans (hs9.trans
    (.cons s22 (.cons s23 (hs13.trans (.single s26)))))))))), ?_, ?_, ?_, ?_⟩
  · simp [m14, M.mov, M.adv, M.setReg, hpc13]
  · simp only [m14, M.mov, M.adv, M.setReg, ite_true, h13r2]; exact sdiv_by_abs a b
  · simp [m14, M.mov, M.adv, M.setReg, h13m, m11, m10, h9m, h8m, h6o.2, m4, m3, m2, m1, M.arith]
  · intro r hr
    have hl : ¬ LoopScratch r := by
      rintro (e | e | e | e) <;> exact hr (by simp [DivScratch, e])
    have h0' : r ≠ r0 := fun e => hr (by simp [DivScratch, e])
    have h1' : r ≠ r1 := fun e => hr (by simp [DivScratch, e])
    have h2' : r ≠ r2 := fun e => hr (by simp [DivScratch, e])
    have h3' : r ≠ r3 := fun e => hr (by simp [DivScratch, e])
    have h7' : r ≠ r7 := fun e => hr (by simp [DivScratch, e])
    have h10' : r ≠ r10 := fun e => hr (by simp [DivScratch, e])
    simp only [m14, M.mov, M.adv, M.setReg, h0', ite_false]
    rw [h13o r h2', show m11.regs r = m9.regs r by simp [m11, m10, M.mov, M.adv, M.setReg, h3', h7'],
      h9fr r hl, h8o r h1', h6o.1 r h0']
    simp [m4, m3, m2, m1, M.mov, M.adv, M.setReg, M.arith, h2', h10', h3']

end Loop

end CM0
end WordDialect
