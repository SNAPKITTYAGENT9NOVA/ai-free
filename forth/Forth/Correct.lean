import Forth.OpCorrect

/-!
# Forth.Correct

Translation correctness of the Forth lowering.

`compile_correct`: whenever the Forth reference semantics derives a result `r` for block `b`
from state `st` (with dictionary `defs`), the machine — running any program that contains every
word body at its address followed by `RET` (`DefsAt`), started at the block's address with a
matching data stack, memory and auxiliary stack (= the Forth return-data stack) and *any*
return stack — either
* reaches (via `Steps`) the end of the block's code with data stack, memory and auxiliary
  stack equal to the Forth result's data stack, memory and return-data stack, and the return
  stack (of code addresses) unchanged, or
* (for an `EXIT`) reaches a `RET` instruction with that data stack, memory and auxiliary stack
  and the return stack unchanged, or
* reaches a state whose next step traps with exactly the trap Forth reports.

The induction is on the `Run` derivation, which for a call contains the callee's derivation,
so recursive words need no separate argument. Likewise `Run.doAgain` contains the derivation of
the next iteration, which the compiled loop starts by jumping back to its `SWAP TOR TOR` entry.

`Program.compile_correct` lifts this to a whole program (main block plus dictionary) run from
the initial machine state (an `EXIT` run by the main block itself returns with an empty return
stack, so the machine traps `returnUnderflow`; the parser rejects `EXIT` outside a definition);
`compileProgram_correct` is the special case without definitions.
-/

namespace WordDialect
namespace Forth

open IR

/-- The machine realizes result `r`. For `ok` it ends at address `e`; for `exit` it ends at a
`RET` instruction (the code of `EXIT`); in both cases with return stack `rs`. -/
def Reaches {n : Nat} (p : Prog n) (s : State n) (e : Nat) (rs : List Nat) :
    Res n → Prop
  | .ok st' => ∃ s', Steps p s s' ∧ s'.pc = e ∧ s'.rstack = rs ∧ s'.dstack = st'.stack ∧
      s'.mem = st'.mem ∧ s'.astack = st'.rstack
  | .exit st' => ∃ s', Steps p s s' ∧ p[s'.pc]? = some .ret ∧ s'.rstack = rs ∧
      s'.dstack = st'.stack ∧ s'.mem = st'.mem ∧ s'.astack = st'.rstack
  | .error t => ∃ s1, Steps p s s1 ∧ step p s1 = .trapped t

theorem reaches_trans {n : Nat} {p : Prog n} {s s1 : State n} {e : Nat} {rs : List Nat}
    {r : Res n} (h1 : Steps p s s1) (h2 : Reaches p s1 e rs r) :
    Reaches p s e rs r := by
  cases r with
  | ok st' =>
    obtain ⟨s', hs, hpc, hrs, hd, hm, ha⟩ := h2
    exact ⟨s', h1.trans hs, hpc, hrs, hd, hm, ha⟩
  | exit st' =>
    obtain ⟨s', hs, hpc, hrs, hd, hm, ha⟩ := h2
    exact ⟨s', h1.trans hs, hpc, hrs, hd, hm, ha⟩
  | error t =>
    obtain ⟨s2, hs, ht⟩ := h2
    exact ⟨s2, h1.trans hs, ht⟩

theorem reaches_cast {n : Nat} {p : Prog n} {s : State n} {e e' : Nat} {rs rs' : List Nat}
    {r : Res n} (h : e = e') (hrs : rs = rs') (hr : Reaches p s e rs r) :
    Reaches p s e' rs' r := by
  subst h; subst hrs; exact hr

