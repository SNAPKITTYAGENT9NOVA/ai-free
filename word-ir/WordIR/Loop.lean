import WordIR.Frag

/-!
# WordIR.Loop

`countedLoop r N body` runs `body` for `r = 0, 1, …, N-1`, using virtual register `r` as the
counter:

    r := 0;  while r <u N do { body; r := r + 1 }

`countedLoop_run` is the verified loop rule. Given an invariant `Inv k` that holds before
iteration `k`, and a proof that the body takes any state satisfying `Inv k` (with counter
`k`, positioned at the body) to a state satisfying `Inv (k+1)` with the counter and data
stack preserved, the loop reaches its end with `Inv N`, counter `N`, and the data stack as
it found it.

The invariant may depend on the memory, the data stack, the return stack and every register
other than `r`; it must not depend on the program counter or on `r` (`hstab`).
-/

namespace WordDialect
namespace IR

def initCode {n : Nat} (r : Nat) : List (Instr n) := [.word 0#n, .pop r]

def condCode {n : Nat} (r N : Nat) : List (Instr n) :=
  [.push r, .word (BitVec.ofNat n N), .cmp .ult]

def incCode {n : Nat} (r : Nat) : List (Instr n) := [.push r, .word 1#n, .add, .pop r]

def countedLoop {n : Nat} (r N : Nat) (body : Frag n) : Frag n :=
  (Frag.ofCode (initCode r)).seq
    (Frag.whileLoop (Frag.ofCode (condCode r N)) (body.seq (Frag.ofCode (incCode r))))

theorem countedLoop_size {n : Nat} (r N : Nat) (body : Frag n) :
    (countedLoop r N body).size = body.size + 12 := by
  simp [countedLoop, Frag.seq_size, Frag.while_size, Frag.ofCode_size, initCode, condCode, incCode]
  omega

theorem initCode_straight {n : Nat} (r : Nat) :
    ∀ i ∈ (initCode r : List (Instr n)), i.isStraight = true := by
  simp [initCode, Instr.isStraight]

theorem condCode_straight {n : Nat} (r N : Nat) :
    ∀ i ∈ (condCode r N : List (Instr n)), i.isStraight = true := by
  simp [condCode, Instr.isStraight]

theorem incCode_straight {n : Nat} (r : Nat) :
    ∀ i ∈ (incCode r : List (Instr n)), i.isStraight = true := by
  simp [incCode, Instr.isStraight]

theorem ult_ofNat {n : Nat} {k N : Nat} (hk : k < 2 ^ n) (hN : N < 2 ^ n) :
    (BitVec.ofNat n k).ult (BitVec.ofNat n N) = decide (k < N) := by
  simp [BitVec.ult, BitVec.toNat_ofNat, Nat.mod_eq_of_lt hk, Nat.mod_eq_of_lt hN]

theorem initCode_run {n : Nat} (r : Nat) (s : State n) :
    execSeq (initCode r) s =
      .next { s with pc := s.pc + 2, regs := State.setReg s.regs r 0#n } := by
  simp [initCode, execSeq, exec, State.fall]

theorem condCode_run {n : Nat} (r N : Nat) (s : State n) :
    execSeq (condCode r N) s =
      .next { s with pc := s.pc + 3, dstack := Word.ofBool ((s.regs r).ult (BitVec.ofNat n N)) :: s.dstack } := by
  simp [condCode, execSeq, exec, State.fall, Cond.eval]

theorem incCode_run {n : Nat} (r : Nat) (s : State n) :
    execSeq (incCode r) s =
      .next { s with pc := s.pc + 4, regs := State.setReg s.regs r (s.regs r + 1#n) } := by
  simp [incCode, execSeq, exec, State.fall, BitVec.add_comm]

/-- Where the loop body sits: at `b + 7`. -/
theorem countedLoop_body_at {n : Nat} {p : Prog n} {b r N : Nat} {body : Frag n}
    (hat : At p b ((countedLoop r N body).emit b)) :
    At p (b + 7) (body.emit (b + 7)) := by
  have hat' := Frag.seq_at (by simpa [countedLoop] using hat)
  have hw : At p (b + 2) ((Frag.whileLoop (Frag.ofCode (condCode r N))
      (body.seq (Frag.ofCode (incCode r)))).emit (b + 2)) := by
    simpa [Frag.ofCode, initCode] using hat'.2
  obtain ⟨_, _, _, hb_at, _⟩ := while_decode hw
  have hb_at' := Frag.seq_at hb_at
  simpa [Frag.ofCode, condCode] using hb_at'.1

theorem countedLoop_run {n : Nat} (hn : 0 < n) {p : Prog n} {b r N : Nat} {body : Frag n}
    (hN : N < 2 ^ n) (hat : At p b ((countedLoop r N body).emit b))
    (Inv : Nat → State n → Prop)
    (hstab : ∀ k s s', Inv k s → s'.mem = s.mem → s'.dstack = s.dstack →
      s'.rstack = s.rstack → (∀ j, j ≠ r → s'.regs j = s.regs j) → Inv k s')
    (hbody : ∀ k s, k < N → Inv k s → s.pc = b + 7 → s.regs r = BitVec.ofNat n k →
      ∃ s', Steps p s s' ∧ s'.pc = b + 7 + body.size ∧ s'.regs r = BitVec.ofNat n k ∧
        s'.dstack = s.dstack ∧ Inv (k + 1) s')
    (s0 : State n) (hpc : s0.pc = b) (h0 : Inv 0 s0) :
    ∃ s', Steps p s0 s' ∧ s'.pc = b + body.size + 12 ∧ s'.regs r = BitVec.ofNat n N ∧
      s'.dstack = s0.dstack ∧ Inv N s' := by
  have hat' := Frag.seq_at (by simpa [countedLoop] using hat)
  have hinit : At p b (initCode r) := by simpa [Frag.ofCode] using hat'.1
  have hw : At p (b + 2) ((Frag.whileLoop (Frag.ofCode (condCode r N))
      (body.seq (Frag.ofCode (incCode r)))).emit (b + 2)) := by
    simpa [Frag.ofCode, initCode] using hat'.2
  obtain ⟨hc_at, _, _, hb_at, _⟩ := while_decode hw
  have hcond_at : At p (b + 2) (condCode r N) := by simpa [Frag.ofCode] using hc_at
  have hb_at' := Frag.seq_at hb_at
  have hbody_at : At p (b + 2 + 3 + 2) (body.emit (b + 2 + 3 + 2)) := by
    simpa [Frag.ofCode, condCode] using hb_at'.1
  have hinc_at : At p (b + 2 + 3 + 2 + body.size) (incCode r) := by
    simpa [Frag.ofCode, condCode] using hb_at'.2
  -- Main induction over the remaining iteration count.
  have key : ∀ d k (s : State n), N - k = d → k ≤ N → Inv k s → s.pc = b + 2 →
      s.regs r = BitVec.ofNat n k →
      ∃ s', Steps p s s' ∧ s'.pc = b + body.size + 12 ∧ s'.regs r = BitVec.ofNat n N ∧
        s'.dstack = s.dstack ∧ Inv N s' := by
    intro d
    induction d with
    | zero =>
      intro k s hd hk hI hpc hr
      have hkN : k = N := by omega
      subst hkN
      have hx := condCode_run r k s
      obtain ⟨hst, hpc1⟩ := execSeq_steps (condCode_straight r k) (by rw [hpc]; exact hcond_at) hx
      have hult : (s.regs r).ult (BitVec.ofNat n k) = false := by
        rw [hr, ult_ofNat (by omega) hN]; simp
      have h1 := while_exit_rule hw
        (s1 := { s with pc := s.pc + 3, dstack := Word.ofBool ((s.regs r).ult (BitVec.ofNat n k)) :: s.dstack })
        (by simp [hpc, Frag.ofCode, condCode]) rfl
        (by rw [hult]; exact Word.isTrue_ofBool hn false)
      refine ⟨_, hst.trans h1, ?_, hr, rfl, ?_⟩
      · simp [Frag.seq_size, Frag.ofCode_size, condCode, incCode, Frag.ofCode]; omega
      · exact hstab k s _ hI rfl rfl rfl (fun _ _ => rfl)
    | succ d ih =>
      intro k s hd hk hI hpc hr
      have hkN : k < N := by omega
      have hx := condCode_run r N s
      obtain ⟨hst, hpc1⟩ := execSeq_steps (condCode_straight r N) (by rw [hpc]; exact hcond_at) hx
      have hult : (s.regs r).ult (BitVec.ofNat n N) = true := by
        rw [hr, ult_ofNat (by omega) hN]; simpa using hkN
      have h1 := while_enter_rule hw
        (s1 := { s with pc := s.pc + 3, dstack := Word.ofBool ((s.regs r).ult (BitVec.ofNat n N)) :: s.dstack })
        (by simp [hpc, Frag.ofCode, condCode]) rfl
        (by rw [hult]; exact Word.isTrue_ofBool hn true)
      have hI2 : Inv k { s with pc := b + 2 + 3 + 2 } :=
        hstab k s _ hI rfl rfl rfl (fun _ _ => rfl)
      obtain ⟨s3, hs3, hpc3, hr3, hd3, hI3⟩ := hbody k
        { s with pc := b + 2 + 3 + 2 } hkN hI2 (by simp) (by simpa using hr)
      have hx4 := incCode_run r s3
      obtain ⟨hst4, hpc4⟩ := execSeq_steps (incCode_straight r)
        (by rw [hpc3]; simpa using hinc_at) hx4
      have h5 := while_back_rule hw
        (s1 := { s3 with pc := s3.pc + 4, regs := State.setReg s3.regs r (s3.regs r + 1#n) })
        (by simp [hpc3, Frag.ofCode, condCode, Frag.seq_size, incCode]; omega)
      have hr5 : (BitVec.ofNat n k + 1#n) = BitVec.ofNat n (k + 1) := by
        rw [BitVec.ofNat_add]
      have hI5 : Inv (k + 1) { s3 with pc := b + 2, regs := State.setReg s3.regs r (s3.regs r + 1#n) } :=
        hstab (k + 1) s3 _ hI3 rfl rfl rfl (by intro j hj; simp [State.setReg, hj])
      obtain ⟨s', hs', hpc', hr', hd', hI'⟩ := ih (k + 1)
        { s3 with pc := b + 2, regs := State.setReg s3.regs r (s3.regs r + 1#n) }
        (by omega) (by omega) hI5 rfl (by simp [State.setReg, hr3, hr5])
      refine ⟨s', ((hst.trans h1).trans hs3 |>.trans hst4).trans (h5.trans hs'), hpc', hr', ?_, hI'⟩
      rw [hd']; simp [hd3]
  -- Initialisation: r := 0.
  have hx0 := initCode_run r s0
  obtain ⟨hst0, hpc0⟩ := execSeq_steps (initCode_straight r) (by rw [hpc]; exact hinit) hx0
  have hI1 : Inv 0 { s0 with pc := s0.pc + 2, regs := State.setReg s0.regs r 0#n } :=
    hstab 0 s0 _ h0 rfl rfl rfl (by intro j hj; simp [State.setReg, hj])
  obtain ⟨s', hs', hpc', hr', hd', hI'⟩ := key N 0
    { s0 with pc := s0.pc + 2, regs := State.setReg s0.regs r 0#n }
    (by omega) (by omega) hI1 (by simp [hpc]) (by simp [State.setReg])
  exact ⟨s', hst0.trans hs', hpc', hr', hd', hI'⟩

/-- `countedLoop_run` with the auxiliary stack: a body that leaves it unchanged leaves it
unchanged through the whole loop, and the invariant may also assume it is unchanged. -/
theorem countedLoop_run' {n : Nat} (hn : 0 < n) {p : Prog n} {b r N : Nat} {body : Frag n}
    (hN : N < 2 ^ n) (hat : At p b ((countedLoop r N body).emit b))
    (Inv : Nat → State n → Prop)
    (hstab : ∀ k s s', Inv k s → s'.mem = s.mem → s'.dstack = s.dstack →
      s'.rstack = s.rstack → s'.astack = s.astack → (∀ j, j ≠ r → s'.regs j = s.regs j) →
      Inv k s')
    (hbody : ∀ k s, k < N → Inv k s → s.pc = b + 7 → s.regs r = BitVec.ofNat n k →
      ∃ s', Steps p s s' ∧ s'.pc = b + 7 + body.size ∧ s'.regs r = BitVec.ofNat n k ∧
        s'.dstack = s.dstack ∧ s'.astack = s.astack ∧ s'.rstack = s.rstack ∧ Inv (k + 1) s')
    (s0 : State n) (hpc : s0.pc = b) (h0 : Inv 0 s0) :
    ∃ s', Steps p s0 s' ∧ s'.pc = b + body.size + 12 ∧ s'.regs r = BitVec.ofNat n N ∧
      s'.dstack = s0.dstack ∧ s'.astack = s0.astack ∧ s'.rstack = s0.rstack ∧ Inv N s' := by
  have hat' := Frag.seq_at (by simpa [countedLoop] using hat)
  have hinit : At p b (initCode r) := by simpa [Frag.ofCode] using hat'.1
  have hw : At p (b + 2) ((Frag.whileLoop (Frag.ofCode (condCode r N))
      (body.seq (Frag.ofCode (incCode r)))).emit (b + 2)) := by
    simpa [Frag.ofCode, initCode] using hat'.2
  obtain ⟨hc_at, _, _, hb_at, _⟩ := while_decode hw
  have hcond_at : At p (b + 2) (condCode r N) := by simpa [Frag.ofCode] using hc_at
  have hb_at' := Frag.seq_at hb_at
  have hbody_at : At p (b + 2 + 3 + 2) (body.emit (b + 2 + 3 + 2)) := by
    simpa [Frag.ofCode, condCode] using hb_at'.1
  have hinc_at : At p (b + 2 + 3 + 2 + body.size) (incCode r) := by
    simpa [Frag.ofCode, condCode] using hb_at'.2
  -- Main induction over the remaining iteration count.
  have key : ∀ d k (s : State n), N - k = d → k ≤ N → Inv k s → s.pc = b + 2 →
      s.regs r = BitVec.ofNat n k →
      ∃ s', Steps p s s' ∧ s'.pc = b + body.size + 12 ∧ s'.regs r = BitVec.ofNat n N ∧
        s'.dstack = s.dstack ∧ s'.astack = s.astack ∧ s'.rstack = s.rstack ∧ Inv N s' := by
    intro d
    induction d with
    | zero =>
      intro k s hd hk hI hpc hr
      have hkN : k = N := by omega
      subst hkN
      have hx := condCode_run r k s
      obtain ⟨hst, hpc1⟩ := execSeq_steps (condCode_straight r k) (by rw [hpc]; exact hcond_at) hx
      have hult : (s.regs r).ult (BitVec.ofNat n k) = false := by
        rw [hr, ult_ofNat (by omega) hN]; simp
      have h1 := while_exit_rule hw
        (s1 := { s with pc := s.pc + 3, dstack := Word.ofBool ((s.regs r).ult (BitVec.ofNat n k)) :: s.dstack })
        (by simp [hpc, Frag.ofCode, condCode]) rfl
        (by rw [hult]; exact Word.isTrue_ofBool hn false)
      refine ⟨_, hst.trans h1, ?_, hr, rfl, rfl, rfl, ?_⟩
      · simp [Frag.seq_size, Frag.ofCode_size, condCode, incCode, Frag.ofCode]; omega
      · exact hstab k s _ hI rfl rfl rfl rfl (fun _ _ => rfl)
    | succ d ih =>
      intro k s hd hk hI hpc hr
      have hkN : k < N := by omega
      have hx := condCode_run r N s
      obtain ⟨hst, hpc1⟩ := execSeq_steps (condCode_straight r N) (by rw [hpc]; exact hcond_at) hx
      have hult : (s.regs r).ult (BitVec.ofNat n N) = true := by
        rw [hr, ult_ofNat (by omega) hN]; simpa using hkN
      have h1 := while_enter_rule hw
        (s1 := { s with pc := s.pc + 3, dstack := Word.ofBool ((s.regs r).ult (BitVec.ofNat n N)) :: s.dstack })
        (by simp [hpc, Frag.ofCode, condCode]) rfl
        (by rw [hult]; exact Word.isTrue_ofBool hn true)
      have hI2 : Inv k { s with pc := b + 2 + 3 + 2 } :=
        hstab k s _ hI rfl rfl rfl rfl (fun _ _ => rfl)
      obtain ⟨s3, hs3, hpc3, hr3, hd3, ha3, hrs3, hI3⟩ := hbody k
        { s with pc := b + 2 + 3 + 2 } hkN hI2 (by simp) (by simpa using hr)
      have hx4 := incCode_run r s3
      obtain ⟨hst4, hpc4⟩ := execSeq_steps (incCode_straight r)
        (by rw [hpc3]; simpa using hinc_at) hx4
      have h5 := while_back_rule hw
        (s1 := { s3 with pc := s3.pc + 4, regs := State.setReg s3.regs r (s3.regs r + 1#n) })
        (by simp [hpc3, Frag.ofCode, condCode, Frag.seq_size, incCode]; omega)
      have hr5 : (BitVec.ofNat n k + 1#n) = BitVec.ofNat n (k + 1) := by
        rw [BitVec.ofNat_add]
      have hI5 : Inv (k + 1) { s3 with pc := b + 2, regs := State.setReg s3.regs r (s3.regs r + 1#n) } :=
        hstab (k + 1) s3 _ hI3 rfl rfl rfl rfl (by intro j hj; simp [State.setReg, hj])
      obtain ⟨s', hs', hpc', hr', hd', ha', hrs', hI'⟩ := ih (k + 1)
        { s3 with pc := b + 2, regs := State.setReg s3.regs r (s3.regs r + 1#n) }
        (by omega) (by omega) hI5 rfl (by simp [State.setReg, hr3, hr5])
      refine ⟨s', ((hst.trans h1).trans hs3 |>.trans hst4).trans (h5.trans hs'), hpc', hr', ?_, ?_,
        ?_, hI'⟩
      · rw [hd']; simp [hd3]
      · rw [ha']; simp [ha3]
      · rw [hrs']; simp [hrs3]
  -- Initialisation: r := 0.
  have hx0 := initCode_run r s0
  obtain ⟨hst0, hpc0⟩ := execSeq_steps (initCode_straight r) (by rw [hpc]; exact hinit) hx0
  have hI1 : Inv 0 { s0 with pc := s0.pc + 2, regs := State.setReg s0.regs r 0#n } :=
    hstab 0 s0 _ h0 rfl rfl rfl rfl (by intro j hj; simp [State.setReg, hj])
  obtain ⟨s', hs', hpc', hr', hd', ha', hrs', hI'⟩ := key N 0
    { s0 with pc := s0.pc + 2, regs := State.setReg s0.regs r 0#n }
    (by omega) (by omega) hI1 (by simp [hpc]) (by simp [State.setReg])
  exact ⟨s', hst0.trans hs', hpc', hr', hd', ha', hrs', hI'⟩


end IR
end WordDialect
