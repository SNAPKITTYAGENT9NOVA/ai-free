import Forth.OpCorrect
import Forth.DoubleMath

/-!
# Forth.DoubleCorrect

The code of `Forth.Double` computes `Op.sem` for `UM*`, `UM/MOD`, `M*`, `SM/REM`, `*/MOD` and
`*/`, and `opFrag_run`: every operation's code (straight-line or loop) realizes its semantics.
The loop proofs use `countedLoop_run'` with an invariant on the registers, whose step is
`DoubleMath.umstar_step` / `DoubleMath.umdiv_step`; at width `0` the loop runs no rounds
(`countedLoop_zero`). `SM/REM` reduces to `UM/MOD` on absolute values (`dneg_toNat`,
`abs_toNat`, `DoubleMath.smrem_cond`), and `*/MOD` to `SM/REM` because `M*`'s two words are the
exact product (`mstar_split`).
-/

namespace WordDialect
namespace Forth

open IR

/-! ## Word-level facts -/

section Words
variable {n : Nat}

theorem shl_one_toNat (x : Word n) : (Word.shl x 1#n).toNat = (2 * x.toNat) % 2 ^ n := by
  rcases n with _ | _ | n
  · simp [Word.shl, Nat.mod_one]
  · have : x.toNat < 2 := x.isLt
    simp [Word.shl] <;> omega
  · have h1 : (1#(n + 2)).toNat = 1 := by
      simp only [BitVec.toNat_ofNat]; exact Nat.mod_eq_of_lt (Nat.one_lt_two_pow (by omega))
    simp only [Word.shl, h1, show 1 < n + 2 by omega, ite_true, BitVec.toNat_shiftLeft,
      Nat.shiftLeft_eq, Nat.pow_one, Nat.mul_comm]

theorem shr_top_toNat (x : Word n) :
    (Word.shr x (BitVec.ofNat n (n - 1))).toNat = x.toNat / 2 ^ (n - 1) := by
  have : (BitVec.ofNat n (n - 1)).toNat = n - 1 := by
    have h2 : n < 2 ^ n := Nat.lt_two_pow_self
    rw [BitVec.toNat_ofNat]; exact Nat.mod_eq_of_lt (by omega)
  simp only [Word.shr, this, BitVec.toNat_ushiftRight, Nat.shiftRight_eq_div_pow]

theorem ofBool_toNat (hn : 0 < n) (b : Bool) :
    (Word.ofBool (n := n) b).toNat = if b then 1 else 0 := by
  cases b
  · simp [Word.ofBool]
  · simp [Word.ofBool]; omega

theorem word_eq_of_width_zero (x y : Word 0) : x = y :=
  BitVec.eq_of_toNat_eq (by have := x.isLt; have := y.isLt; simp at *; omega)

theorem ofNat_eq_of_toNat {x : Word n} {v : Nat} (h : x.toNat = v) : BitVec.ofNat n v = x := by
  apply BitVec.eq_of_toNat_eq
  rw [BitVec.toNat_ofNat, ← h, Nat.mod_eq_of_lt x.isLt]

end Words

/-! ## A loop of no rounds -/

theorem countedLoop_zero {n : Nat} {p : Prog n} {b r : Nat} {body : Frag n}
    (hat : At p b ((countedLoop r 0 body).emit b)) (s : State n) (hpc : s.pc = b) :
    ∃ s', Steps p s s' ∧ s'.pc = b + body.size + 12 ∧ s'.dstack = s.dstack ∧
      s'.astack = s.astack ∧ s'.rstack = s.rstack ∧ s'.mem = s.mem ∧
      (∀ j, j ≠ r → s'.regs j = s.regs j) := by
  have hat' := Frag.seq_at (by simpa [countedLoop] using hat)
  have hinit : At p b (initCode r) := by simpa [Frag.ofCode] using hat'.1
  have hw : At p (b + 2) ((Frag.whileLoop (Frag.ofCode (condCode r 0))
      (body.seq (Frag.ofCode (incCode r)))).emit (b + 2)) := by
    simpa [Frag.ofCode, initCode] using hat'.2
  obtain ⟨hc_at, _⟩ := while_decode hw
  obtain ⟨hst0, hpc0⟩ := execSeq_steps (initCode_straight r) (by rw [hpc]; exact hinit)
    (initCode_run r s)
  let s1 : State n := { s with pc := s.pc + 2, regs := State.setReg s.regs r 0#n }
  have hx := condCode_run r 0 s1
  have hult : (s1.regs r).ult (BitVec.ofNat n 0) = false := by simp [BitVec.ult]
  rw [hult] at hx
  obtain ⟨hst1, hpc1⟩ := execSeq_steps (condCode_straight r 0)
    (by show At p (s.pc + 2) _; rw [hpc]; simpa [Frag.ofCode] using hc_at) hx
  let s2 : State n := { s1 with pc := s1.pc + 3, dstack := Word.ofBool false :: s1.dstack }
  have h1 := while_exit_rule hw (s1 := s2) (by simp [s2, s1, hpc, Frag.ofCode, condCode]) rfl
    (by simp [Word.isTrue, Word.ofBool])
  refine ⟨_, hst0.trans (hst1.trans h1), ?_, rfl, rfl, rfl, rfl, ?_⟩
  · simp [Frag.seq_size, condCode, incCode, Frag.ofCode]; omega
  · intro j hj; simp [s2, s1, State.setReg, hj]

/-! ## `UM*` -/

section UmStar
variable {n : Nat}

theorem umStarPre_straight : ∀ i ∈ (umStarPre : List (Instr n)), i.isStraight = true := by
  simp [umStarPre, Instr.isStraight]
theorem umStarBody_straight : ∀ i ∈ (umStarBody : List (Instr n)), i.isStraight = true := by
  simp [umStarBody, Instr.isStraight]
theorem umStarPost_straight : ∀ i ∈ (umStarPost : List (Instr n)), i.isStraight = true := by
  simp [umStarPost, Instr.isStraight]

/-- What one round of `UM*` does to the registers. -/
theorem umStarBody_run (s : State n) :
    let hi1 := Word.shl (s.regs 3) 1#n + Word.shr (s.regs 2) (BitVec.ofNat n (n - 1))
    let lo1 := Word.shl (s.regs 2) 1#n
    let X := s.regs 0 * Word.shr (s.regs 1) (BitVec.ofNat n (n - 1))
    let L := X + lo1
    ∃ s', execSeq umStarBody s = .next s' ∧ s'.pc = s.pc + 31 ∧ s'.dstack = s.dstack ∧
      s'.mem = s.mem ∧ s'.astack = s.astack ∧ s'.rstack = s.rstack ∧
      s'.regs 0 = s.regs 0 ∧ s'.regs 4 = s.regs 4 ∧ s'.regs 1 = Word.shl (s.regs 1) 1#n ∧
      s'.regs 2 = L ∧ s'.regs 3 = Word.ofBool (L.ult X) + hi1 ∧ (∀ j, 5 ≤ j → s'.regs j = s.regs j) := by
  intro hi1 lo1 X L
  obtain ⟨pc, d, rs, as, regs, mem⟩ := s
  simp only [umStarBody, execSeq, exec, State.fall, Cond.eval]
  refine ⟨_, rfl, ?_⟩
  refine ⟨by simp [Nat.add_assoc], rfl, rfl, rfl, rfl, by simp [State.setReg],
    by simp [State.setReg], by simp [State.setReg], by simp [State.setReg, X, L, lo1],
    by simp [State.setReg, hi1, lo1, X, L], ?_⟩
  intro j hj
  simp [State.setReg, show j ≠ 1 by omega, show j ≠ 2 by omega,
    show j ≠ 3 by omega]

theorem umStarPre_run (s : State n) {a b : Word n} {d : List (Word n)}
    (hd : s.dstack = b :: a :: d) :
    ∃ s', execSeq umStarPre s = .next s' ∧ s'.pc = s.pc + 6 ∧ s'.dstack = d ∧
      s'.mem = s.mem ∧ s'.astack = s.astack ∧ s'.rstack = s.rstack ∧
      s'.regs 0 = a ∧ s'.regs 1 = b ∧ s'.regs 2 = 0#n ∧ s'.regs 3 = 0#n ∧ (∀ j, 5 ≤ j → s'.regs j = s.regs j) := by
  obtain ⟨pc, d', rs, as, regs, mem⟩ := s
  simp only at hd; subst hd
  simp only [umStarPre, execSeq, exec, State.fall]
  refine ⟨_, rfl, ?_⟩
  refine ⟨by simp [Nat.add_assoc], rfl, rfl, rfl, rfl, by simp [State.setReg],
    by simp [State.setReg], by simp [State.setReg], by simp [State.setReg], ?_⟩
  intro j hj
  simp [State.setReg, show j ≠ 0 by omega, show j ≠ 1 by omega, show j ≠ 2 by omega,
    show j ≠ 3 by omega]

theorem umStarPre_under (s : State n) (h : s.dstack.length < 2) :
    execSeq umStarPre s = .trapped .stackUnderflow := by
  obtain ⟨pc, d, rs, as, regs, mem⟩ := s
  rcases d with _ | ⟨x, _ | ⟨y, d⟩⟩
  · simp [umStarPre, execSeq, exec]
  · simp [umStarPre, execSeq, exec]
  · simp at h; omega

/-- The `UM*` loop invariant after `k` rounds. -/
def umStarInv (a b : Word n) (k : Nat) (s : State n) : Prop :=
  s.regs 0 = a ∧ (s.regs 1).toNat = b.toNat * 2 ^ k % 2 ^ n ∧
    (s.regs 3).toNat * 2 ^ n + (s.regs 2).toNat = a.toNat * (b.toNat / 2 ^ (n - k))

theorem umStar_round (hn : 0 < n) {a b : Word n} {k : Nat} (hk : k < n) {s s' : State n}
    (hI : umStarInv a b k s)
    (h0 : s'.regs 0 = s.regs 0) (h1 : s'.regs 1 = Word.shl (s.regs 1) 1#n)
    (h2 : s'.regs 2 = s.regs 0 * Word.shr (s.regs 1) (BitVec.ofNat n (n - 1)) +
      Word.shl (s.regs 2) 1#n)
    (h3 : s'.regs 3 = Word.ofBool ((s.regs 0 * Word.shr (s.regs 1) (BitVec.ofNat n (n - 1)) +
        Word.shl (s.regs 2) 1#n).ult (s.regs 0 * Word.shr (s.regs 1) (BitVec.ofNat n (n - 1)))) +
      (Word.shl (s.regs 3) 1#n + Word.shr (s.regs 2) (BitVec.ofNat n (n - 1)))) :
    umStarInv a b (k + 1) s' := by
  obtain ⟨ha, hb, hacc⟩ := hI
  refine ⟨h0.trans ha, ?_, ?_⟩
  · rw [h1, shl_one_toNat, hb, Nat.mul_mod, Nat.mod_mod, ← Nat.mul_mod, Nat.pow_succ,
      Nat.mul_comm (2 ^ k) 2, Nat.mul_left_comm]
  · have step := DoubleMath.umstar_step hn hk a.isLt b.isLt (s.regs 2).isLt hacc
    rw [h3, h2]
    simp only [BitVec.toNat_add, BitVec.toNat_mul, ofBool_toNat hn, BitVec.ult,
      decide_eq_true_eq, shl_one_toNat, shr_top_toNat, hb, ha] at step ⊢
    exact step

/-- **`UM*` computes the full product.** -/
theorem umStar_ok {p : Prog n} {base : Nat} (hat : At p base ((umStarFrag : Frag n).emit base))
    (s : State n) (hpc : s.pc = base) {a b : Word n} {d : List (Word n)}
    (hd : s.dstack = b :: a :: d) :
    ∃ s', Steps p s s' ∧ s'.pc = base + 51 ∧ s'.rstack = s.rstack ∧
      s'.dstack = BitVec.ofNat n (a.toNat * b.toNat / 2 ^ n) :: BitVec.ofNat n (a.toNat * b.toNat) :: d ∧
      s'.mem = s.mem ∧ s'.astack = s.astack ∧ (∀ j, 5 ≤ j → s'.regs j = s.regs j) := by
  obtain ⟨hpre, hrest⟩ := Frag.seq_at (by simpa [umStarFrag] using hat)
  obtain ⟨hloop, hpost⟩ := Frag.seq_at hrest
  rw [countedLoop_size, Frag.ofCode_size, Frag.ofCode_size] at hpost
  simp only [Frag.ofCode, umStarPre, umStarBody, List.length_cons, List.length_nil] at hpre hloop hpost
  obtain ⟨s1, hx1, hpc1, hd1, hm1, ha1, hr1, hA, hB, hLo, hHi, hK1⟩ := umStarPre_run s hd
  obtain ⟨hst1, -⟩ := execSeq_steps umStarPre_straight (by rw [hpc]; exact hpre) hx1
  -- after the loop: a state with the product in registers 3 (hi) and 2 (lo)
  have hloop' : ∃ s2, Steps p s1 s2 ∧ s2.pc = base + 6 + 31 + 12 ∧ s2.dstack = d ∧
      s2.astack = s.astack ∧ s2.rstack = s.rstack ∧ s2.mem = s.mem ∧
      (∀ j, 5 ≤ j → s2.regs j = s.regs j) ∧
      (s2.regs 3).toNat * 2 ^ n + (s2.regs 2).toNat = a.toNat * b.toNat := by
    rcases Nat.eq_zero_or_pos n with hn | hn
    · subst hn
      obtain ⟨s2, hs2, hpc2, hd2, ha2, hr2, hm2, hK2⟩ :=
        countedLoop_zero hloop s1 (by rw [hpc1, hpc])
      refine ⟨s2, hs2, by simpa [Frag.ofCode, umStarBody] using hpc2, by rw [hd2, hd1],
        by rw [ha2, ha1], by rw [hr2, hr1], by rw [hm2, hm1],
        fun j hj => (hK2 j (by omega)).trans (hK1 j hj), ?_⟩
      rw [word_eq_of_width_zero a 0#0, word_eq_of_width_zero b 0#0,
        word_eq_of_width_zero (s2.regs 3) 0#0, word_eq_of_width_zero (s2.regs 2) 0#0]; rfl
    · obtain ⟨s2, hs2, hpc2, -, hd2, ha2, hr2, hI⟩ := countedLoop_run' (r := 4) (N := n)
        (body := Frag.ofCode umStarBody) hn Nat.lt_two_pow_self hloop
        (fun k s => umStarInv a b k s ∧ s.mem = s1.mem ∧ ∀ j, 5 ≤ j → s.regs j = s1.regs j)
        (by
          intro k s s' hI hm _ _ _ hregs
          obtain ⟨⟨h0, h1, h2⟩, hm0, hK⟩ := hI
          refine ⟨⟨by rw [hregs 0 (by decide)]; exact h0, by rw [hregs 1 (by decide)]; exact h1, ?_⟩,
            hm.trans hm0, fun j hj => (hregs j (by omega)).trans (hK j hj)⟩
          rw [hregs 2 (by decide), hregs 3 (by decide)]; exact h2)
        (by
          intro k s hk hI hpcs hrk
          have hbody := countedLoop_body_at hloop
          obtain ⟨s', hx, hpc', hd', hm', ha', hr', h0, h4, h1, h2, h3, hK'⟩ := umStarBody_run s
          obtain ⟨hst, -⟩ := execSeq_steps umStarBody_straight
            (by rw [hpcs]; simpa [Frag.ofCode, umStarBody] using hbody) hx
          refine ⟨s', hst, by rw [hpc', hpcs]; simp [Frag.ofCode, umStarBody], by rw [h4, hrk],
            hd', ha', hr', umStar_round hn hk hI.1 h0 h1 h2 h3, hm'.trans hI.2.1,
            fun j hj => (hK' j hj).trans (hI.2.2 j hj)⟩)
        s1 (by rw [hpc1, hpc])
        ⟨⟨hA, by rw [hB]; simp [Nat.mod_eq_of_lt b.isLt], by
          rw [hHi, hLo]; simp [Nat.div_eq_of_lt b.isLt]⟩, rfl, fun _ _ => rfl⟩
      refine ⟨s2, hs2, by rw [hpc2]; simp [Frag.ofCode, umStarBody], by rw [hd2, hd1],
        by rw [ha2, ha1], by rw [hr2, hr1], by rw [hI.2.1, hm1],
        fun j hj => (hI.2.2 j hj).trans (hK1 j hj), ?_⟩
      have := hI.1.2.2; simpa using this
  obtain ⟨s2, hs2, hpc2, hd2, ha2, hr2, hm2, hK2, hprod⟩ := hloop'
  have hx3 : execSeq umStarPost s2 =
      .next { s2 with pc := s2.pc + 2, dstack := s2.regs 3 :: s2.regs 2 :: s2.dstack } := by
    simp [umStarPost, execSeq, exec, State.fall, Nat.add_assoc]
  obtain ⟨hst3, -⟩ := execSeq_steps umStarPost_straight
    (by rw [hpc2]; simpa [Nat.add_assoc] using hpost) hx3
  have hlo := (s2.regs 2).isLt
  have hhi : a.toNat * b.toNat / 2 ^ n = (s2.regs 3).toNat := by
    rw [← hprod, Nat.add_comm, Nat.add_mul_div_right _ _ (Nat.two_pow_pos n),
      Nat.div_eq_of_lt hlo, Nat.zero_add]
  have hlow : a.toNat * b.toNat % 2 ^ n = (s2.regs 2).toNat := by
    rw [← hprod, Nat.add_comm, Nat.add_mul_mod_self_right, Nat.mod_eq_of_lt hlo]
  refine ⟨_, hst1.trans (hs2.trans hst3), by simp [hpc2], by simp [hr2], ?_, by simp [hm2],
    by simp [ha2], fun j hj => hK2 j hj⟩
  simp only [hd2]
  congr 1
  · exact (ofNat_eq_of_toNat hhi.symm).symm
  · congr 1
    apply BitVec.eq_of_toNat_eq
    rw [BitVec.toNat_ofNat, hlow]

end UmStar

/-! ## `UM/MOD` -/

section UmDiv
variable {n : Nat}

theorem umDivPre_straight : ∀ i ∈ (umDivPre : List (Instr n)), i.isStraight = true := by
  simp [umDivPre, Instr.isStraight]
theorem umDivBody_straight : ∀ i ∈ (umDivBody : List (Instr n)), i.isStraight = true := by
  simp [umDivBody, Instr.isStraight]
theorem umDivPost_straight : ∀ i ∈ (umDivPost : List (Instr n)), i.isStraight = true := by
  simp [umDivPost, Instr.isStraight]

theorem umDivPre_run (s : State n) {u hi lo : Word n} {d : List (Word n)}
    (hd : s.dstack = u :: hi :: lo :: d) (hlt : hi.toNat < u.toNat) :
    ∃ s', execSeq umDivPre s = .next s' ∧ s'.pc = s.pc + 11 ∧ s'.dstack = d ∧
      s'.mem = s.mem ∧ s'.astack = s.astack ∧ s'.rstack = s.rstack ∧
      s'.regs 0 = u ∧ s'.regs 1 = hi ∧ s'.regs 2 = lo ∧ s'.regs 3 = 0#n ∧ (∀ j, 5 ≤ j → s'.regs j = s.regs j) := by
  have hn : 0 < n := by
    rcases Nat.eq_zero_or_pos n with h | h
    · subst h; have := u.isLt; simp at this; omega
    · exact h
  have hult : hi.ult u = true := by simp [BitVec.ult, hlt]
  have h10 : (1#n = 0#n) = False := by
    simp only [eq_iff_iff, iff_false]; intro h
    have := congrArg BitVec.toNat h; simp at this; omega
  obtain ⟨pc, d', rs, as, regs, mem⟩ := s
  simp only at hd; subst hd
  simp only [umDivPre, execSeq, exec, State.fall, Cond.eval]
  simp [State.setReg, hult, Word.ofBool, h10, Nat.add_assoc]
  intro j hj
  simp [show j ≠ 0 by omega, show j ≠ 1 by omega, show j ≠ 2 by omega, show j ≠ 3 by omega]

theorem umDivPre_trap (s : State n) {u hi lo : Word n} {d : List (Word n)}
    (hd : s.dstack = u :: hi :: lo :: d) (hge : ¬hi.toNat < u.toNat) :
    execSeq umDivPre s = .trapped .divideByZero := by
  have hult : hi.ult u = false := by simp [BitVec.ult, hge]
  obtain ⟨pc, d', rs, as, regs, mem⟩ := s
  simp only at hd; subst hd
  simp [umDivPre, execSeq, exec, State.fall, Cond.eval, State.setReg, hult, Word.ofBool]

theorem umDivPre_under (s : State n) (h : s.dstack.length < 3) :
    execSeq umDivPre s = .trapped .stackUnderflow := by
  obtain ⟨pc, d, rs, as, regs, mem⟩ := s
  rcases d with _ | ⟨x, _ | ⟨y, _ | ⟨z, d⟩⟩⟩
  · simp [umDivPre, execSeq, exec]
  · simp [umDivPre, execSeq, exec]
  · simp [umDivPre, execSeq, exec]
  · simp at h; omega

/-- What one round of `UM/MOD` does to the registers. -/
theorem umDivBody_run (s : State n) :
    let t := Word.shr (s.regs 1) (BitVec.ofNat n (n - 1))
    let r2 := Word.shl (s.regs 1) 1#n + Word.shr (s.regs 2) (BitVec.ofNat n (n - 1))
    let c := Word.ofBool (Cond.eval .uge r2 (s.regs 0)) ||| t
    ∃ s', execSeq umDivBody s = .next s' ∧ s'.pc = s.pc + 29 ∧ s'.dstack = s.dstack ∧
      s'.mem = s.mem ∧ s'.astack = s.astack ∧ s'.rstack = s.rstack ∧
      s'.regs 0 = s.regs 0 ∧ s'.regs 4 = s.regs 4 ∧ s'.regs 2 = Word.shl (s.regs 2) 1#n ∧
      s'.regs 3 = c + Word.shl (s.regs 3) 1#n ∧ s'.regs 1 = r2 - c * s.regs 0 ∧ (∀ j, 5 ≤ j → s'.regs j = s.regs j) := by
  intro t r2 c
  obtain ⟨pc, d, rs, as, regs, mem⟩ := s
  simp only [umDivBody, execSeq, exec, State.fall]
  refine ⟨_, rfl, ?_⟩
  refine ⟨by simp [Nat.add_assoc], rfl, rfl, rfl, rfl, by simp [State.setReg],
    by simp [State.setReg], by simp [State.setReg], by simp [State.setReg, t, r2, c],
    by simp [State.setReg, t, r2, c], ?_⟩
  intro j hj
  simp [State.setReg, show j ≠ 1 by omega, show j ≠ 2 by omega, show j ≠ 3 by omega]

theorem lor_flags {y : Nat} (hy : y ≤ 1) (P : Prop) [Decidable P] :
    (if P then 1 else 0) ||| y = if y = 1 ∨ P then 1 else 0 := by
  rcases (by omega : y = 0 ∨ y = 1) with h | h <;> subst h <;> by_cases hp : P <;> simp [hp]

/-- The `UM/MOD` loop invariant after `k` rounds. -/
def umDivInv (u hi lo : Word n) (k : Nat) (s : State n) : Prop :=
  s.regs 0 = u ∧
    (s.regs 1).toNat = (hi.toNat * 2 ^ n + lo.toNat) / 2 ^ (n - k) % u.toNat ∧
    (s.regs 3).toNat = (hi.toNat * 2 ^ n + lo.toNat) / 2 ^ (n - k) / u.toNat ∧
    (s.regs 2).toNat = lo.toNat * 2 ^ k % 2 ^ n

theorem umDiv_round (hn : 0 < n) {u hi lo : Word n} (hlt : hi.toNat < u.toNat) {k : Nat}
    (hk : k < n) {s s' : State n} (hI : umDivInv u hi lo k s)
    (h0 : s'.regs 0 = s.regs 0) (h2 : s'.regs 2 = Word.shl (s.regs 2) 1#n)
    (h3 : s'.regs 3 = (Word.ofBool (Cond.eval .uge (Word.shl (s.regs 1) 1#n +
        Word.shr (s.regs 2) (BitVec.ofNat n (n - 1))) (s.regs 0)) |||
        Word.shr (s.regs 1) (BitVec.ofNat n (n - 1))) + Word.shl (s.regs 3) 1#n)
    (h1 : s'.regs 1 = (Word.shl (s.regs 1) 1#n + Word.shr (s.regs 2) (BitVec.ofNat n (n - 1))) -
      (Word.ofBool (Cond.eval .uge (Word.shl (s.regs 1) 1#n +
        Word.shr (s.regs 2) (BitVec.ofNat n (n - 1))) (s.regs 0)) |||
        Word.shr (s.regs 1) (BitVec.ofNat n (n - 1))) * s.regs 0) :
    umDivInv u hi lo (k + 1) s' := by
  obtain ⟨hu, hR, hQ, hL⟩ := hI
  have hU : 0 < u.toNat := by omega
  have step := DoubleMath.umdiv_step hn hk hU u.isLt lo.isLt hlt hR hQ hL
  have hN := DoubleMath.two_pow_succ' n hn
  have ht : (s.regs 1).toNat / 2 ^ (n - 1) ≤ 1 := by
    have := (s.regs 1).isLt
    have : (s.regs 1).toNat / 2 ^ (n - 1) < 2 := Nat.div_lt_of_lt_mul (by omega)
    omega
  refine ⟨h0.trans hu, ?_, ?_, ?_⟩
  · rw [h1]
    simp only [BitVec.toNat_sub, BitVec.toNat_mul, BitVec.toNat_or, BitVec.toNat_add,
      ofBool_toNat hn, Cond.eval, BitVec.ule, decide_eq_true_eq, shl_one_toNat, shr_top_toNat,
      hu] at step ⊢
    rw [lor_flags ht]; exact step.1
  · rw [h3]
    simp only [BitVec.toNat_or, BitVec.toNat_add, ofBool_toNat hn, Cond.eval,
      BitVec.ule, decide_eq_true_eq, shl_one_toNat, shr_top_toNat, hu] at step ⊢
    rw [lor_flags ht, Nat.add_comm]; exact step.2
  · rw [h2, shl_one_toNat, hL, Nat.mul_mod, Nat.mod_mod, ← Nat.mul_mod, Nat.pow_succ,
      Nat.mul_comm (2 ^ k) 2, Nat.mul_left_comm]

/-- **`UM/MOD` divides the double-cell number.** -/
theorem umDiv_ok {p : Prog n} {base : Nat} (hat : At p base ((umDivFrag : Frag n).emit base))
    (s : State n) (hpc : s.pc = base) {u hi lo : Word n} {d : List (Word n)}
    (hd : s.dstack = u :: hi :: lo :: d) (hlt : hi.toNat < u.toNat) :
    ∃ s', Steps p s s' ∧ s'.pc = base + 54 ∧ s'.rstack = s.rstack ∧
      s'.dstack = BitVec.ofNat n ((hi.toNat * 2 ^ n + lo.toNat) / u.toNat) ::
        BitVec.ofNat n ((hi.toNat * 2 ^ n + lo.toNat) % u.toNat) :: d ∧
      s'.mem = s.mem ∧ s'.astack = s.astack ∧ (∀ j, 5 ≤ j → s'.regs j = s.regs j) := by
  have hn : 0 < n := by
    rcases Nat.eq_zero_or_pos n with h | h
    · subst h; have := u.isLt; simp at this; omega
    · exact h
  obtain ⟨hpre, hrest⟩ := Frag.seq_at (by simpa [umDivFrag] using hat)
  obtain ⟨hloop, hpost⟩ := Frag.seq_at hrest
  rw [countedLoop_size, Frag.ofCode_size, Frag.ofCode_size] at hpost
  simp only [Frag.ofCode, umDivPre, umDivBody, List.length_cons, List.length_nil] at hpre hloop hpost
  obtain ⟨s1, hx1, hpc1, hd1, hm1, ha1, hr1, hU, hH, hL, hQ, hK1⟩ := umDivPre_run s hd hlt
  obtain ⟨hst1, -⟩ := execSeq_steps umDivPre_straight (by rw [hpc]; exact hpre) hx1
  have hlo := lo.isLt
  have hD0 : (hi.toNat * 2 ^ n + lo.toNat) / 2 ^ n = hi.toNat := by
    rw [Nat.add_comm, Nat.add_mul_div_right _ _ (Nat.two_pow_pos n), Nat.div_eq_of_lt hlo,
      Nat.zero_add]
  obtain ⟨s2, hs2, hpc2, -, hd2, ha2, hr2, hI⟩ := countedLoop_run' (r := 4) (N := n)
    (body := Frag.ofCode umDivBody) hn Nat.lt_two_pow_self hloop
    (fun k s => umDivInv u hi lo k s ∧ s.mem = s1.mem ∧ ∀ j, 5 ≤ j → s.regs j = s1.regs j)
    (by
      intro k s s' hI hm _ _ _ hregs
      obtain ⟨⟨h0, h1, h3, h2⟩, hm0, hK⟩ := hI
      exact ⟨⟨by rw [hregs 0 (by decide)]; exact h0, by rw [hregs 1 (by decide)]; exact h1,
        by rw [hregs 3 (by decide)]; exact h3, by rw [hregs 2 (by decide)]; exact h2⟩,
        hm.trans hm0, fun j hj => (hregs j (by omega)).trans (hK j hj)⟩)
    (by
      intro k s hk hI hpcs hrk
      have hbody := countedLoop_body_at hloop
      obtain ⟨s', hx, hpc', hd', hm', ha', hr', h0, h4, h2, h3, h1, hK'⟩ := umDivBody_run s
      obtain ⟨hst, -⟩ := execSeq_steps umDivBody_straight
        (by rw [hpcs]; simpa [Frag.ofCode, umDivBody] using hbody) hx
      refine ⟨s', hst, by rw [hpc', hpcs]; simp [Frag.ofCode, umDivBody], by rw [h4, hrk],
        hd', ha', hr', umDiv_round hn hlt hk hI.1 h0 h2 h3 h1, hm'.trans hI.2.1,
        fun j hj => (hK' j hj).trans (hI.2.2 j hj)⟩)
    s1 (by rw [hpc1, hpc])
    ⟨⟨hU, by rw [hH, Nat.sub_zero, hD0, Nat.mod_eq_of_lt hlt],
      by rw [hQ, Nat.sub_zero, hD0, Nat.div_eq_of_lt hlt]; rfl,
      by rw [hL]; simp [Nat.mod_eq_of_lt hlo]⟩, rfl, fun _ _ => rfl⟩
  obtain ⟨⟨-, hRf, hQf, -⟩, hm2, hK2⟩ := hI
  simp only [Nat.sub_self, Nat.pow_zero, Nat.div_one] at hRf hQf
  have hpc2' : s2.pc = base + 52 := by rw [hpc2]; simp [Frag.ofCode, umDivBody]
  have hx3 : execSeq umDivPost s2 =
      .next { s2 with pc := s2.pc + 2, dstack := s2.regs 3 :: s2.regs 1 :: s2.dstack } := by
    simp [umDivPost, execSeq, exec, State.fall, Nat.add_assoc]
  obtain ⟨hst3, -⟩ := execSeq_steps umDivPost_straight (by rw [hpc2']; exact hpost) hx3
  refine ⟨_, hst1.trans (hs2.trans hst3), by simp [hpc2'], by simp [hr2, hr1], ?_,
    by simp [hm2, hm1], by simp [ha2, ha1], fun j hj => (hK2 j hj).trans (hK1 j hj)⟩
  simp only [hd2, hd1]
  rw [ofNat_eq_of_toNat hQf, ofNat_eq_of_toNat hRf]

end UmDiv

/-! ## `M*` -/

section MStar
variable {n : Nat}

theorem ofInt_flag (x : Word n) :
    BitVec.ofInt n (if x.msb then 1 else 0) = Word.ofBool (n := n) (x.slt 0#n) := by
  rw [BitVec.slt_zero_eq_msb]; cases x.msb <;> simp [Word.ofBool]

theorem ofInt_pow : BitVec.ofInt n ((2 ^ n : Nat) : Int) = 0#n := by
  rw [BitVec.ofInt_natCast]; apply BitVec.eq_of_toNat_eq; simp

theorem ofInt_toNat (x : Word n) : BitVec.ofInt n (x.toNat : Int) = x := by
  rw [BitVec.ofInt_natCast]; apply BitVec.eq_of_toNat_eq; simp

/-- The signed product's low word is the unsigned one. -/
theorem mstar_lo (a b : Word n) :
    BitVec.ofNat n (a.toNat * b.toNat) = BitVec.ofInt n (a.toInt * b.toInt) := by
  rw [BitVec.ofInt_mul, BitVec.ofInt_toInt, BitVec.ofInt_toInt]
  apply BitVec.eq_of_toNat_eq; simp

set_option linter.unusedSimpArgs false in
/-- **The signed product's high word** is the unsigned one minus `b` when `a < 0` and minus `a`
when `b < 0` (the bit patterns of negative numbers are `2^n` too large). -/
theorem mstar_hi (a b : Word n) :
    BitVec.ofNat n (a.toNat * b.toNat / 2 ^ n) - Word.ofBool (a.slt 0#n) * b -
      Word.ofBool (b.slt 0#n) * a = BitVec.ofInt n (a.toInt * b.toInt / (2 ^ n : Nat)) := by
  have ha := BitVec.toInt_eq_msb_cond a
  have hb := BitVec.toInt_eq_msb_cond b
  have key : a.toInt * b.toInt = (a.toNat * b.toNat : Nat) +
      ((if a.msb then 1 else 0) * (if b.msb then 1 else 0) * (2 ^ n : Nat) -
        (if b.msb then 1 else 0) * a.toNat - (if a.msb then 1 else 0) * b.toNat) * (2 ^ n : Nat) := by
    rw [ha, hb]; cases a.msb <;> cases b.msb <;> simp [Int.mul_sub, Int.sub_mul, Int.mul_comm,
      Int.neg_mul, Int.mul_neg, Int.mul_assoc, Int.mul_left_comm] <;> omega
  have hN : ((2 ^ n : Nat) : Int) ≠ 0 := by have := Nat.two_pow_pos n; omega
  rw [key, Int.add_mul_ediv_right _ _ hN, ← Int.natCast_ediv, BitVec.ofInt_add, BitVec.ofInt_natCast]
  simp only [Int.sub_eq_add_neg, BitVec.ofInt_add, BitVec.ofInt_neg, BitVec.ofInt_mul, ofInt_flag,
    ofInt_pow, ofInt_toNat, BitVec.mul_zero, BitVec.zero_add, BitVec.sub_eq_add_neg]
  rw [BitVec.add_assoc, BitVec.add_comm (-(Word.ofBool (a.slt 0#n) * b))]

theorem mStarPre_straight : ∀ i ∈ (mStarPre : List (Instr n)), i.isStraight = true := by
  simp [mStarPre, Instr.isStraight]
theorem mStarPost_straight : ∀ i ∈ (mStarPost : List (Instr n)), i.isStraight = true := by
  simp [mStarPost, Instr.isStraight]

theorem mStarPre_run (s : State n) {a b : Word n} {d : List (Word n)}
    (hd : s.dstack = b :: a :: d) :
    ∃ s', execSeq mStarPre s = .next s' ∧ s'.pc = s.pc + 4 ∧ s'.dstack = s.dstack ∧
      s'.mem = s.mem ∧ s'.astack = s.astack ∧ s'.rstack = s.rstack ∧
      s'.regs 5 = a ∧ s'.regs 6 = b := by
  obtain ⟨pc, d', rs, as, regs, mem⟩ := s
  simp only at hd; subst hd
  simp [mStarPre, execSeq, exec, State.fall, State.setReg, Nat.add_assoc]

theorem mStarPre_under (s : State n) (h : s.dstack.length < 2) :
    execSeq mStarPre s = .trapped .stackUnderflow := by
  obtain ⟨pc, d, rs, as, regs, mem⟩ := s
  rcases d with _ | ⟨x, _ | ⟨y, d⟩⟩
  · simp [mStarPre, execSeq, exec]
  · simp [mStarPre, execSeq, exec, State.fall]
  · simp at h; omega

/-- **`M*` computes the full signed product.** -/
theorem mStar_ok {p : Prog n} {base : Nat} (hat : At p base ((mStarFrag : Frag n).emit base))
    (s : State n) (hpc : s.pc = base) {a b : Word n} {d : List (Word n)}
    (hd : s.dstack = b :: a :: d) :
    ∃ s', Steps p s s' ∧ s'.pc = base + 67 ∧ s'.rstack = s.rstack ∧
      s'.dstack = BitVec.ofInt n (a.toInt * b.toInt / (2 ^ n : Nat)) ::
        BitVec.ofInt n (a.toInt * b.toInt) :: d ∧
      s'.mem = s.mem ∧ s'.astack = s.astack := by
  obtain ⟨hpre, hrest⟩ := Frag.seq_at (by simpa [mStarFrag] using hat)
  obtain ⟨hum, hpost⟩ := Frag.seq_at hrest
  rw [umStarFrag_size] at hpost
  simp only [Frag.ofCode, mStarPre, List.length_cons, List.length_nil] at hpre hum hpost
  obtain ⟨s1, hx1, hpc1, hd1, hm1, ha1, hr1, h5, h6⟩ := mStarPre_run s hd
  obtain ⟨hst1, -⟩ := execSeq_steps mStarPre_straight (by rw [hpc]; exact hpre) hx1
  obtain ⟨s2, hst2, hpc2, hr2, hd2, hm2, ha2, hK2⟩ :=
    umStar_ok hum s1 (by rw [hpc1, hpc]) (by rw [hd1, hd])
  have hx3 : execSeq mStarPost s2 =
      .next { s2 with
              pc := s2.pc + 12
              dstack := (BitVec.ofNat n (a.toNat * b.toNat / 2 ^ n) - Word.ofBool (a.slt 0#n) * b -
                Word.ofBool (b.slt 0#n) * a) :: BitVec.ofNat n (a.toNat * b.toNat) :: d } := by
    have e5 : s2.regs 5 = a := (hK2 5 (by decide)).trans h5
    have e6 : s2.regs 6 = b := (hK2 6 (by decide)).trans h6
    obtain ⟨pc, d', rs, as, regs, mem⟩ := s2
    simp only at hd2 e5 e6; subst hd2
    simp [mStarPost, execSeq, exec, State.fall, Cond.eval, e5, e6, Nat.add_assoc]
  obtain ⟨hst3, -⟩ := execSeq_steps mStarPost_straight (by rw [hpc2]; exact hpost) hx3
  refine ⟨_, hst1.trans (hst2.trans hst3), by simp [hpc2], by simp [hr2, hr1], ?_,
    by simp [hm2, hm1], by simp [ha2, ha1]⟩
  simp only [mstar_hi, mstar_lo]

end MStar

/-! ## The code before a loop -/

theorem umStarFrag_pre {n : Nat} {p : Prog n} {base : Nat}
    (hat : At p base ((umStarFrag : Frag n).emit base)) : At p base umStarPre := by
  exact (Frag.seq_at (by simpa [umStarFrag] using hat)).1

theorem umDivFrag_pre {n : Nat} {p : Prog n} {base : Nat}
    (hat : At p base ((umDivFrag : Frag n).emit base)) : At p base umDivPre := by
  exact (Frag.seq_at (by simpa [umDivFrag] using hat)).1

/-! ## `SM/REM` -/

section SmRem
variable {n : Nat}
open DoubleMath

theorem cneg (x : Word n) (b : Bool) :
    (x ^^^ (0#n - Word.ofBool b)) + Word.ofBool b = if b then -x else x := by
  cases b
  · simp [Word.ofBool]
  · have h : (0#n - 1#n) = BitVec.allOnes n := by
      rw [BitVec.zero_sub, BitVec.neg_one_eq_allOnes]
    simp only [Word.ofBool, ite_true, h, BitVec.xor_allOnes, ← BitVec.neg_eq_not_add]

theorem slt_zero (x : Word n) : x.slt 0#n = decide (x.toInt < 0) := by
  rw [BitVec.slt_zero_eq_msb]; simp [BitVec.msb_eq_toInt]

theorem xor_mask_true (x : Word n) : x ^^^ (0#n - Word.ofBool true) = ~~~x := by
  have h : (0#n - 1#n) = BitVec.allOnes n := by
    rw [BitVec.zero_sub, BitVec.neg_one_eq_allOnes]
  simp only [Word.ofBool, ite_true, h, BitVec.xor_allOnes]

theorem dneg_toNat (hi lo : Word n) :
    (Word.ofBool (((lo ^^^ (0#n - Word.ofBool (hi.slt 0#n))) + Word.ofBool (hi.slt 0#n)).ult
        (Word.ofBool (hi.slt 0#n))) + (hi ^^^ (0#n - Word.ofBool (hi.slt 0#n)))).toNat * 2 ^ n +
      ((lo ^^^ (0#n - Word.ofBool (hi.slt 0#n))) + Word.ofBool (hi.slt 0#n)).toNat =
      (hi.toInt * 2 ^ n + lo.toNat).natAbs := by
  have hlo := lo.isLt
  have hhi := hi.isLt
  rw [cneg, BitVec.toInt_eq_msb_cond, BitVec.slt_zero_eq_msb]
  cases hm : hi.msb
  · simp [Word.ofBool, BitVec.ult]
    rw [show (BitVec.toNat hi : Int) * 2 ^ n + (BitVec.toNat lo : Int) =
      ((BitVec.toNat hi * 2 ^ n + BitVec.toNat lo : Nat) : Int) by push_cast; rfl, Int.natAbs_natCast]
  · rw [xor_mask_true]
    simp only [ite_true]
    have h2 := BitVec.msb_eq_true_iff_two_mul_ge.mp hm
    have hn : 0 < n := by
      rcases Nat.eq_zero_or_pos n with h | h
      · subst h; simp at hhi h2; omega
      · exact h
    have hN := Nat.two_pow_pos n
    have h1 : (Word.ofBool (n := n) true).toNat = 1 := by rw [ofBool_toNat hn]; rfl
    have hneg : (-lo).toNat = (2 ^ n - lo.toNat) % 2 ^ n := by simp [BitVec.toNat_neg]
    have hnot : (~~~hi).toNat = 2 ^ n - 1 - hi.toNat := BitVec.toNat_not
    have hle : hi.toNat * 2 ^ n + 2 ^ n ≤ 2 ^ n * 2 ^ n := by
      rw [← Nat.succ_mul]; exact Nat.mul_le_mul_right _ hhi
    apply natAbs_dd
    by_cases hl0 : lo.toNat = 0
    · have hc : BitVec.ult (-lo) (Word.ofBool true) = true := by
        simp only [BitVec.ult, h1, hneg, hl0, Nat.sub_zero, Nat.mod_self]; decide
      have e : (Word.ofBool (n := n) true + ~~~hi).toNat = 2 ^ n - hi.toNat := by
        rw [BitVec.toNat_add, h1, hnot, Nat.mod_eq_of_lt (by omega)]; omega
      rw [hc, e, hneg, hl0, Nat.sub_zero, Nat.mod_self, Nat.sub_mul]
      omega
    · have hc : BitVec.ult (-lo) (Word.ofBool true) = false := by
        simp only [BitVec.ult, h1, hneg, Nat.mod_eq_of_lt (show 2 ^ n - lo.toNat < 2 ^ n by omega)]
        simp; omega
      have e : (Word.ofBool (n := n) false + ~~~hi).toNat = 2 ^ n - 1 - hi.toNat := by
        simp [Word.ofBool, hnot]
      rw [hc, e, hneg, Nat.mod_eq_of_lt (show 2 ^ n - lo.toNat < 2 ^ n by omega), Nat.sub_mul,
        Nat.sub_mul, Nat.one_mul]
      omega

theorem abs_toNat (v : Word n) :
    (if Word.isTrue (Word.ofBool (n := n) (v.slt 0#n)) then 0#n - v else v).toNat = v.toInt.natAbs := by
  have hv := v.isLt
  rw [BitVec.zero_sub]
  rw [BitVec.toInt_eq_msb_cond, BitVec.slt_zero_eq_msb]
  cases hm : v.msb
  · simp [Word.ofBool, Word.isTrue]
  · have h2 := BitVec.msb_eq_true_iff_two_mul_ge.mp hm
    have hn : 0 < n := by
      rcases Nat.eq_zero_or_pos n with h | h
      · subst h; simp at hv h2; omega
      · exact h
    have h10 : Word.isTrue (Word.ofBool (n := n) true) = true := by
      simp only [Word.isTrue, bne_iff_ne, ne_eq]; intro h
      have := congrArg BitVec.toNat h; rw [ofBool_toNat hn] at this; simp at this
    simp only [h10, ite_true, BitVec.toNat_neg]
    rw [Nat.mod_eq_of_lt (by omega)]
    omega

theorem ofBool_xor (a b : Bool) : Word.ofBool (n := n) a ^^^ Word.ofBool b = Word.ofBool (a ^^ b) := by
  cases a <;> cases b <;> simp [Word.ofBool]

theorem ofBool_and (a b : Bool) : Word.ofBool (n := n) a &&& Word.ofBool b = Word.ofBool (a && b) := by
  cases a <;> cases b <;> simp [Word.ofBool]

theorem ofBool_or (a b : Bool) : Word.ofBool (n := n) a ||| Word.ofBool b = Word.ofBool (a || b) := by
  cases a <;> cases b <;> simp [Word.ofBool]

theorem ofBool_eq_zero (hn : 0 < n) (b : Bool) : Word.ofBool (n := n) b = 0#n ↔ b = false := by
  constructor
  · intro h; have := congrArg BitVec.toNat h; rw [ofBool_toNat hn] at this
    cases b <;> simp_all
  · intro h; subst h; rfl

theorem dsign (hi lo : Word n) : hi.toInt * 2 ^ n + lo.toNat < 0 ↔ hi.toInt < 0 := by
  have hlo : (lo.toNat : Int) < 2 ^ n := by exact_mod_cast lo.isLt
  have hN : (0 : Int) ≤ 2 ^ n := Int.le_of_lt (Int.pow_pos (by decide))
  constructor
  · intro h; apply Classical.byContradiction; intro h'
    have := Int.mul_nonneg (Int.not_lt.mp h') hN; omega
  · intro h
    have := Int.mul_le_mul_of_nonneg_right (show hi.toInt ≤ -1 by omega) hN
    omega

theorem smrem_sign (v hi lo : Word n) :
    (v.slt 0#n ^^ hi.slt 0#n) = true ↔
      ¬(hi.toInt * 2 ^ n + lo.toNat < 0 ↔ v.toInt < 0) := by
  rw [dsign, slt_zero, slt_zero]
  by_cases h1 : hi.toInt < 0 <;> by_cases h2 : v.toInt < 0 <;> simp [h1, h2]

theorem smRemPre_straight : ∀ i ∈ (smRemPre : List (Instr n)), i.isStraight = true := by
  simp [smRemPre, Instr.isStraight]

theorem smRemPost_straight : ∀ i ∈ (smRemPost : List (Instr n)), i.isStraight = true := by
  simp [smRemPost, Instr.isStraight]

/-- The absolute value of `v` as `SM/REM` computes it. -/
def smAbs (v : Word n) : Word n :=
  if Word.isTrue (Word.ofBool (n := n) (v.slt 0#n)) then 0#n - v else v

/-- The low word of `|(lo, hi)|`. -/
def smLo (hi lo : Word n) : Word n :=
  (lo ^^^ (0#n - Word.ofBool (hi.slt 0#n))) + Word.ofBool (hi.slt 0#n)

/-- The high word of `|(lo, hi)|`. -/
def smHi (hi lo : Word n) : Word n :=
  Word.ofBool ((smLo hi lo).ult (Word.ofBool (hi.slt 0#n))) + (hi ^^^ (0#n - Word.ofBool (hi.slt 0#n)))

theorem smRemPre_run (s : State n) {v hi lo : Word n} {d : List (Word n)}
    (hd : s.dstack = v :: hi :: lo :: d) :
    ∃ s', execSeq smRemPre s = .next s' ∧ s'.pc = s.pc + 37 ∧
      s'.dstack = smAbs v :: smHi hi lo :: smLo hi lo :: d ∧
      s'.mem = s.mem ∧ s'.astack = s.astack ∧ s'.rstack = s.rstack ∧
      s'.regs 5 = Word.ofBool (v.slt 0#n ^^ hi.slt 0#n) ∧ s'.regs 6 = Word.ofBool (hi.slt 0#n) := by
  obtain ⟨pc, d', rs, as, regs, mem⟩ := s
  simp only at hd; subst hd
  simp only [smRemPre, execSeq, exec, State.fall, Cond.eval]
  refine ⟨_, rfl, by simp [Nat.add_assoc], rfl, rfl, rfl, rfl, ?_, by simp [State.setReg]⟩
  simp [State.setReg, ofBool_xor]

theorem smRemPre_under (s : State n) (h : s.dstack.length < 3) :
    execSeq smRemPre s = .trapped .stackUnderflow := by
  obtain ⟨pc, d, rs, as, regs, mem⟩ := s
  rcases d with _ | ⟨x, _ | ⟨y, _ | ⟨z, d⟩⟩⟩
  · simp [smRemPre, execSeq, exec]
  · simp [smRemPre, execSeq, exec]
  · simp [smRemPre, execSeq, exec, State.fall]
  · simp at h; omega

/-- The flag `SM/REM` divides by: nonzero iff the quotient fits. -/
def smOk (q r5 : Word n) : Word n :=
  Word.ofBool (q.ult (BitVec.intMin n)) ||| (Word.ofBool (q == BitVec.intMin n) &&& r5)

theorem smRemPost_run (s : State n) {q r : Word n} {d : List (Word n)}
    (hd : s.dstack = q :: r :: d) (hok : smOk q (s.regs 5) ≠ 0#n) :
    execSeq smRemPost s = .next { s with
      pc := s.pc + 27
      dstack := ((q ^^^ (0#n - s.regs 5)) + s.regs 5) :: ((r ^^^ (0#n - s.regs 6)) + s.regs 6) :: d } := by
  obtain ⟨pc, d', rs, as, regs, mem⟩ := s
  simp only at hd hok; subst hd
  simp only [smOk] at hok
  simp [smRemPost, execSeq, exec, State.fall, Cond.eval, hok, Nat.add_assoc]

theorem smRemPost_trap (s : State n) {q r : Word n} {d : List (Word n)}
    (hd : s.dstack = q :: r :: d) (hok : smOk q (s.regs 5) = 0#n) :
    execSeq smRemPost s = .trapped .divideByZero := by
  obtain ⟨pc, d', rs, as, regs, mem⟩ := s
  simp only at hd hok; subst hd
  simp only [smOk] at hok
  simp [smRemPost, execSeq, exec, State.fall, Cond.eval, hok]

theorem smOk_eq_zero (hn : 0 < n) {Q : Nat} (hQ : Q < 2 ^ n) (b : Bool) :
    smOk (BitVec.ofNat n Q) (Word.ofBool b) = 0#n ↔ ¬(Q < 2 ^ (n - 1) ∨ (Q = 2 ^ (n - 1) ∧ b = true)) := by
  have hM : (BitVec.intMin n).toNat = 2 ^ (n - 1) := by
    rw [BitVec.toNat_intMin, Nat.mod_eq_of_lt (Nat.pow_lt_pow_right (by decide) (by omega))]
  have hq : (BitVec.ofNat n Q).toNat = Q := by rw [BitVec.toNat_ofNat, Nat.mod_eq_of_lt hQ]
  have he : (BitVec.ofNat n Q == BitVec.intMin n) = decide (Q = 2 ^ (n - 1)) := by
    have e : ∀ x y : Word n, (x == y) = decide (x.toNat = y.toNat) := by
      intro x y; by_cases h : x = y
      · simp [h]
      · have : x.toNat ≠ y.toNat := fun e => h (BitVec.eq_of_toNat_eq e)
        simp [h, this]
    rw [e, hM, hq]
  simp only [smOk, ofBool_and, ofBool_or, ofBool_eq_zero hn, BitVec.ult, hM, hq, he]
  cases b <;> simp

theorem smHiLo_toNat (hi lo : Word n) :
    (smHi hi lo).toNat * 2 ^ n + (smLo hi lo).toNat = (hi.toInt * 2 ^ n + lo.toNat).natAbs :=
  dneg_toNat hi lo

theorem smAbs_toNat (v : Word n) : (smAbs v).toNat = v.toInt.natAbs := abs_toNat v

/-- The signed result from the unsigned one and its sign. -/
theorem smrem_signed {Q : Nat} (b : Bool) {P : Prop} [Decidable P] (hb : b = true ↔ ¬P) :
    (BitVec.ofNat n Q ^^^ (0#n - Word.ofBool b)) + Word.ofBool b =
      BitVec.ofInt n (if P then (Q : Int) else -(Q : Int)) := by
  rw [cneg]
  by_cases hP : P
  · have : b = false := by cases b <;> simp_all
    simp [this, hP, BitVec.ofInt_natCast]
  · have : b = true := hb.mpr hP
    simp [this, hP, BitVec.ofInt_neg, BitVec.ofInt_natCast]

theorem smrem_signed' {Q : Nat} (b : Bool) {P : Prop} [Decidable P] (hb : b = true ↔ P) :
    (BitVec.ofNat n Q ^^^ (0#n - Word.ofBool b)) + Word.ofBool b =
      BitVec.ofInt n (if P then -(Q : Int) else (Q : Int)) := by
  rw [smrem_signed b (P := ¬P) (by simp [hb])]
  by_cases hP : P <;> simp [hP]

theorem width_pos_of_toInt {v : Word n} (h : v.toInt ≠ 0) : 0 < n := by
  rcases Nat.eq_zero_or_pos n with hn | hn
  · subst hn; exact absurd (by rw [word_eq_of_width_zero v 0#0]; rfl) h
  · exact hn

/-- **`SM/REM` divides symmetrically.** -/
theorem smRem_ok {p : Prog n} {base : Nat} (hat : At p base ((smRemFrag : Frag n).emit base))
    (s : State n) (hpc : s.pc = base) {v hi lo : Word n} {d : List (Word n)}
    (hd : s.dstack = v :: hi :: lo :: d)
    (hc : v.toInt ≠ 0 ∧ -(2 ^ (n - 1) : Int) ≤ (hi.toInt * 2 ^ n + lo.toNat).tdiv v.toInt ∧
      (hi.toInt * 2 ^ n + lo.toNat).tdiv v.toInt < 2 ^ (n - 1)) :
    ∃ s', Steps p s s' ∧ s'.pc = base + 118 ∧ s'.rstack = s.rstack ∧
      s'.dstack = BitVec.ofInt n ((hi.toInt * 2 ^ n + lo.toNat).tdiv v.toInt) ::
        BitVec.ofInt n ((hi.toInt * 2 ^ n + lo.toNat).tmod v.toInt) :: d ∧
      s'.mem = s.mem ∧ s'.astack = s.astack := by
  have hn := width_pos_of_toInt hc.1
  have hN := DoubleMath.two_pow_succ' n hn
  have hH : 0 < 2 ^ (n - 1) := Nat.two_pow_pos _
  obtain ⟨hpre, hrest⟩ := Frag.seq_at (by simpa [smRemFrag] using hat)
  obtain ⟨hum, hpost⟩ := Frag.seq_at hrest
  rw [umDivFrag_size] at hpost
  simp only [Frag.ofCode, smRemPre, List.length_cons, List.length_nil] at hpre hum hpost
  obtain ⟨s1, hx1, hpc1, hd1, hm1, ha1, hr1, h5, h6⟩ := smRemPre_run s hd
  obtain ⟨hst1, -⟩ := execSeq_steps smRemPre_straight (by rw [hpc]; exact hpre) hx1
  have hcond := (smrem_cond (sq := v.slt 0#n ^^ hi.slt 0#n) (by omega : 2 ^ n = 2 * 2 ^ (n - 1)) hH
    (smrem_sign v hi lo)).mp
    (by exact_mod_cast hc)
  rw [← smHiLo_toNat, ← smAbs_toNat] at hcond
  obtain ⟨hlt, hq⟩ := hcond
  have hlo := (smLo hi lo).isLt
  have hhi : (smHi hi lo).toNat < (smAbs v).toNat := by
    apply Classical.byContradiction; intro h
    have := Nat.mul_le_mul_right (2 ^ n) (Nat.not_lt.mp h); omega
  obtain ⟨s2, hst2, hpc2, hr2, hd2, hm2, ha2, hK2⟩ :=
    umDiv_ok hum s1 (by rw [hpc1, hpc]) hd1 hhi
  rw [smHiLo_toNat, smAbs_toNat] at hd2
  rw [smHiLo_toNat, smAbs_toNat] at hlt hq
  have hb : 0 < v.toInt.natAbs := by
    rcases Nat.eq_zero_or_pos v.toInt.natAbs with h | h
    · rw [h] at hlt; omega
    · exact h
  have hQ : (hi.toInt * 2 ^ n + lo.toNat).natAbs / v.toInt.natAbs < 2 ^ n :=
    (Nat.div_lt_iff_lt_mul hb).mpr (by rw [Nat.mul_comm]; exact hlt)
  have e5 : s2.regs 5 = Word.ofBool (v.slt 0#n ^^ hi.slt 0#n) := (hK2 5 (by decide)).trans h5
  have e6 : s2.regs 6 = Word.ofBool (hi.slt 0#n) := (hK2 6 (by decide)).trans h6
  have hok : smOk (BitVec.ofNat n ((hi.toInt * 2 ^ n + lo.toNat).natAbs / v.toInt.natAbs))
      (s2.regs 5) ≠ 0#n := by
    rw [e5]; intro h; exact (smOk_eq_zero hn hQ _).mp h hq
  have hx3 := smRemPost_run s2 hd2 hok
  obtain ⟨hst3, -⟩ := execSeq_steps smRemPost_straight (by rw [hpc2]; exact hpost) hx3
  refine ⟨_, hst1.trans (hst2.trans hst3), by simp [hpc2], by simp [hr2, hr1], ?_,
    by simp [hm2, hm1], by simp [ha2, ha1]⟩
  simp only [e5, e6]
  rw [smrem_signed _ (smrem_sign v hi lo), tdiv_natAbs, tmod_natAbs,
    smrem_signed' _ (P := hi.toInt * 2 ^ n + lo.toNat < 0)
      (by rw [slt_zero, decide_eq_true_iff, dsign])]

/-- **`SM/REM` traps** when the divisor is zero or the quotient does not fit. -/
theorem smRem_err {p : Prog n} {base : Nat} (hat : At p base ((smRemFrag : Frag n).emit base))
    (s : State n) (hpc : s.pc = base) {v hi lo : Word n} {d : List (Word n)}
    (hd : s.dstack = v :: hi :: lo :: d)
    (hc : ¬(v.toInt ≠ 0 ∧ -(2 ^ (n - 1) : Int) ≤ (hi.toInt * 2 ^ n + lo.toNat).tdiv v.toInt ∧
      (hi.toInt * 2 ^ n + lo.toNat).tdiv v.toInt < 2 ^ (n - 1))) :
    ∃ s1, Steps p s s1 ∧ step p s1 = .trapped .divideByZero := by
  obtain ⟨hpre, hrest⟩ := Frag.seq_at (by simpa [smRemFrag] using hat)
  obtain ⟨hum, hpost⟩ := Frag.seq_at hrest
  rw [umDivFrag_size] at hpost
  simp only [Frag.ofCode, smRemPre, List.length_cons, List.length_nil] at hpre hum hpost
  obtain ⟨s1, hx1, hpc1, hd1, hm1, ha1, hr1, h5, h6⟩ := smRemPre_run s hd
  obtain ⟨hst1, -⟩ := execSeq_steps smRemPre_straight (by rw [hpc]; exact hpre) hx1
  by_cases hhi : (smHi hi lo).toNat < (smAbs v).toNat
  · have hn : 0 < n := by
      rcases Nat.eq_zero_or_pos n with h | h
      · subst h; have := (smAbs v).isLt; simp at this; omega
      · exact h
    have hN := DoubleMath.two_pow_succ' n hn
    have hH : 0 < 2 ^ (n - 1) := Nat.two_pow_pos _
    have hlo := (smLo hi lo).isLt
    have hlt : (smHi hi lo).toNat * 2 ^ n + (smLo hi lo).toNat < (smAbs v).toNat * 2 ^ n := by
      have := Nat.mul_le_mul_right (2 ^ n) (Nat.succ_le_of_lt hhi)
      rw [Nat.succ_mul] at this; omega
    have hcond := mt (smrem_cond (sq := v.slt 0#n ^^ hi.slt 0#n)
      (by omega : 2 ^ n = 2 * 2 ^ (n - 1)) hH (smrem_sign v hi lo)).mpr
      (by exact_mod_cast hc)
    rw [← smHiLo_toNat, ← smAbs_toNat] at hcond
    have hq := fun h => hcond ⟨hlt, h⟩
    obtain ⟨s2, hst2, hpc2, -, hd2, -, -, hK2⟩ := umDiv_ok hum s1 (by rw [hpc1, hpc]) hd1 hhi
    have hb : 0 < (smAbs v).toNat := by omega
    have hQ : ((smHi hi lo).toNat * 2 ^ n + (smLo hi lo).toNat) / (smAbs v).toNat < 2 ^ n :=
      (Nat.div_lt_iff_lt_mul hb).mpr (by rw [Nat.mul_comm (2 ^ n) (smAbs v).toNat]; exact hlt)
    have e5 : s2.regs 5 = Word.ofBool (v.slt 0#n ^^ hi.slt 0#n) := (hK2 5 (by decide)).trans h5
    have hok : smOk (BitVec.ofNat n (((smHi hi lo).toNat * 2 ^ n + (smLo hi lo).toNat) /
        (smAbs v).toNat)) (s2.regs 5) = 0#n := by
      rw [e5]; exact (smOk_eq_zero hn hQ _).mpr hq
    obtain ⟨s3, hst3, ht3⟩ := execSeq_trap smRemPost_straight (by rw [hpc2]; exact hpost)
      (smRemPost_trap s2 hd2 hok)
    exact ⟨s3, hst1.trans (hst2.trans hst3), ht3⟩
  · have hdpre := umDivFrag_pre hum
    obtain ⟨s3, hst3, ht3⟩ := execSeq_trap umDivPre_straight (by rw [hpc1, hpc]; exact hdpre)
      (umDivPre_trap s1 hd1 hhi)
    exact ⟨s3, hst1.trans hst3, ht3⟩

end SmRem

/-! ## `*/MOD` and `*/` -/

section StarSlash
variable {n : Nat}

/-- The two words of `M*` are the double-cell number `a * b`. -/
theorem mstar_split (a b : Word n) :
    (BitVec.ofInt n (a.toInt * b.toInt / (2 ^ n : Nat))).toInt * 2 ^ n +
      ((BitVec.ofInt n (a.toInt * b.toInt)).toNat : Int) = a.toInt * b.toInt := by
  rcases Nat.eq_zero_or_pos n with hn | hn
  · subst hn
    rw [word_eq_of_width_zero a 0#0]; simp
  have ha1 := BitVec.le_toInt a
  have ha2 := BitVec.toInt_lt (x := a)
  have hb1 := BitVec.le_toInt b
  have hb2 := BitVec.toInt_lt (x := b)
  have hN : (2 : Int) ^ n = 2 * 2 ^ (n - 1) := by
    rw [← Int.pow_succ', Nat.sub_add_cancel hn]
  have hH : (0 : Int) < 2 ^ (n - 1) := Int.pow_pos (by decide)
  generalize (2 : Int) ^ (n - 1) = H at *
  have hP : (a.toInt * b.toInt).natAbs ≤ H.natAbs * H.natAbs := by
    rw [Int.natAbs_mul]; exact Nat.mul_le_mul (by omega) (by omega)
  have hHH : ((H.natAbs * H.natAbs : Nat) : Int) = H * H := by
    push_cast; rw [Int.natAbs_of_nonneg (by omega)]
  generalize a.toInt * b.toInt = P at *
  rw [BitVec.toInt_ofInt, BitVec.toNat_ofInt, Int.toNat_of_nonneg (Int.emod_nonneg _ (by have := Nat.two_pow_pos n; omega))]
  push_cast
  have hP' : (P.natAbs : Int) ≤ H * H := by rw [← hHH]; exact_mod_cast hP
  have hHH2 : H * (2 * H) = 2 * (H * H) := Int.mul_left_comm _ _ _
  have hpos := Int.mul_pos hH hH
  have e := Int.emod_add_ediv_mul P (2 ^ n)
  rw [Int.bmod_eq_of_le]
  · omega
  · push_cast; rw [hN, show 2 * H / 2 = H by omega]
    apply Int.le_ediv_of_mul_le (by omega)
    rw [Int.neg_mul, hHH2]; omega
  · push_cast; rw [hN, show (2 * H + 1) / 2 = H by omega]
    apply Int.ediv_lt_of_lt_mul (by omega)
    rw [hHH2]; omega

theorem starSlashMod_mid {p : Prog n} {base : Nat}
    (hat : At p base ((starSlashModFrag : Frag n).emit base))
    (s : State n) (hpc : s.pc = base) {a b c : Word n} {d : List (Word n)}
    (hd : s.dstack = c :: b :: a :: d) :
    ∃ s3, Steps p s s3 ∧ s3.pc = base + 69 ∧
      s3.dstack = c :: BitVec.ofInt n (a.toInt * b.toInt / (2 ^ n : Nat)) ::
        BitVec.ofInt n (a.toInt * b.toInt) :: d ∧
      s3.rstack = s.rstack ∧ s3.mem = s.mem ∧ s3.astack = s.astack ∧
      At p (base + 69) ((smRemFrag : Frag n).emit (base + 69)) := by
  obtain ⟨htor, hrest⟩ := Frag.seq_at (by simpa [starSlashModFrag] using hat)
  obtain ⟨hm, hrest⟩ := Frag.seq_at hrest
  obtain ⟨hfr, hsm⟩ := Frag.seq_at hrest
  simp only [Frag.ofCode, mStarFrag_size, List.length_cons, List.length_nil] at htor hm hfr hsm
  obtain ⟨pc, d', rs, as, regs, mem⟩ := s
  simp only at hd hpc; subst hd
  have hx1 : execSeq [.tor] (⟨pc, c :: b :: a :: d, rs, as, regs, mem⟩ : State n) =
      .next ⟨pc + 1, b :: a :: d, rs, c :: as, regs, mem⟩ := by simp [execSeq, exec]
  obtain ⟨hst1, -⟩ := execSeq_steps (by simp [Instr.isStraight]) (by simpa [hpc] using htor) hx1
  obtain ⟨s2, hst2, hpc2, hr2, hd2, hm2, ha2⟩ :=
    mStar_ok hm ⟨pc + 1, b :: a :: d, rs, c :: as, regs, mem⟩ (by simp [hpc]) rfl
  have hx3 : execSeq [.fromr] s2 = .next { s2 with
              pc := s2.pc + 1
              dstack := c :: s2.dstack
              astack := as } := by
    obtain ⟨pc2, d2, rs2, as2, regs2, mem2⟩ := s2
    simp only at ha2; subst ha2
    simp [execSeq, exec]
  obtain ⟨hst3, -⟩ := execSeq_steps (by simp [Instr.isStraight]) (by rw [hpc2]; exact hfr) hx3
  refine ⟨_, hst1.trans (hst2.trans hst3), by simp [hpc2], by simp [hd2], by simp [hr2],
    by simp [hm2], rfl, by simpa [Nat.add_assoc] using hsm⟩

/-- **`*/MOD` divides the double-cell product.** -/
theorem starSlashMod_ok {p : Prog n} {base : Nat}
    (hat : At p base ((starSlashModFrag : Frag n).emit base))
    (s : State n) (hpc : s.pc = base) {a b c : Word n} {d : List (Word n)}
    (hd : s.dstack = c :: b :: a :: d)
    (hc : c.toInt ≠ 0 ∧ -(2 ^ (n - 1) : Int) ≤ (a.toInt * b.toInt).tdiv c.toInt ∧
      (a.toInt * b.toInt).tdiv c.toInt < 2 ^ (n - 1)) :
    ∃ s', Steps p s s' ∧ s'.pc = base + 187 ∧ s'.rstack = s.rstack ∧
      s'.dstack = BitVec.ofInt n ((a.toInt * b.toInt).tdiv c.toInt) ::
        BitVec.ofInt n ((a.toInt * b.toInt).tmod c.toInt) :: d ∧
      s'.mem = s.mem ∧ s'.astack = s.astack := by
  obtain ⟨s3, hst3, hpc3, hd3, hr3, hm3, ha3, hsm⟩ := starSlashMod_mid hat s hpc hd
  rw [← mstar_split a b] at hc
  obtain ⟨s4, hst4, hpc4, hr4, hd4, hm4, ha4⟩ := smRem_ok hsm s3 hpc3 hd3 hc
  rw [mstar_split] at hd4
  exact ⟨s4, hst3.trans hst4, by rw [hpc4], by rw [hr4, hr3], hd4, by rw [hm4, hm3],
    by rw [ha4, ha3]⟩

theorem starSlashMod_err {p : Prog n} {base : Nat}
    (hat : At p base ((starSlashModFrag : Frag n).emit base))
    (s : State n) (hpc : s.pc = base) {a b c : Word n} {d : List (Word n)}
    (hd : s.dstack = c :: b :: a :: d)
    (hc : ¬(c.toInt ≠ 0 ∧ -(2 ^ (n - 1) : Int) ≤ (a.toInt * b.toInt).tdiv c.toInt ∧
      (a.toInt * b.toInt).tdiv c.toInt < 2 ^ (n - 1))) :
    ∃ s1, Steps p s s1 ∧ step p s1 = .trapped .divideByZero := by
  obtain ⟨s3, hst3, hpc3, hd3, -, -, -, hsm⟩ := starSlashMod_mid hat s hpc hd
  rw [← mstar_split a b] at hc
  obtain ⟨s4, hst4, ht4⟩ := smRem_err hsm s3 hpc3 hd3 hc
  exact ⟨s4, hst3.trans hst4, ht4⟩

theorem starSlashMod_under {p : Prog n} {base : Nat}
    (hat : At p base ((starSlashModFrag : Frag n).emit base))
    (s : State n) (hpc : s.pc = base) (h : s.dstack.length < 3) :
    ∃ s1, Steps p s s1 ∧ step p s1 = .trapped .stackUnderflow := by
  obtain ⟨htor, hrest⟩ := Frag.seq_at (by simpa [starSlashModFrag] using hat)
  obtain ⟨hm, -⟩ := Frag.seq_at hrest
  obtain ⟨hmpre, -⟩ := Frag.seq_at (by simpa [mStarFrag] using hm)
  simp only [Frag.ofCode, List.length_cons, List.length_nil] at htor hmpre
  obtain ⟨pc, d, rs, as, regs, mem⟩ := s
  simp only at hpc h
  rcases d with _ | ⟨c, d⟩
  · exact execSeq_trap (code := [.tor]) (by simp [Instr.isStraight]) (by simpa [hpc] using htor)
      (by simp [execSeq, exec])
  · have hx1 : execSeq [.tor] (⟨pc, c :: d, rs, as, regs, mem⟩ : State n) =
        .next ⟨pc + 1, d, rs, c :: as, regs, mem⟩ := by simp [execSeq, exec]
    obtain ⟨hst1, -⟩ := execSeq_steps (by simp [Instr.isStraight]) (by simpa [hpc] using htor) hx1
    obtain ⟨s2, hst2, ht2⟩ := execSeq_trap mStarPre_straight
      (s := ⟨pc + 1, d, rs, c :: as, regs, mem⟩) (by simpa [hpc] using hmpre)
      (mStarPre_under _ (by simp at h ⊢; omega))
    exact ⟨s2, hst1.trans hst2, ht2⟩

theorem starSlash_ok {p : Prog n} {base : Nat}
    (hat : At p base ((starSlashFrag : Frag n).emit base))
    (s : State n) (hpc : s.pc = base) {a b c : Word n} {d : List (Word n)}
    (hd : s.dstack = c :: b :: a :: d)
    (hc : c.toInt ≠ 0 ∧ -(2 ^ (n - 1) : Int) ≤ (a.toInt * b.toInt).tdiv c.toInt ∧
      (a.toInt * b.toInt).tdiv c.toInt < 2 ^ (n - 1)) :
    ∃ s', Steps p s s' ∧ s'.pc = base + 189 ∧ s'.rstack = s.rstack ∧
      s'.dstack = BitVec.ofInt n ((a.toInt * b.toInt).tdiv c.toInt) :: d ∧
      s'.mem = s.mem ∧ s'.astack = s.astack := by
  obtain ⟨hmod, hsd⟩ := Frag.seq_at (by simpa [starSlashFrag] using hat)
  rw [starSlashModFrag_size] at hsd
  obtain ⟨s4, hst4, hpc4, hr4, hd4, hm4, ha4⟩ := starSlashMod_ok hmod s hpc hd hc
  have hx : execSeq [.swap, .drop] s4 = .next { s4 with
              pc := s4.pc + 2
              dstack := BitVec.ofInt n ((a.toInt * b.toInt).tdiv c.toInt) :: d } := by
    obtain ⟨pc4, d4, rs4, as4, regs4, mem4⟩ := s4
    simp only at hd4; subst hd4
    simp [execSeq, exec, State.fall, Nat.add_assoc]
  obtain ⟨hst5, -⟩ := execSeq_steps (by simp [Instr.isStraight])
    (by rw [hpc4]; simpa [Frag.ofCode] using hsd) hx
  exact ⟨_, hst4.trans hst5, by simp [hpc4], hr4, rfl, hm4, ha4⟩

theorem starSlashFrag_mod {p : Prog n} {base : Nat}
    (hat : At p base ((starSlashFrag : Frag n).emit base)) :
    At p base ((starSlashModFrag : Frag n).emit base) :=
  (Frag.seq_at (by simpa [starSlashFrag] using hat)).1

end StarSlash

/-! ## Every operation's code realizes its semantics -/

/-- **The code of an operation realizes `Op.sem`**: on success it reaches the end of the code
with the resulting stacks and memory (return stack unchanged); on a trap it traps the same. -/
theorem opFrag_run {n : Nat} {p : Prog n} (o : Op) {base : Nat} {s : State n}
    (hat : At p base ((opFrag o : Frag n).emit base)) (hpc : s.pc = base) :
    (∀ st', o.sem ⟨s.dstack, s.mem, s.astack⟩ = .ok st' →
      ∃ s', Steps p s s' ∧ s'.pc = base + o.len ∧ s'.rstack = s.rstack ∧
        s'.dstack = st'.stack ∧ s'.mem = st'.mem ∧ s'.astack = st'.rstack) ∧
    (∀ t, o.sem ⟨s.dstack, s.mem, s.astack⟩ = .error t →
      ∃ s1, Steps p s s1 ∧ step p s1 = .trapped t) := by
  cases hl : o.loopy
  · rw [opFrag_straight o hl] at hat
    have hcode : At p base (compileOp o : List (Instr n)) := by simpa [Frag.ofCode] using hat
    refine ⟨fun st' h => ?_, fun t h => ?_⟩
    · obtain ⟨hst, hpc'⟩ := execSeq_steps (compileOp_straight o) (by rw [hpc]; exact hcode)
        (compileOp_ok o hl s st' h)
      exact ⟨_, hst, by rw [hpc', hpc, compileOp_length o hl], rfl, rfl, rfl, rfl⟩
    · exact execSeq_trap (compileOp_straight o) (by rw [hpc]; exact hcode)
        (compileOp_err o hl s t h)
  · cases o <;> simp [Op.loopy] at hl
    · -- UM*
      have hpre := umStarFrag_pre hat
      obtain ⟨pc, d, rs, as, regs, mem⟩ := s
      simp only at hpc
      refine ⟨fun st' h => ?_, fun t h => ?_⟩
      · rcases d with _ | ⟨b, _ | ⟨a, d⟩⟩ <;> simp only [Op.sem] at h <;> try cases h
        obtain ⟨s', hs, hpc', hrs, hd', hm', ha', -⟩ :=
          umStar_ok hat ⟨pc, b :: a :: d, rs, as, regs, mem⟩ hpc rfl
        exact ⟨s', hs, hpc', hrs, hd', hm', ha'⟩
      · rcases d with _ | ⟨b, _ | ⟨a, d⟩⟩ <;> simp only [Op.sem] at h <;> cases h
        all_goals
          exact execSeq_trap umStarPre_straight (by show At p pc _; rw [hpc]; exact hpre)
            (umStarPre_under _ (by simp))
    · -- UM/MOD
      have hpre := umDivFrag_pre hat
      obtain ⟨pc, d, rs, as, regs, mem⟩ := s
      simp only at hpc
      refine ⟨fun st' h => ?_, fun t h => ?_⟩
      · rcases d with _ | ⟨u, _ | ⟨hi, _ | ⟨lo, d⟩⟩⟩ <;> simp only [Op.sem] at h <;> try cases h
        split at h
        · rename_i hlt
          cases h
          obtain ⟨s', hs, hpc', hrs, hd', hm', ha', -⟩ :=
            umDiv_ok hat ⟨pc, u :: hi :: lo :: d, rs, as, regs, mem⟩ hpc rfl hlt
          exact ⟨s', hs, hpc', hrs, hd', hm', ha'⟩
        · cases h
      · rcases d with _ | ⟨u, _ | ⟨hi, _ | ⟨lo, d⟩⟩⟩
        all_goals first
          | (simp only [Op.sem] at h; cases h
             exact execSeq_trap umDivPre_straight (by show At p pc _; rw [hpc]; exact hpre)
               (umDivPre_under _ (by simp)))
          | skip
        simp only [Op.sem] at h
        split at h
        · cases h
        · rename_i hge
          cases h
          exact execSeq_trap umDivPre_straight (by show At p pc _; rw [hpc]; exact hpre)
            (umDivPre_trap ⟨pc, u :: hi :: lo :: d, rs, as, regs, mem⟩ rfl hge)
    · -- M*
      obtain ⟨hpre, -⟩ := Frag.seq_at (by simpa [opFrag, mStarFrag] using hat)
      obtain ⟨pc, d, rs, as, regs, mem⟩ := s
      simp only at hpc
      refine ⟨fun st' h => ?_, fun t h => ?_⟩
      · rcases d with _ | ⟨b, _ | ⟨a, d⟩⟩ <;> simp only [Op.sem] at h <;> try cases h
        obtain ⟨s', hs, hpc', hrs, hd', hm', ha'⟩ :=
          mStar_ok hat ⟨pc, b :: a :: d, rs, as, regs, mem⟩ hpc rfl
        exact ⟨s', hs, hpc', hrs, hd', hm', ha'⟩
      · rcases d with _ | ⟨b, _ | ⟨a, d⟩⟩ <;> simp only [Op.sem] at h <;> cases h
        all_goals
          exact execSeq_trap mStarPre_straight (by show At p pc _; rw [hpc]; exact hpre)
            (mStarPre_under _ (by simp))
    · -- SM/REM
      obtain ⟨hpre, -⟩ := Frag.seq_at (by simpa [opFrag, smRemFrag] using hat)
      obtain ⟨pc, d, rs, as, regs, mem⟩ := s
      simp only at hpc
      refine ⟨fun st' h => ?_, fun t h => ?_⟩
      · rcases d with _ | ⟨v, _ | ⟨hi, _ | ⟨lo, d⟩⟩⟩ <;> simp only [Op.sem] at h <;> try cases h
        split at h
        · rename_i hc
          cases h
          obtain ⟨s', hs, hpc', hrs, hd', hm', ha'⟩ :=
            smRem_ok hat ⟨pc, v :: hi :: lo :: d, rs, as, regs, mem⟩ hpc rfl hc
          exact ⟨s', hs, hpc', hrs, hd', hm', ha'⟩
        · cases h
      · rcases d with _ | ⟨v, _ | ⟨hi, _ | ⟨lo, d⟩⟩⟩
        all_goals first
          | (simp only [Op.sem] at h; cases h
             exact execSeq_trap smRemPre_straight (by show At p pc _; rw [hpc]; exact hpre)
               (smRemPre_under _ (by simp)))
          | skip
        simp only [Op.sem] at h
        split at h
        · cases h
        · rename_i hc
          cases h
          exact smRem_err hat ⟨pc, v :: hi :: lo :: d, rs, as, regs, mem⟩ hpc rfl hc
    all_goals
      have hmod : At p base ((starSlashModFrag : Frag n).emit base) := by
        first
          | simpa [opFrag] using hat
          | exact starSlashFrag_mod (by simpa [opFrag] using hat)
      obtain ⟨pc, d, rs, as, regs, mem⟩ := s
      simp only at hpc
      refine ⟨fun st' h => ?_, fun t h => ?_⟩
      · rcases d with _ | ⟨c, _ | ⟨b, _ | ⟨a, d⟩⟩⟩ <;> simp only [Op.sem] at h <;> try cases h
        split at h
        · rename_i hc
          cases h
          first
            | (obtain ⟨s', hs, hpc', hrs, hd', hm', ha'⟩ :=
                starSlashMod_ok hmod ⟨pc, c :: b :: a :: d, rs, as, regs, mem⟩ hpc rfl hc
               exact ⟨s', hs, hpc', hrs, hd', hm', ha'⟩)
            | (obtain ⟨s', hs, hpc', hrs, hd', hm', ha'⟩ :=
                starSlash_ok (by simpa [opFrag] using hat) ⟨pc, c :: b :: a :: d, rs, as, regs, mem⟩
                  hpc rfl hc
               exact ⟨s', hs, hpc', hrs, hd', hm', ha'⟩)
        · cases h
      · rcases d with _ | ⟨c, _ | ⟨b, _ | ⟨a, d⟩⟩⟩
        all_goals first
          | (simp only [Op.sem] at h; cases h
             exact starSlashMod_under hmod _ hpc (by simp))
          | skip
        simp only [Op.sem] at h
        split at h
        · cases h
        · rename_i hc
          cases h
          exact starSlashMod_err hmod ⟨pc, c :: b :: a :: d, rs, as, regs, mem⟩ hpc rfl hc

end Forth
end WordDialect