/-- The end address does not matter for an abrupt result. -/
theorem reaches_abrupt {n : Nat} {p : Prog n} {s : State n} {e e' : Nat} {rs : List Nat}
    {r : Res n} (hk : r.isOk = false) (hr : Reaches p s e rs r) : Reaches p s e' rs r := by
  cases r with
  | ok _ => cases hk
  | exit _ => exact hr
  | error _ => exact hr

/-- A word body realizing a result that returns `st1` reaches a `RET` (the one after the body,
or an `EXIT`) with the data stack and memory of `st1`. -/
theorem reaches_returned {n : Nat} {p : Prog n} {s : State n} {e : Nat} {rs : List Nat}
    {r : Res n} {st1 : FState n} (hret : p[e]? = some .ret) (hr : Reaches p s e rs r)
    (h : r.returned = some st1) :
    ∃ s', Steps p s s' ∧ p[s'.pc]? = some .ret ∧ s'.rstack = rs ∧ s'.dstack = st1.stack ∧
      s'.mem = st1.mem ∧ s'.astack = st1.rstack := by
  cases r with
  | ok st' =>
    cases h
    obtain ⟨s', hs, hpc, hrs, hd, hm, ha⟩ := hr
    exact ⟨s', hs, by rw [hpc]; exact hret, hrs, hd, hm, ha⟩
  | exit st' => cases h; exact hr
  | error _ => cases h

/-- Every word of `defs` is in `p` at `addr i`, followed by `RET`; the address of an index
outside the dictionary is outside `p`. -/
def DefsAt {n : Nat} (p : Prog n) (addr : Nat → Nat) (defs : List Block) : Prop :=
  (∀ i body, defs[i]? = some body →
    At p (addr i) ((compile addr body : Frag n).emit (addr i) ++ [.ret])) ∧
  (∀ i, defs[i]? = none → p[addr i]? = none)

section Sizes
variable {n : Nat} (addr : Nat → Nat)

theorem size_op (o : Op) (rest : Block) :
    (compile addr (.op o rest) : Frag n).size =
      (compileOp o : List (Instr n)).length + (compile addr rest : Frag n).size := rfl

theorem size_ite (t e rest : Block) :
    (compile addr (.ite t e rest) : Frag n).size =
      ((compile addr e : Frag n).size + (compile addr t : Frag n).size + 2) +
        (compile addr rest : Frag n).size := rfl

theorem size_until (body rest : Block) :
    (compile addr (.untilL body rest) : Frag n).size =
      ((compile addr body : Frag n).size + 2) + (compile addr rest : Frag n).size := rfl

theorem size_call (i : Nat) (rest : Block) :
    (compile addr (.call i rest) : Frag n).size = 1 + (compile addr rest : Frag n).size := rfl

theorem size_exit (rest : Block) :
    (compile addr (.exit rest) : Frag n).size = 1 + (compile addr rest : Frag n).size := rfl

theorem size_doLoop (body rest : Block) :
    (compile addr (.doLoop body rest) : Frag n).size =
      ((3 + ((compile addr body : Frag n).size + 8)) + 1) + (2 + (compile addr rest : Frag n).size) :=
  rfl

end Sizes

theorem fstate_eta {n : Nat} (st : FState n) : (⟨st.stack, st.mem, st.rstack⟩ : FState n) = st := by
  cases st; rfl

/-! ## The code of `DO … LOOP` -/

section Loop
variable {n : Nat}

theorem loopEnter_straight : ∀ i ∈ (loopEnter : List (Instr n)), i.isStraight = true := by
  simp [loopEnter, Instr.isStraight]

theorem loopTest_straight : ∀ i ∈ (loopTest : List (Instr n)), i.isStraight = true := by
  simp [loopTest, Instr.isStraight]

theorem loopLeave_straight : ∀ i ∈ (loopLeave : List (Instr n)), i.isStraight = true := by
  simp [loopLeave, Instr.isStraight]

theorem loopEnter_ok (s : State n) {i l : Word n} {d : List (Word n)}
    (hd : s.dstack = i :: l :: d) :
    execSeq loopEnter s =
      .next { s with pc := s.pc + 3, dstack := d, astack := i :: l :: s.astack } := by
  obtain ⟨pc, d', rs, as, regs, mem⟩ := s
  simp only at hd; subst hd
  simp [loopEnter, execSeq, exec, State.fall, Nat.add_assoc]

theorem loopEnter_under (s : State n) (h : s.dstack.length < 2) :
    execSeq loopEnter s = .trapped .stackUnderflow := by
  obtain ⟨pc, d, rs, as, regs, mem⟩ := s
  rcases d with _ | ⟨x, _ | ⟨y, d⟩⟩
  · simp [loopEnter, execSeq, exec]
  · simp [loopEnter, execSeq, exec]
  · simp at h; omega

theorem loopTest_ok (s : State n) {i l : Word n} {rs : List (Word n)}
    (ha : s.astack = i :: l :: rs) :
    execSeq loopTest s =
      .next { s with pc := s.pc + 8,
                     dstack := (l - (i + 1#n)) :: (i + 1#n) :: l :: s.dstack, astack := rs } := by
  obtain ⟨pc, d, rs', as, regs, mem⟩ := s
  simp only at ha; subst ha
  simp [loopTest, execSeq, exec, State.fall, Nat.add_assoc]

theorem loopTest_under (s : State n) (h : s.astack.length < 2) :
    execSeq loopTest s = .trapped .returnUnderflow := by
  obtain ⟨pc, d, rs, as, regs, mem⟩ := s
  rcases as with _ | ⟨x, _ | ⟨y, as⟩⟩
  · simp [loopTest, execSeq, exec]
  · simp [loopTest, execSeq, exec, State.fall]
  · simp at h; omega

theorem loopLeave_ok (s : State n) {a b : Word n} {d : List (Word n)}
    (hd : s.dstack = a :: b :: d) :
    execSeq loopLeave s = .next { s with pc := s.pc + 2, dstack := d } := by
  obtain ⟨pc, d', rs, as, regs, mem⟩ := s
  simp only at hd; subst hd
  simp [loopLeave, execSeq, exec, State.fall, Nat.add_assoc]

theorem isTrue_sub_self {l k : Word n} (h : k = l) : Word.isTrue (l - k) = false := by
  subst h; simp [Word.isTrue]

theorem isTrue_sub_ne {l k : Word n} (h : k ≠ l) : Word.isTrue (l - k) = true := by
  simp only [Word.isTrue, bne_iff_ne, ne_eq]
  intro h'
  apply h
  have := congrArg (· + k) h'
  simp only [BitVec.sub_add_cancel] at this
  simp at this
  exact this.symm

theorem doLoop_decode {p : Prog n} {addr : Nat → Nat} {body rest : Block} {base : Nat}
    (hat : At p base ((compile addr (.doLoop body rest) : Frag n).emit base)) :
    At p base loopEnter ∧
    At p (base + 3) ((compile addr body : Frag n).emit (base + 3)) ∧
    At p (base + 3 + (compile addr body : Frag n).size) loopTest ∧
    p[base + 3 + (compile addr body : Frag n).size + 8]? = some (.branch base) ∧
    At p (base + 3 + (compile addr body : Frag n).size + 9) loopLeave ∧
    At p (base + 3 + (compile addr body : Frag n).size + 11)
      ((compile addr rest : Frag n).emit (base + 3 + (compile addr body : Frag n).size + 11)) := by
  have hat0 : At p base (((Frag.repeatLoop ((Frag.ofCode loopEnter).seq
      ((compile addr body : Frag n).seq (Frag.ofCode loopTest)))).seq
      ((Frag.ofCode loopLeave).seq (compile addr rest))).emit base) := hat
  obtain ⟨h1, h2⟩ := Frag.seq_at hat0
  obtain ⟨hB, hbr⟩ := repeat_decode h1
  obtain ⟨hE, hB2⟩ := Frag.seq_at hB
  obtain ⟨hBody, hT⟩ := Frag.seq_at hB2
  obtain ⟨hL, hR⟩ := Frag.seq_at h2
  simp only [Frag.ofCode, Frag.seq, Frag.repeatLoop] at hE hBody hT hbr hL hR
  have e3 : (loopEnter : List (Instr n)).length = 3 := rfl
  have e8 : (loopTest : List (Instr n)).length = 8 := rfl
  have e2 : (loopLeave : List (Instr n)).length = 2 := rfl
  simp only [e3, e8, e2] at hE hBody hT hbr hL hR
  refine ⟨hE, hBody, ?_, ?_, ?_, ?_⟩
  · simpa [Nat.add_assoc] using hT
  · simpa [Nat.add_assoc] using hbr
  · have e : base + (3 + ((compile addr body : Frag n).size + 8) + 1) =
        base + 3 + (compile addr body : Frag n).size + 9 := by omega
    rw [e] at hL; exact hL
  · have e : base + (3 + ((compile addr body : Frag n).size + 8) + 1) + 2 =
        base + 3 + (compile addr body : Frag n).size + 11 := by omega
    rw [e] at hR; exact hR

end Loop

theorem compile_correct {n : Nat} {defs : List Block} {addr : Nat → Nat} {p : Prog n}
    (hdefs : DefsAt p addr defs) {b : Block} {st : FState n} {r : Res n}
    (h : Run defs b st r) :
    ∀ (base : Nat) (s : State n),
      At p base ((compile addr b : Frag n).emit base) → s.pc = base →
      s.dstack = st.stack → s.mem = st.mem → s.astack = st.rstack →
      Reaches p s (base + (compile addr b : Frag n).size) s.rstack r := by
  induction h with
  | nil =>
    intro base s _ hpc hd hm ha
    exact ⟨s, .refl, by simp [compile, Frag.empty, Frag.ofCode, hpc], rfl, hd, hm, ha⟩
  | @exit rest st =>
    intro base s hat hpc hd hm ha
    have hat' := Frag.seq_at (by simpa [compile] using hat)
    have hret : p[s.pc]? = some .ret := by
      rw [hpc]; simpa [Frag.ofCode, At] using hat'.1
    exact ⟨s, .refl, hret, rfl, hd, hm, ha⟩
  | @opOk o rest st st' r hs _ ih =>
    intro base s hat hpc hd hm ha
    have hat' := Frag.seq_at (by simpa [compile] using hat)
    have hcode : At p base (compileOp o : List (Instr n)) := by
      simpa [Frag.ofCode] using hat'.1
    have hrest : At p (base + (compileOp o : List (Instr n)).length)
        ((compile addr rest : Frag n).emit (base + (compileOp o : List (Instr n)).length)) := by
      simpa [Frag.ofCode] using hat'.2
    have hsem : o.sem ⟨s.dstack, s.mem, s.astack⟩ = .ok st' := by
      rw [hd, hm, ha, fstate_eta]; exact hs
    have hx := compileOp_ok o s st' hsem
    obtain ⟨hst, hpc'⟩ := execSeq_steps (compileOp_straight o) (by rw [hpc]; exact hcode) hx
    have := ih (base + (compileOp o : List (Instr n)).length)
      { s with pc := s.pc + (compileOp o : List (Instr n)).length, dstack := st'.stack,
               mem := st'.mem, astack := st'.rstack } hrest
      (by simp [hpc]) rfl rfl rfl
    refine reaches_cast ?_ rfl (reaches_trans hst this)
    rw [size_op]; omega
  | @opErr o rest st t hs =>
    intro base s hat hpc hd hm ha
    have hat' := Frag.seq_at (by simpa [compile] using hat)
    have hcode : At p base (compileOp o : List (Instr n)) := by
      simpa [Frag.ofCode] using hat'.1
    have hsem : o.sem ⟨s.dstack, s.mem, s.astack⟩ = .error t := by
      rw [hd, hm, ha, fstate_eta]; exact hs
    have hx := compileOp_err o s t hsem
    exact execSeq_trap (compileOp_straight o) (by rw [hpc]; exact hcode) hx
  | @iteUnder t e rest m rs =>
    intro base s hat hpc hd hm ha
    have hat' := Frag.seq_at (by simpa [compile] using hat)
    obtain ⟨h1, _, _, _⟩ := ite_decode hat'.1
    refine ⟨s, .refl, ?_⟩
    rw [step_of_fetch (by rw [hpc]; exact h1)]
    exact exec_underflow _ s (by simp [hd, Instr.pops])
  | @iteTrue t e rest c d m rs st1 r hc _ _ iht ihr =>
    intro base s hat hpc hd hm ha
    have hat' := Frag.seq_at (by simpa [compile] using hat)
    obtain ⟨_, _, _, ht⟩ := ite_decode hat'.1
    have h1 := ite_true_rule hat'.1 hpc hd hc
    have h2 := iht _ { s with pc := base + 2 + (compile addr e : Frag n).size, dstack := d } ht
      rfl rfl hm ha
    obtain ⟨s2, hs2, hpc2, hrs2, hd2, hm2, ha2⟩ := h2
    have h3 := ihr (base + (Frag.ite (compile addr t) (compile addr e) : Frag n).size) s2
      (by simpa using hat'.2)
      (by rw [Frag.ite_size]; omega) hd2 hm2 ha2
    refine reaches_cast ?_ hrs2 (reaches_trans (h1.trans hs2) h3)
    rw [size_ite, Frag.ite_size]; omega
  | @iteTrueStop t e rest c d m rs r hc _ hk iht =>
    intro base s hat hpc hd hm ha
    have hat' := Frag.seq_at (by simpa [compile] using hat)
    obtain ⟨_, _, _, ht⟩ := ite_decode hat'.1
    have h1 := ite_true_rule hat'.1 hpc hd hc
    have h2 := iht _ { s with pc := base + 2 + (compile addr e : Frag n).size, dstack := d } ht
      rfl rfl hm ha
    exact reaches_abrupt hk (reaches_trans h1 h2)
  | @iteFalse t e rest c d m rs st1 r hc _ _ ihe ihr =>
    intro base s hat hpc hd hm ha
    have hat' := Frag.seq_at (by simpa [compile] using hat)
    obtain ⟨_, he, _, _⟩ := ite_decode hat'.1
    have h2 := ihe (base + 1) { s with pc := base + 1, dstack := d } he rfl rfl hm ha
    obtain ⟨s2, hs2, hpc2, hrs2, hd2, hm2, ha2⟩ := h2
    have h1 := ite_false_rule hat'.1 hpc hd hc hs2 hpc2
    have h3 := ihr (base + (Frag.ite (compile addr t) (compile addr e) : Frag n).size)
      { s2 with pc := base + 2 + (compile addr e : Frag n).size + (compile addr t : Frag n).size }
      (by simpa using hat'.2)
      (by
        show base + 2 + (compile addr e : Frag n).size + (compile addr t : Frag n).size = _
        rw [Frag.ite_size]; omega) hd2 hm2 ha2
    refine reaches_cast ?_ hrs2 (reaches_trans h1 h3)
    rw [size_ite, Frag.ite_size]; omega
  | @iteFalseStop t e rest c d m rs r hc _ hk ihe =>
    intro base s hat hpc hd hm ha
    have hat' := Frag.seq_at (by simpa [compile] using hat)
    obtain ⟨h0, he, _, _⟩ := ite_decode hat'.1
    have hfall := step_branch_fall (s := s) (by rw [hpc]; exact h0) hd hc
    rw [hpc] at hfall
    have h2 := ihe (base + 1) { s with pc := base + 1, dstack := d } he rfl rfl hm ha
    exact reaches_abrupt hk (reaches_trans (.single hfall) h2)
  | @untilBodyStop body rest st r _ hk ihb =>
    intro base s hat hpc hd hm ha
    have hat' := Frag.seq_at (by simpa [compile] using hat)
    obtain ⟨hb, _, _⟩ := until_decode hat'.1
    exact reaches_abrupt hk (ihb base s hb hpc hd hm ha)
  | @untilUnder body rest st m rs _ ihb =>
    intro base s hat hpc hd hm ha
    have hat' := Frag.seq_at (by simpa [compile] using hat)
    obtain ⟨hb, h2, _⟩ := until_decode hat'.1
    obtain ⟨s1, hs1, hpc1, _, hd1, hm1, -⟩ := ihb base s hb hpc hd hm ha
    refine ⟨s1, hs1, ?_⟩
    rw [step_of_fetch (by rw [hpc1]; exact h2)]
    exact exec_underflow _ s1 (by simp [hd1, Instr.pops])
  | @untilDone body rest st c d m rs r _ hc _ ihb ihr =>
    intro base s hat hpc hd hm ha
    have hat' := Frag.seq_at (by simpa [compile] using hat)
    obtain ⟨hb, _, _⟩ := until_decode hat'.1
    obtain ⟨s1, hs1, hpc1, hrs1, hd1, hm1, ha1⟩ := ihb base s hb hpc hd hm ha
    have h1 := until_exit_rule hat'.1 hpc1 hd1 hc
    have h3 := ihr (base + (Frag.untilLoop (compile addr body) : Frag n).size)
      { s1 with pc := base + (compile addr body : Frag n).size + 2, dstack := d }
      (by simpa using hat'.2)
      (by show base + (compile addr body : Frag n).size + 2 = _; rw [Frag.until_size]; omega)
      rfl hm1 ha1
    refine reaches_cast ?_ hrs1 (reaches_trans (hs1.trans h1) h3)
    rw [size_until, Frag.until_size]; omega
  | @untilAgain body rest st c d m rs r _ hc _ ihb ihl =>
    intro base s hat hpc hd hm ha
    obtain ⟨s1, hs1, hpc1, hrs1, hd1, hm1, ha1⟩ := ihb base s
      (until_decode (Frag.seq_at (by simpa [compile] using hat)).1).1 hpc hd hm ha
    have h1 := until_again_rule (Frag.seq_at (by simpa [compile] using hat)).1 hpc1 hd1 hc
    have h3 := ihl base { s1 with pc := base, dstack := d } hat rfl rfl hm1 ha1
    exact reaches_cast rfl hrs1 (reaches_trans (hs1.trans h1) h3)
  | @callOk i rest st body r1 st1 r hi _ hr1 _ ihb ihr =>
    intro base s hat hpc hd hm ha
    have hat' := Frag.seq_at (by simpa [compile] using hat)
    have hcall : p[s.pc]? = some (.call (addr i)) := by
      rw [hpc]; simpa [Frag.ofCode, At] using hat'.1
    obtain ⟨hbody, hret⟩ := at_append.mp (hdefs.1 i body hi)
    have hret' : p[addr i + (compile addr body : Frag n).size]? = some .ret := by
      simpa [At, Frag.len] using hret
    obtain ⟨s2, hs2, hpc2, hrs2, hd2, hm2, ha2⟩ := reaches_returned hret'
      (ihb (addr i) { s with pc := addr i, rstack := (s.pc + 1) :: s.rstack } hbody rfl hd hm ha)
      hr1
    have h2 : step p s2 = .next { s2 with pc := s.pc + 1, rstack := s.rstack } :=
      step_ret hpc2 hrs2
    have h3 := ihr (base + 1) { s2 with pc := s.pc + 1, rstack := s.rstack }
      (by simpa [Frag.ofCode] using hat'.2) (by simp [hpc]) hd2 hm2 ha2
    refine reaches_cast ?_ rfl
      (reaches_trans (.cons (step_call hcall) (hs2.trans (.single h2))) h3)
    rw [size_call]; omega
  | @callErr i rest st body x hi _ ihb =>
    intro base s hat hpc hd hm ha
    have hat' := Frag.seq_at (by simpa [compile] using hat)
    have hcall : p[s.pc]? = some (.call (addr i)) := by
      rw [hpc]; simpa [Frag.ofCode, At] using hat'.1
    have hbody := (at_append.mp (hdefs.1 i body hi)).1
    exact reaches_trans (.single (step_call hcall))
      (ihb (addr i) { s with pc := addr i, rstack := (s.pc + 1) :: s.rstack } hbody rfl hd hm ha)
  | @callUndef i rest st hi =>
    intro base s hat hpc hd hm ha
    have hat' := Frag.seq_at (by simpa [compile] using hat)
    have hcall : p[s.pc]? = some (.call (addr i)) := by
      rw [hpc]; simpa [Frag.ofCode, At] using hat'.1
    refine ⟨_, .single (step_call hcall), ?_⟩
    simp [step, hdefs.2 i hi]
  | @doUnder body rest st hl =>
    intro base s hat hpc hd hm ha
    obtain ⟨hE, -⟩ := doLoop_decode hat
    exact execSeq_trap loopEnter_straight (by rw [hpc]; exact hE)
      (loopEnter_under s (by rw [hd]; exact hl))
  | @doBodyStop body rest i l d m rs r _ hk ihb =>
    intro base s hat hpc hd hm ha
    obtain ⟨hE, hBody, -⟩ := doLoop_decode hat
    obtain ⟨hst, hpc1⟩ := execSeq_steps loopEnter_straight (by rw [hpc]; exact hE)
      (loopEnter_ok s hd)
    have h1 := ihb (base + 3) { s with pc := s.pc + 3, dstack := d, astack := i :: l :: s.astack }
      hBody (by simp [hpc]) rfl hm (by simp [ha])
    exact reaches_abrupt hk (reaches_trans hst h1)
  | @doTestUnder body rest i l d m rs st1 _ hl ihb =>
    intro base s hat hpc hd hm ha
    obtain ⟨hE, hBody, hT, -⟩ := doLoop_decode hat
    obtain ⟨hst, -⟩ := execSeq_steps loopEnter_straight (by rw [hpc]; exact hE)
      (loopEnter_ok s hd)
    obtain ⟨s2, hs2, hpc2, -, -, -, ha2⟩ := ihb (base + 3)
      { s with pc := s.pc + 3, dstack := d, astack := i :: l :: s.astack }
      hBody (by simp [hpc]) rfl hm (by simp [ha])
    obtain ⟨s3, hs3, ht⟩ := execSeq_trap loopTest_straight (by rw [hpc2]; exact hT)
      (loopTest_under s2 (by rw [ha2]; exact hl))
    exact ⟨s3, hst.trans (hs2.trans hs3), ht⟩
  | @doDone body rest i l d m rs i1 l1 d1 m1 rs1 r _ he _ ihb ihr =>
    intro base s hat hpc hd hm ha
    obtain ⟨hE, hBody, hT, hbr, hL, hR⟩ := doLoop_decode hat
    obtain ⟨hst, -⟩ := execSeq_steps loopEnter_straight (by rw [hpc]; exact hE)
      (loopEnter_ok s hd)
    obtain ⟨s2, hs2, hpc2, hrs2, hd2, hm2, ha2⟩ := ihb (base + 3)
      { s with pc := s.pc + 3, dstack := d, astack := i :: l :: s.astack }
      hBody (by simp [hpc]) rfl hm (by simp [ha])
    obtain ⟨hs3, hpc3⟩ := execSeq_steps loopTest_straight (by rw [hpc2]; exact hT)
      (loopTest_ok s2 ha2)
    have hfall := step_branch_fall (by rw [hpc3, hpc2]; exact hbr) rfl
      (isTrue_sub_self he)
    obtain ⟨hs5, -⟩ := execSeq_steps loopLeave_straight
      (s := { s2 with pc := s2.pc + 8 + 1, astack := rs1,
                      dstack := (i1 + 1#n) :: l1 :: s2.dstack })
      (by simp only [hpc2]; exact hL) (loopLeave_ok _ rfl)
    have h6 := ihr (base + 3 + (compile addr body : Frag n).size + 11)
      { s2 with pc := s2.pc + 8 + 1 + 2, astack := rs1, dstack := s2.dstack } hR
      (by simp only [hpc2]) hd2 hm2 rfl
    refine reaches_cast ?_ hrs2
      (reaches_trans (hst.trans (hs2.trans (hs3.trans (.cons hfall hs5)))) h6)
    rw [size_doLoop]; omega
  | @doAgain body rest i l d m rs i1 l1 d1 m1 rs1 r _ hne _ ihb ihl =>
    intro base s hat hpc hd hm ha
    obtain ⟨hE, hBody, hT, hbr, -⟩ := doLoop_decode hat
    obtain ⟨hst, -⟩ := execSeq_steps loopEnter_straight (by rw [hpc]; exact hE)
      (loopEnter_ok s hd)
    obtain ⟨s2, hs2, hpc2, hrs2, hd2, hm2, ha2⟩ := ihb (base + 3)
      { s with pc := s.pc + 3, dstack := d, astack := i :: l :: s.astack }
      hBody (by simp [hpc]) rfl hm (by simp [ha])
    obtain ⟨hs3, hpc3⟩ := execSeq_steps loopTest_straight (by rw [hpc2]; exact hT)
      (loopTest_ok s2 ha2)
    have htaken := step_branch_taken (by rw [hpc3, hpc2]; exact hbr) rfl
      (isTrue_sub_ne hne)
    have h5 := ihl base
      ({ s2 with pc := base, astack := rs1, dstack := (i1 + 1#n) :: l1 :: s2.dstack } : State n)
      hat rfl
      (by simp [hd2]) hm2 rfl
    exact reaches_cast rfl hrs2
      (reaches_trans (hst.trans (hs2.trans (hs3.trans (.single htaken)))) h5)

/-- The dictionary laid out by `emitDefs` after any code `pre` satisfies `DefsAt` for the
addresses `wordAddr`. -/
theorem emitDefs_layout {n : Nat} (addr : Nat → Nat) :
    ∀ (defs : List Block) (pre : Prog n) (base : Nat), pre.length = base →
      (∀ i body, defs[i]? = some body →
        At (pre ++ emitDefs addr base defs) (wordAddr base defs i)
          ((compile addr body : Frag n).emit (wordAddr base defs i) ++ [Instr.ret])) ∧
      (∀ i, defs[i]? = none → (pre ++ emitDefs addr base defs)[wordAddr base defs i]? = none) := by
  intro defs
  induction defs with
  | nil =>
    intro pre base hlen
    refine ⟨fun i body h => by simp at h, fun i _ => ?_⟩
    simp [wordAddr, emitDefs, ← hlen]
  | cons b bs ih =>
    intro pre base hlen
    have hlen' : (pre ++ ((compile addr b : Frag n).emit base ++ [Instr.ret])).length =
        base + b.size + 1 := by
      simp [Frag.len, compile_size, hlen]; omega
    have hp : pre ++ emitDefs addr base (b :: bs) =
        (pre ++ ((compile addr b : Frag n).emit base ++ [.ret])) ++
          emitDefs addr (base + b.size + 1) bs := by
      simp [emitDefs, List.append_assoc]
    obtain ⟨ih1, ih2⟩ := ih _ _ hlen'
    refine ⟨fun i body h => ?_, fun i h => ?_⟩
    · cases i with
      | zero =>
        simp only [List.getElem?_cons_zero, Option.some.injEq] at h
        subst h
        rw [hp]
        have := at_embed pre ((compile addr b : Frag n).emit base ++ [.ret])
          (emitDefs addr (base + b.size + 1) bs)
        simpa [wordAddr, hlen, List.append_assoc] using this
      | succ i =>
        simp only [List.getElem?_cons_succ] at h
        rw [hp]; exact ih1 i body h
    · cases i with
      | zero => simp at h
      | succ i =>
        simp only [List.getElem?_cons_succ] at h
        rw [hp]; exact ih2 i h

theorem Program.defsAt {n : Nat} (P : Program) :
    DefsAt (P.compile : Prog n) P.addr P.defs := by
  have hlen : ((Forth.compile P.addr P.main : Frag n).emit 0 ++ [Instr.halt]).length =
      P.main.size + 1 := by
    simp [Frag.len, compile_size]
  exact emitDefs_layout P.addr P.defs _ _ hlen

/-- Whole-program correctness from the initial machine state (empty stacks, given memory),
for a program with colon definitions. -/
theorem Program.compile_correct {n : Nat} {P : Program} {mem : Memory n}
    {r : Res n} (h : Run P.defs P.main ⟨[], mem, []⟩ r) :
    match r with
    | .ok st' =>
        ∃ s', Exec (P.compile : Prog n) (State.init mem) (.halted s') ∧
          s'.dstack = st'.stack ∧ s'.mem = st'.mem ∧ s'.astack = st'.rstack
    | .exit _ => Exec (P.compile : Prog n) (State.init mem) (.trapped .returnUnderflow)
    | .error t => Exec (P.compile : Prog n) (State.init mem) (.trapped t) := by
  have hat : At (P.compile : Prog n) 0 ((Forth.compile P.addr P.main : Frag n).emit 0) := by
    have := at_embed ([] : Prog n) ((Forth.compile P.addr P.main : Frag n).emit 0)
      ([.halt] ++ emitDefs P.addr (P.main.size + 1) P.defs)
    simpa [Program.compile, List.append_assoc] using this
  have key := Forth.compile_correct (Program.defsAt P) h 0 (State.init mem) hat rfl rfl rfl rfl
  cases r with
  | ok st' =>
    obtain ⟨s', hs, hpc, _, hd, hm, ha⟩ := key
    have hfetch : (P.compile : Prog n)[s'.pc]? = some .halt := by
      rw [hpc]
      simp [Program.compile,
        (Forth.compile P.addr P.main : Frag n).len, List.append_assoc]
    refine ⟨s', Exec.of_steps hs (.halt ?_), hd, hm, ha⟩
    rw [step_of_fetch hfetch]; rfl
  | exit st' =>
    obtain ⟨s', hs, hret, hrs, _, _, _⟩ := key
    refine Exec.of_steps hs (.trap ?_)
    simp [step, hret, exec, hrs, State.init]
  | error t =>
    obtain ⟨s1, hs, ht⟩ := key
    exact Exec.of_steps hs (.trap ht)

/-- Whole-program correctness for a block with no definitions. -/
theorem compileProgram_correct {n : Nat} {b : Block} {mem : Memory n}
    {r : Res n} (h : Run [] b ⟨[], mem, []⟩ r) :
    match r with
    | .ok st' =>
        ∃ s', Exec (compileProgram b : Prog n) (State.init mem) (.halted s') ∧
          s'.dstack = st'.stack ∧ s'.mem = st'.mem ∧ s'.astack = st'.rstack
    | .exit _ => Exec (compileProgram b : Prog n) (State.init mem) (.trapped .returnUnderflow)
    | .error t => Exec (compileProgram b : Prog n) (State.init mem) (.trapped t) :=
  by cases r <;> exact Program.compile_correct (P := { defs := [], main := b }) h

end Forth
end WordDialect
