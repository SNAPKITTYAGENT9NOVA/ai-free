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
* (for a `LEAVE`) reaches the leave target the block was compiled with (the end of the
  innermost enclosing loop) with that data stack, memory and auxiliary stack, or
* reaches a state whose next step traps with exactly the trap Forth reports.

The induction is on the `Run` derivation, which for a call contains the callee's derivation,
so recursive words need no separate argument. Likewise `Run.doAgain` and `Run.plusAgain` contain
the derivation of the next iteration, which the compiled loop starts by jumping back to its
`SWAP TOR TOR` entry. The leave target is a parameter of the induction: a loop proves its body
with its own end address.

`Program.compile_correct` lifts this to a whole program (main block plus dictionary) run from
the initial machine state (an `EXIT` run by the main block itself returns with an empty return
stack, so the machine traps `returnUnderflow`; the parser rejects `EXIT` outside a definition;
a `LEAVE` outside any loop of the main block reaches its `HALT`);
`compileProgram_correct` is the special case without definitions.
-/

namespace WordDialect
namespace Forth

open IR

/-- The machine realizes result `r`. For `ok` it ends at address `e`; for `exit` it ends at a
`RET` instruction (the code of `EXIT`); for `leave` it ends at the leave target `lv`, the loop
parameters already removed; in all three cases with return stack `rs`. -/
def Reaches {n : Nat} (p : Prog n) (s : State n) (e lv : Nat) (rs : List Nat) :
    Res n → Prop
  | .ok st' => ∃ s', Steps p s s' ∧ s'.pc = e ∧ s'.rstack = rs ∧ s'.dstack = st'.stack ∧
      s'.mem = st'.mem ∧ s'.astack = st'.rstack
  | .exit st' => ∃ s', Steps p s s' ∧ p[s'.pc]? = some .ret ∧ s'.rstack = rs ∧
      s'.dstack = st'.stack ∧ s'.mem = st'.mem ∧ s'.astack = st'.rstack
  | .leave st' => ∃ s', Steps p s s' ∧ s'.pc = lv ∧ s'.rstack = rs ∧ s'.dstack = st'.stack ∧
      s'.mem = st'.mem ∧ s'.astack = st'.rstack
  | .error t => ∃ s1, Steps p s s1 ∧ step p s1 = .trapped t

theorem reaches_trans {n : Nat} {p : Prog n} {s s1 : State n} {e lv : Nat} {rs : List Nat}
    {r : Res n} (h1 : Steps p s s1) (h2 : Reaches p s1 e lv rs r) :
    Reaches p s e lv rs r := by
  cases r with
  | ok st' =>
    obtain ⟨s', hs, hpc, hrs, hd, hm, ha⟩ := h2
    exact ⟨s', h1.trans hs, hpc, hrs, hd, hm, ha⟩
  | exit st' =>
    obtain ⟨s', hs, hpc, hrs, hd, hm, ha⟩ := h2
    exact ⟨s', h1.trans hs, hpc, hrs, hd, hm, ha⟩
  | leave st' =>
    obtain ⟨s', hs, hpc, hrs, hd, hm, ha⟩ := h2
    exact ⟨s', h1.trans hs, hpc, hrs, hd, hm, ha⟩
  | error t =>
    obtain ⟨s2, hs, ht⟩ := h2
    exact ⟨s2, h1.trans hs, ht⟩

theorem reaches_cast {n : Nat} {p : Prog n} {s : State n} {e e' lv : Nat} {rs rs' : List Nat}
    {r : Res n} (h : e = e') (hrs : rs = rs') (hr : Reaches p s e lv rs r) :
    Reaches p s e' lv rs' r := by
  subst h; subst hrs; exact hr

/-- The end address does not matter for an abrupt result. -/
theorem reaches_abrupt {n : Nat} {p : Prog n} {s : State n} {e e' lv : Nat} {rs : List Nat}
    {r : Res n} (hk : r.isOk = false) (hr : Reaches p s e lv rs r) : Reaches p s e' lv rs r := by
  cases r with
  | ok _ => cases hk
  | exit _ => exact hr
  | leave _ => exact hr
  | error _ => exact hr

/-- Neither the end address nor the leave target matters for `EXIT` or a trap. -/
theorem reaches_stop {n : Nat} {p : Prog n} {s : State n} {e e' lv lv' : Nat} {rs : List Nat}
    {r : Res n} (hk : r.isStop = true) (hr : Reaches p s e lv rs r) :
    Reaches p s e' lv' rs r := by
  cases r with
  | ok _ => cases hk
  | leave _ => cases hk
  | exit _ => exact hr
  | error _ => exact hr

/-- A word body (compiled with the `RET` after it, at `e`, as its leave target) realizing a
result that returns `st1` reaches a `RET` with the data stack and memory of `st1`. -/
theorem reaches_returned {n : Nat} {p : Prog n} {s : State n} {e : Nat} {rs : List Nat}
    {r : Res n} {st1 : FState n} (hret : p[e]? = some .ret) (hr : Reaches p s e e rs r)
    (h : r.returned = some st1) :
    ∃ s', Steps p s s' ∧ p[s'.pc]? = some .ret ∧ s'.rstack = rs ∧ s'.dstack = st1.stack ∧
      s'.mem = st1.mem ∧ s'.astack = st1.rstack := by
  cases r with
  | ok st' =>
    cases h
    obtain ⟨s', hs, hpc, hrs, hd, hm, ha⟩ := hr
    exact ⟨s', hs, by rw [hpc]; exact hret, hrs, hd, hm, ha⟩
  | leave st' =>
    cases h
    obtain ⟨s', hs, hpc, hrs, hd, hm, ha⟩ := hr
    exact ⟨s', hs, by rw [hpc]; exact hret, hrs, hd, hm, ha⟩
  | exit st' => cases h; exact hr
  | error _ => cases h

/-- Every word of `defs` is in `p` at `addr i`, followed by `RET` (its leave target); the
address of an index outside the dictionary is outside `p`. -/
def DefsAt {n : Nat} (p : Prog n) (addr : Nat → Nat) (defs : List Block) : Prop :=
  (∀ i body, defs[i]? = some body →
    At p (addr i) ((compile addr (addr i + body.size) body : Frag n).emit (addr i) ++ [.ret])) ∧
  (∀ i, defs[i]? = none → p[addr i]? = none)

section Sizes
variable {n : Nat} (addr : Nat → Nat) (lv : Nat)

theorem size_op (o : Op) (rest : Block) :
    (compile addr lv (.op o rest) : Frag n).size =
      (compileOp o : List (Instr n)).length + (compile addr lv rest : Frag n).size := rfl

theorem size_ite (t e rest : Block) :
    (compile addr lv (.ite t e rest) : Frag n).size =
      ((compile addr lv e : Frag n).size + (compile addr lv t : Frag n).size + 2) +
        (compile addr lv rest : Frag n).size := rfl

theorem size_until (body rest : Block) :
    (compile addr lv (.untilL body rest) : Frag n).size =
      ((compile addr lv body : Frag n).size + 2) + (compile addr lv rest : Frag n).size := rfl

theorem size_call (i : Nat) (rest : Block) :
    (compile addr lv (.call i rest) : Frag n).size = 1 + (compile addr lv rest : Frag n).size := rfl

theorem size_exit (rest : Block) :
    (compile addr lv (.exit rest) : Frag n).size = 1 + (compile addr lv rest : Frag n).size := rfl

theorem size_leave (rest : Block) :
    (compile addr lv (.leave rest) : Frag n).size = 5 + (compile addr lv rest : Frag n).size := rfl

theorem size_doLoop (body rest : Block) :
    (compile addr lv (.doLoop body rest) : Frag n).size =
      (body.size + 14) + (compile addr lv rest : Frag n).size := rfl

theorem size_plusLoop (body rest : Block) :
    (compile addr lv (.plusLoop body rest) : Frag n).size =
      (body.size + 33) + (compile addr lv rest : Frag n).size := rfl

end Sizes

theorem fstate_eta {n : Nat} (st : FState n) : (⟨st.stack, st.mem, st.rstack⟩ : FState n) = st := by
  cases st; rfl

/-! ## The code of `DO … LOOP` and `DO … +LOOP` -/

section Loop
variable {n : Nat}

theorem loopEnter_straight : ∀ i ∈ (loopEnter : List (Instr n)), i.isStraight = true := by
  simp [loopEnter, Instr.isStraight]

theorem loopTest_straight : ∀ i ∈ (loopTest : List (Instr n)), i.isStraight = true := by
  simp [loopTest, Instr.isStraight]

theorem loopLeave_straight : ∀ i ∈ (loopLeave : List (Instr n)), i.isStraight = true := by
  simp [loopLeave, Instr.isStraight]

theorem plusTest_straight : ∀ i ∈ (plusTest : List (Instr n)), i.isStraight = true := by
  simp [plusTest, Instr.isStraight]

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

theorem plus_index (i l k : Word n) : l + (k + (i - l)) = i + k := by
  rw [BitVec.add_comm k, ← BitVec.add_assoc, BitVec.add_comm l (i - l), BitVec.sub_add_cancel]

theorem plusTest_ok (s : State n) {i l k : Word n} {d rs : List (Word n)}
    (hd : s.dstack = k :: d) (ha : s.astack = i :: l :: rs) :
    execSeq plusTest s =
      .next { s with pc := s.pc + 26,
                     dstack := Word.ofBool (loopCrossed i l k) :: (i + k) :: l :: d,
                     astack := rs } := by
  obtain ⟨pc, d', rs', as, regs, mem⟩ := s
  simp only at hd ha; subst hd ha
  simp [plusTest, execSeq, exec, State.fall, Nat.add_assoc, loopCrossed, Cond.eval, plus_index]

theorem plusTest_underR (s : State n) (h : s.astack.length < 2) :
    execSeq plusTest s = .trapped .returnUnderflow := by
  obtain ⟨pc, d, rs, as, regs, mem⟩ := s
  rcases as with _ | ⟨x, _ | ⟨y, as⟩⟩
  · simp [plusTest, execSeq, exec]
  · simp [plusTest, execSeq, exec]
  · simp at h; omega

theorem plusTest_underD (s : State n) {i l : Word n} {rs : List (Word n)}
    (hd : s.dstack = []) (ha : s.astack = i :: l :: rs) :
    execSeq plusTest s = .trapped .stackUnderflow := by
  obtain ⟨pc, d, rs', as, regs, mem⟩ := s
  simp only at hd ha; subst hd ha
  simp [plusTest, execSeq, exec, State.fall]

theorem unloop_code_ok (s : State n) {a b : Word n} {rs : List (Word n)}
    (ha : s.astack = a :: b :: rs) :
    execSeq (compileOp .unloop) s = .next { s with pc := s.pc + 4, astack := rs } := by
  obtain ⟨pc, d, rs', as, regs, mem⟩ := s
  simp only at ha; subst ha
  simp [compileOp, execSeq, exec, State.fall, Nat.add_assoc]

/-- The `+LOOP` flag is the branch condition, for every width (at `n = 0` both are `false`). -/
theorem isTrue_crossed (i l k : Word n) :
    Word.isTrue (Word.ofBool (n := n) (loopCrossed i l k)) = loopCrossed i l k := by
  rcases Nat.eq_zero_or_pos n with h | h
  · subst h
    have hx : ∀ x : BitVec 0, x = 0#0 := fun x => BitVec.eq_of_toNat_eq (by
      have := x.isLt; simp at this ⊢; omega)
    have : loopCrossed i l k = false := by
      simp only [loopCrossed, Cond.eval]; rw [hx (_ &&& _)]; decide
    rw [this]; simp [Word.isTrue, Word.ofBool]
  · exact Word.isTrue_ofBool h _

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

theorem at_cast {p : Prog n} {a b : Nat} {c : List (Instr n)} (h : a = b) (hc : At p a c) :
    At p b c := h ▸ hc

theorem doLoop_decode {p : Prog n} {addr : Nat → Nat} {lv : Nat} {body rest : Block} {base : Nat}
    (hat : At p base ((compile addr lv (.doLoop body rest) : Frag n).emit base)) :
    At p base loopEnter ∧
    At p (base + 3) ((compile addr (base + body.size + 14) body : Frag n).emit (base + 3)) ∧
    At p (base + 3 + body.size) loopTest ∧
    p[base + 3 + body.size + 8]? = some (.branch base) ∧
    At p (base + 3 + body.size + 9) loopLeave ∧
    At p (base + body.size + 14) ((compile addr lv rest : Frag n).emit (base + body.size + 14)) := by
  rw [compile_doLoop] at hat
  obtain ⟨h1, h2⟩ := Frag.seq_at hat
  have e3 : (loopEnter : List (Instr n)).length = 3 := rfl
  have e8 : (loopTest : List (Instr n)).length = 8 := rfl
  simp only [loopFrag, at_append, List.length_append, Frag.len, compile_size, e3, e8,
    List.length_singleton, At] at h1 h2
  obtain ⟨⟨⟨⟨hE, hB⟩, hT⟩, hbr, -⟩, hL⟩ := h1
  refine ⟨hE, hB, at_cast (by omega) hT, ?_, at_cast (by omega) hL, at_cast (by omega) h2⟩
  have e : base + (3 + body.size + 8) = base + 3 + body.size + 8 := by omega
  rw [← e]; exact hbr

theorem plusLoop_decode {p : Prog n} {addr : Nat → Nat} {lv : Nat} {body rest : Block} {base : Nat}
    (hat : At p base ((compile addr lv (.plusLoop body rest) : Frag n).emit base)) :
    At p base loopEnter ∧
    At p (base + 3) ((compile addr (base + body.size + 33) body : Frag n).emit (base + 3)) ∧
    At p (base + 3 + body.size) plusTest ∧
    p[base + 3 + body.size + 26]? = some (.branch (base + body.size + 31)) ∧
    p[base + 3 + body.size + 27]? = some (.jmp base) ∧
    At p (base + body.size + 31) loopLeave ∧
    At p (base + body.size + 33) ((compile addr lv rest : Frag n).emit (base + body.size + 33)) := by
  rw [compile_plusLoop] at hat
  obtain ⟨h1, h2⟩ := Frag.seq_at hat
  have e3 : (loopEnter : List (Instr n)).length = 3 := rfl
  have e26 : (plusTest : List (Instr n)).length = 26 := rfl
  simp only [plusFrag, at_append, List.length_append, Frag.len, compile_size, e3, e26,
    List.length_cons, List.length_nil, At] at h1 h2
  obtain ⟨⟨⟨⟨hE, hB⟩, hT⟩, hbr, hj, -⟩, hL⟩ := h1
  refine ⟨hE, hB, at_cast (by omega) hT, ?_, ?_, at_cast (by omega) hL, at_cast (by omega) h2⟩
  · have e : base + (3 + body.size + 26) = base + 3 + body.size + 26 := by omega
    rw [← e]; exact hbr
  · have e : base + (3 + body.size + 26) + 1 = base + 3 + body.size + 27 := by omega
    rw [← e]; exact hj

end Loop

/-- **Translation correctness of a block.** -/
theorem compile_correct {n : Nat} {defs : List Block} {addr : Nat → Nat} {p : Prog n}
    (hdefs : DefsAt p addr defs) {b : Block} {st : FState n} {r : Res n}
    (h : Run defs b st r) :
    ∀ (lv base : Nat) (s : State n),
      At p base ((compile addr lv b : Frag n).emit base) → s.pc = base →
      s.dstack = st.stack → s.mem = st.mem → s.astack = st.rstack →
      Reaches p s (base + (compile addr lv b : Frag n).size) lv s.rstack r := by
  induction h with
  | nil =>
    intro lv base s _ hpc hd hm ha
    exact ⟨s, .refl, by simp [compile_nil, Frag.empty, Frag.ofCode, hpc], rfl, hd, hm, ha⟩
  | @exit rest st =>
    intro lv base s hat hpc hd hm ha
    rw [compile_exit] at hat
    have hat' := Frag.seq_at hat
    have hret : p[s.pc]? = some .ret := by
      rw [hpc]; simpa [Frag.ofCode, At] using hat'.1
    exact ⟨s, .refl, hret, rfl, hd, hm, ha⟩
  | @leaveOk rest d m a b rs =>
    intro lv base s hat hpc hd hm ha
    rw [compile_leave] at hat
    have hat' := Frag.seq_at hat
    have hcode := at_append.mp (by simpa [Frag.ofCode] using hat'.1)
    obtain ⟨hst, hpc1⟩ := execSeq_steps (compileOp_straight .unloop) (by rw [hpc]; exact hcode.1)
      (unloop_code_ok s ha)
    have hj : step p { s with pc := s.pc + 4, astack := rs } =
        .next { s with pc := lv, astack := rs } := by
      apply step_jmp
      simpa [hpc, compileOp, At] using hcode.2
    exact ⟨_, hst.trans (.single hj), rfl, rfl, hd, hm, rfl⟩
  | @leaveUnder rest st hl =>
    intro lv base s hat hpc hd hm ha
    rw [compile_leave] at hat
    have hat' := Frag.seq_at hat
    have hcode := at_append.mp (by simpa [Frag.ofCode] using hat'.1)
    have hsem : Op.unloop.sem ⟨s.dstack, s.mem, s.astack⟩ = .error .returnUnderflow := by
      obtain ⟨d, m, rs⟩ := st
      simp only at hl hd hm ha
      rw [ha]
      rcases rs with _ | ⟨x, _ | ⟨y, rs⟩⟩ <;> simp_all [Op.sem] <;> omega
    exact execSeq_trap (compileOp_straight .unloop) (by rw [hpc]; exact hcode.1)
      (compileOp_err .unloop s _ hsem)
  | @opOk o rest st st' r hs _ ih =>
    intro lv base s hat hpc hd hm ha
    rw [compile_op] at hat
    have hat' := Frag.seq_at hat
    have hcode : At p base (compileOp o : List (Instr n)) := by
      simpa [Frag.ofCode] using hat'.1
    have hrest : At p (base + (compileOp o : List (Instr n)).length)
        ((compile addr lv rest : Frag n).emit (base + (compileOp o : List (Instr n)).length)) := by
      simpa [Frag.ofCode] using hat'.2
    have hsem : o.sem ⟨s.dstack, s.mem, s.astack⟩ = .ok st' := by
      rw [hd, hm, ha, fstate_eta]; exact hs
    have hx := compileOp_ok o s st' hsem
    obtain ⟨hst, hpc'⟩ := execSeq_steps (compileOp_straight o) (by rw [hpc]; exact hcode) hx
    have := ih lv (base + (compileOp o : List (Instr n)).length)
      { s with pc := s.pc + (compileOp o : List (Instr n)).length, dstack := st'.stack,
               mem := st'.mem, astack := st'.rstack } hrest
      (by simp [hpc]) rfl rfl rfl
    refine reaches_cast ?_ rfl (reaches_trans hst this)
    rw [size_op]; omega
  | @opErr o rest st t hs =>
    intro lv base s hat hpc hd hm ha
    rw [compile_op] at hat
    have hat' := Frag.seq_at hat
    have hcode : At p base (compileOp o : List (Instr n)) := by
      simpa [Frag.ofCode] using hat'.1
    have hsem : o.sem ⟨s.dstack, s.mem, s.astack⟩ = .error t := by
      rw [hd, hm, ha, fstate_eta]; exact hs
    have hx := compileOp_err o s t hsem
    exact execSeq_trap (compileOp_straight o) (by rw [hpc]; exact hcode) hx
  | @iteUnder t e rest m rs =>
    intro lv base s hat hpc hd hm ha
    rw [compile_ite] at hat
    have hat' := Frag.seq_at hat
    obtain ⟨h1, _, _, _⟩ := ite_decode hat'.1
    refine ⟨s, .refl, ?_⟩
    rw [step_of_fetch (by rw [hpc]; exact h1)]
    exact exec_underflow _ s (by simp [hd, Instr.pops])
  | @iteTrue t e rest c d m rs st1 r hc _ _ iht ihr =>
    intro lv base s hat hpc hd hm ha
    rw [compile_ite] at hat
    have hat' := Frag.seq_at hat
    obtain ⟨_, _, _, ht⟩ := ite_decode hat'.1
    have h1 := ite_true_rule hat'.1 hpc hd hc
    have h2 := iht lv _ { s with pc := base + 2 + (compile addr lv e : Frag n).size, dstack := d } ht
      rfl rfl hm ha
    obtain ⟨s2, hs2, hpc2, hrs2, hd2, hm2, ha2⟩ := h2
    have h3 := ihr lv (base + (Frag.ite (compile addr lv t) (compile addr lv e) : Frag n).size) s2
      (by simpa using hat'.2)
      (by rw [Frag.ite_size]; omega) hd2 hm2 ha2
    refine reaches_cast ?_ hrs2 (reaches_trans (h1.trans hs2) h3)
    rw [size_ite, Frag.ite_size]; omega
  | @iteTrueStop t e rest c d m rs r hc _ hk iht =>
    intro lv base s hat hpc hd hm ha
    rw [compile_ite] at hat
    have hat' := Frag.seq_at hat
    obtain ⟨_, _, _, ht⟩ := ite_decode hat'.1
    have h1 := ite_true_rule hat'.1 hpc hd hc
    have h2 := iht lv _ { s with pc := base + 2 + (compile addr lv e : Frag n).size, dstack := d } ht
      rfl rfl hm ha
    exact reaches_abrupt hk (reaches_trans h1 h2)
  | @iteFalse t e rest c d m rs st1 r hc _ _ ihe ihr =>
    intro lv base s hat hpc hd hm ha
    rw [compile_ite] at hat
    have hat' := Frag.seq_at hat
    obtain ⟨_, he, _, _⟩ := ite_decode hat'.1
    have h2 := ihe lv (base + 1) { s with pc := base + 1, dstack := d } he rfl rfl hm ha
    obtain ⟨s2, hs2, hpc2, hrs2, hd2, hm2, ha2⟩ := h2
    have h1 := ite_false_rule hat'.1 hpc hd hc hs2 hpc2
    have h3 := ihr lv (base + (Frag.ite (compile addr lv t) (compile addr lv e) : Frag n).size)
      { s2 with pc := base + 2 + (compile addr lv e : Frag n).size + (compile addr lv t : Frag n).size }
      (by simpa using hat'.2)
      (by
        show base + 2 + (compile addr lv e : Frag n).size + (compile addr lv t : Frag n).size = _
        rw [Frag.ite_size]; omega) hd2 hm2 ha2
    refine reaches_cast ?_ hrs2 (reaches_trans h1 h3)
    rw [size_ite, Frag.ite_size]; omega
  | @iteFalseStop t e rest c d m rs r hc _ hk ihe =>
    intro lv base s hat hpc hd hm ha
    rw [compile_ite] at hat
    have hat' := Frag.seq_at hat
    obtain ⟨h0, he, _, _⟩ := ite_decode hat'.1
    have hfall := step_branch_fall (s := s) (by rw [hpc]; exact h0) hd hc
    rw [hpc] at hfall
    have h2 := ihe lv (base + 1) { s with pc := base + 1, dstack := d } he rfl rfl hm ha
    exact reaches_abrupt hk (reaches_trans (.single hfall) h2)
  | @untilBodyStop body rest st r _ hk ihb =>
    intro lv base s hat hpc hd hm ha
    rw [compile_until] at hat
    have hat' := Frag.seq_at hat
    obtain ⟨hb, _, _⟩ := until_decode hat'.1
    exact reaches_abrupt hk (ihb lv base s hb hpc hd hm ha)
  | @untilUnder body rest st m rs _ ihb =>
    intro lv base s hat hpc hd hm ha
    rw [compile_until] at hat
    have hat' := Frag.seq_at hat
    obtain ⟨hb, h2, _⟩ := until_decode hat'.1
    obtain ⟨s1, hs1, hpc1, _, hd1, hm1, -⟩ := ihb lv base s hb hpc hd hm ha
    refine ⟨s1, hs1, ?_⟩
    rw [step_of_fetch (by rw [hpc1]; exact h2)]
    exact exec_underflow _ s1 (by simp [hd1, Instr.pops])
  | @untilDone body rest st c d m rs r _ hc _ ihb ihr =>
    intro lv base s hat hpc hd hm ha
    rw [compile_until] at hat
    have hat' := Frag.seq_at hat
    obtain ⟨hb, _, _⟩ := until_decode hat'.1
    obtain ⟨s1, hs1, hpc1, hrs1, hd1, hm1, ha1⟩ := ihb lv base s hb hpc hd hm ha
    have h1 := until_exit_rule hat'.1 hpc1 hd1 hc
    have h3 := ihr lv (base + (Frag.untilLoop (compile addr lv body) : Frag n).size)
      { s1 with pc := base + (compile addr lv body : Frag n).size + 2, dstack := d }
      (by simpa using hat'.2)
      (by show base + (compile addr lv body : Frag n).size + 2 = _; rw [Frag.until_size]; omega)
      rfl hm1 ha1
    refine reaches_cast ?_ hrs1 (reaches_trans (hs1.trans h1) h3)
    rw [size_until, Frag.until_size]; omega
  | @untilAgain body rest st c d m rs r _ hc _ ihb ihl =>
    intro lv base s hat hpc hd hm ha
    have hat0 := hat
    rw [compile_until] at hat0
    obtain ⟨s1, hs1, hpc1, hrs1, hd1, hm1, ha1⟩ := ihb lv base s
      (until_decode (Frag.seq_at hat0).1).1 hpc hd hm ha
    have h1 := until_again_rule (Frag.seq_at hat0).1 hpc1 hd1 hc
    have h3 := ihl lv base { s1 with pc := base, dstack := d } hat rfl rfl hm1 ha1
    exact reaches_cast rfl hrs1 (reaches_trans (hs1.trans h1) h3)
  | @callOk i rest st body r1 st1 r hi _ hr1 _ ihb ihr =>
    intro lv base s hat hpc hd hm ha
    rw [compile_call] at hat
    have hat' := Frag.seq_at hat
    have hcall : p[s.pc]? = some (.call (addr i)) := by
      rw [hpc]; simpa [Frag.ofCode, At] using hat'.1
    obtain ⟨hbody, hret⟩ := at_append.mp (hdefs.1 i body hi)
    have hret' : p[addr i + (compile addr (addr i + body.size) body : Frag n).size]? = some .ret := by
      simpa [At, Frag.len] using hret
    have hb := ihb (addr i + body.size) (addr i)
      { s with pc := addr i, rstack := (s.pc + 1) :: s.rstack } hbody rfl hd hm ha
    rw [compile_size] at hb hret'
    obtain ⟨s2, hs2, hpc2, hrs2, hd2, hm2, ha2⟩ := reaches_returned hret' hb hr1
    have h2 : step p s2 = .next { s2 with pc := s.pc + 1, rstack := s.rstack } :=
      step_ret hpc2 hrs2
    have h3 := ihr lv (base + 1) { s2 with pc := s.pc + 1, rstack := s.rstack }
      (by simpa [Frag.ofCode] using hat'.2) (by simp [hpc]) hd2 hm2 ha2
    refine reaches_cast ?_ rfl
      (reaches_trans (.cons (step_call hcall) (hs2.trans (.single h2))) h3)
    rw [size_call]; omega
  | @callErr i rest st body x hi _ ihb =>
    intro lv base s hat hpc hd hm ha
    rw [compile_call] at hat
    have hat' := Frag.seq_at hat
    have hcall : p[s.pc]? = some (.call (addr i)) := by
      rw [hpc]; simpa [Frag.ofCode, At] using hat'.1
    have hbody := (at_append.mp (hdefs.1 i body hi)).1
    exact reaches_trans (.single (step_call hcall))
      (ihb (addr i + body.size) (addr i)
        { s with pc := addr i, rstack := (s.pc + 1) :: s.rstack } hbody rfl hd hm ha)
  | @callUndef i rest st hi =>
    intro lv base s hat hpc hd hm ha
    rw [compile_call] at hat
    have hat' := Frag.seq_at hat
    have hcall : p[s.pc]? = some (.call (addr i)) := by
      rw [hpc]; simpa [Frag.ofCode, At] using hat'.1
    refine ⟨_, .single (step_call hcall), ?_⟩
    simp [step, hdefs.2 i hi]
  | @doUnder body rest st hl =>
    intro lv base s hat hpc hd hm ha
    obtain ⟨hE, -⟩ := doLoop_decode hat
    exact execSeq_trap loopEnter_straight (by rw [hpc]; exact hE)
      (loopEnter_under s (by rw [hd]; exact hl))
  | @doBodyStop body rest i l d m rs r _ hk ihb =>
    intro lv base s hat hpc hd hm ha
    obtain ⟨hE, hBody, -⟩ := doLoop_decode hat
    obtain ⟨hst, hpc1⟩ := execSeq_steps loopEnter_straight (by rw [hpc]; exact hE)
      (loopEnter_ok s hd)
    have h1 := ihb _ (base + 3) { s with pc := s.pc + 3, dstack := d, astack := i :: l :: s.astack }
      hBody (by simp [hpc]) rfl hm (by simp [ha])
    exact reaches_stop hk (reaches_trans hst h1)
  | @doLeave body rest i l d m rs st1 r _ _ ihb ihr =>
    intro lv base s hat hpc hd hm ha
    obtain ⟨hE, hBody, -, -, -, hR⟩ := doLoop_decode hat
    obtain ⟨hst, -⟩ := execSeq_steps loopEnter_straight (by rw [hpc]; exact hE)
      (loopEnter_ok s hd)
    obtain ⟨s2, hs2, hpc2, hrs2, hd2, hm2, ha2⟩ := ihb _ (base + 3)
      { s with pc := s.pc + 3, dstack := d, astack := i :: l :: s.astack }
      hBody (by simp [hpc]) rfl hm (by simp [ha])
    have h3 := ihr lv (base + body.size + 14) s2 hR hpc2 hd2 hm2 ha2
    refine reaches_cast ?_ hrs2 (reaches_trans (hst.trans hs2) h3)
    rw [size_doLoop]; omega
  | @doTestUnder body rest i l d m rs st1 _ hl ihb =>
    intro lv base s hat hpc hd hm ha
    obtain ⟨hE, hBody, hT, -⟩ := doLoop_decode hat
    obtain ⟨hst, -⟩ := execSeq_steps loopEnter_straight (by rw [hpc]; exact hE)
      (loopEnter_ok s hd)
    obtain ⟨s2, hs2, hpc2, -, -, -, ha2⟩ := ihb _ (base + 3)
      { s with pc := s.pc + 3, dstack := d, astack := i :: l :: s.astack }
      hBody (by simp [hpc]) rfl hm (by simp [ha])
    rw [compile_size] at hpc2
    obtain ⟨s3, hs3, ht⟩ := execSeq_trap loopTest_straight (by rw [hpc2]; exact hT)
      (loopTest_under s2 (by rw [ha2]; exact hl))
    exact ⟨s3, hst.trans (hs2.trans hs3), ht⟩
  | @doDone body rest i l d m rs i1 l1 d1 m1 rs1 r _ he _ ihb ihr =>
    intro lv base s hat hpc hd hm ha
    obtain ⟨hE, hBody, hT, hbr, hL, hR⟩ := doLoop_decode hat
    obtain ⟨hst, -⟩ := execSeq_steps loopEnter_straight (by rw [hpc]; exact hE)
      (loopEnter_ok s hd)
    obtain ⟨s2, hs2, hpc2, hrs2, hd2, hm2, ha2⟩ := ihb _ (base + 3)
      { s with pc := s.pc + 3, dstack := d, astack := i :: l :: s.astack }
      hBody (by simp [hpc]) rfl hm (by simp [ha])
    rw [compile_size] at hpc2
    obtain ⟨hs3, hpc3⟩ := execSeq_steps loopTest_straight (by rw [hpc2]; exact hT)
      (loopTest_ok s2 ha2)
    have hfall := step_branch_fall (by rw [hpc3, hpc2]; exact hbr) rfl
      (isTrue_sub_self he)
    obtain ⟨hs5, -⟩ := execSeq_steps loopLeave_straight
      (s := { s2 with pc := s2.pc + 8 + 1, astack := rs1,
                      dstack := (i1 + 1#n) :: l1 :: s2.dstack })
      (by simp only [hpc2]; exact hL) (loopLeave_ok _ rfl)
    have h6 := ihr lv (base + body.size + 14)
      { s2 with pc := s2.pc + 8 + 1 + 2, astack := rs1, dstack := s2.dstack } hR
      (by simp only [hpc2]; omega) hd2 hm2 rfl
    refine reaches_cast ?_ hrs2
      (reaches_trans (hst.trans (hs2.trans (hs3.trans (.cons hfall hs5)))) h6)
    rw [size_doLoop]; omega
  | @doAgain body rest i l d m rs i1 l1 d1 m1 rs1 r _ hne _ ihb ihl =>
    intro lv base s hat hpc hd hm ha
    obtain ⟨hE, hBody, hT, hbr, -⟩ := doLoop_decode hat
    obtain ⟨hst, -⟩ := execSeq_steps loopEnter_straight (by rw [hpc]; exact hE)
      (loopEnter_ok s hd)
    obtain ⟨s2, hs2, hpc2, hrs2, hd2, hm2, ha2⟩ := ihb _ (base + 3)
      { s with pc := s.pc + 3, dstack := d, astack := i :: l :: s.astack }
      hBody (by simp [hpc]) rfl hm (by simp [ha])
    rw [compile_size] at hpc2
    obtain ⟨hs3, hpc3⟩ := execSeq_steps loopTest_straight (by rw [hpc2]; exact hT)
      (loopTest_ok s2 ha2)
    have htaken := step_branch_taken (by rw [hpc3, hpc2]; exact hbr) rfl
      (isTrue_sub_ne hne)
    have h5 := ihl lv base
      ({ s2 with pc := base, astack := rs1, dstack := (i1 + 1#n) :: l1 :: s2.dstack } : State n)
      hat rfl
      (by simp [hd2]) hm2 rfl
    exact reaches_cast rfl hrs2
      (reaches_trans (hst.trans (hs2.trans (hs3.trans (.single htaken)))) h5)
  | @plusUnder body rest st hl =>
    intro lv base s hat hpc hd hm ha
    obtain ⟨hE, -⟩ := plusLoop_decode hat
    exact execSeq_trap loopEnter_straight (by rw [hpc]; exact hE)
      (loopEnter_under s (by rw [hd]; exact hl))
  | @plusBodyStop body rest i l d m rs r _ hk ihb =>
    intro lv base s hat hpc hd hm ha
    obtain ⟨hE, hBody, -⟩ := plusLoop_decode hat
    obtain ⟨hst, hpc1⟩ := execSeq_steps loopEnter_straight (by rw [hpc]; exact hE)
      (loopEnter_ok s hd)
    have h1 := ihb _ (base + 3) { s with pc := s.pc + 3, dstack := d, astack := i :: l :: s.astack }
      hBody (by simp [hpc]) rfl hm (by simp [ha])
    exact reaches_stop hk (reaches_trans hst h1)
  | @plusLeave body rest i l d m rs st1 r _ _ ihb ihr =>
    intro lv base s hat hpc hd hm ha
    obtain ⟨hE, hBody, -, -, -, -, hR⟩ := plusLoop_decode hat
    obtain ⟨hst, -⟩ := execSeq_steps loopEnter_straight (by rw [hpc]; exact hE)
      (loopEnter_ok s hd)
    obtain ⟨s2, hs2, hpc2, hrs2, hd2, hm2, ha2⟩ := ihb _ (base + 3)
      { s with pc := s.pc + 3, dstack := d, astack := i :: l :: s.astack }
      hBody (by simp [hpc]) rfl hm (by simp [ha])
    have h3 := ihr lv (base + body.size + 33) s2 hR hpc2 hd2 hm2 ha2
    refine reaches_cast ?_ hrs2 (reaches_trans (hst.trans hs2) h3)
    rw [size_plusLoop]; omega
  | @plusTestUnder body rest i l d m rs st1 _ hl ihb =>
    intro lv base s hat hpc hd hm ha
    obtain ⟨hE, hBody, hT, -⟩ := plusLoop_decode hat
    obtain ⟨hst, -⟩ := execSeq_steps loopEnter_straight (by rw [hpc]; exact hE)
      (loopEnter_ok s hd)
    obtain ⟨s2, hs2, hpc2, -, -, -, ha2⟩ := ihb _ (base + 3)
      { s with pc := s.pc + 3, dstack := d, astack := i :: l :: s.astack }
      hBody (by simp [hpc]) rfl hm (by simp [ha])
    rw [compile_size] at hpc2
    obtain ⟨s3, hs3, ht⟩ := execSeq_trap plusTest_straight (by rw [hpc2]; exact hT)
      (plusTest_underR s2 (by rw [ha2]; exact hl))
    exact ⟨s3, hst.trans (hs2.trans hs3), ht⟩
  | @plusStepUnder body rest i l d m rs i1 l1 m1 rs1 _ ihb =>
    intro lv base s hat hpc hd hm ha
    obtain ⟨hE, hBody, hT, -⟩ := plusLoop_decode hat
    obtain ⟨hst, -⟩ := execSeq_steps loopEnter_straight (by rw [hpc]; exact hE)
      (loopEnter_ok s hd)
    obtain ⟨s2, hs2, hpc2, -, hd2, -, ha2⟩ := ihb _ (base + 3)
      { s with pc := s.pc + 3, dstack := d, astack := i :: l :: s.astack }
      hBody (by simp [hpc]) rfl hm (by simp [ha])
    rw [compile_size] at hpc2
    obtain ⟨s3, hs3, ht⟩ := execSeq_trap plusTest_straight (by rw [hpc2]; exact hT)
      (plusTest_underD s2 hd2 ha2)
    exact ⟨s3, hst.trans (hs2.trans hs3), ht⟩
  | @plusDone body rest i l d m rs i1 l1 k d1 m1 rs1 r _ he _ ihb ihr =>
    intro lv base s hat hpc hd hm ha
    obtain ⟨hE, hBody, hT, hbr, -, hL, hR⟩ := plusLoop_decode hat
    obtain ⟨hst, -⟩ := execSeq_steps loopEnter_straight (by rw [hpc]; exact hE)
      (loopEnter_ok s hd)
    obtain ⟨s2, hs2, hpc2, hrs2, hd2, hm2, ha2⟩ := ihb _ (base + 3)
      { s with pc := s.pc + 3, dstack := d, astack := i :: l :: s.astack }
      hBody (by simp [hpc]) rfl hm (by simp [ha])
    rw [compile_size] at hpc2
    obtain ⟨hs3, hpc3⟩ := execSeq_steps plusTest_straight (by rw [hpc2]; exact hT)
      (plusTest_ok s2 hd2 ha2)
    have htaken := step_branch_taken (by rw [hpc3, hpc2]; exact hbr) rfl
      (by rw [isTrue_crossed]; exact he)
    obtain ⟨hs5, -⟩ := execSeq_steps loopLeave_straight
      (s := { s2 with pc := base + body.size + 31, astack := rs1,
                      dstack := (i1 + k) :: l1 :: d1 })
      hL (loopLeave_ok _ rfl)
    have h6 := ihr lv (base + body.size + 33)
      { s2 with pc := base + body.size + 31 + 2, astack := rs1, dstack := d1 } hR
      (by simp only <;> omega) rfl hm2 rfl
    refine reaches_cast ?_ hrs2
      (reaches_trans (hst.trans (hs2.trans (hs3.trans (.cons htaken hs5)))) h6)
    rw [size_plusLoop]; omega
  | @plusAgain body rest i l d m rs i1 l1 k d1 m1 rs1 r _ hne _ ihb ihl =>
    intro lv base s hat hpc hd hm ha
    obtain ⟨hE, hBody, hT, hbr, hj, -⟩ := plusLoop_decode hat
    obtain ⟨hst, -⟩ := execSeq_steps loopEnter_straight (by rw [hpc]; exact hE)
      (loopEnter_ok s hd)
    obtain ⟨s2, hs2, hpc2, hrs2, hd2, hm2, ha2⟩ := ihb _ (base + 3)
      { s with pc := s.pc + 3, dstack := d, astack := i :: l :: s.astack }
      hBody (by simp [hpc]) rfl hm (by simp [ha])
    rw [compile_size] at hpc2
    obtain ⟨hs3, hpc3⟩ := execSeq_steps plusTest_straight (by rw [hpc2]; exact hT)
      (plusTest_ok s2 hd2 ha2)
    have hfall := step_branch_fall (by rw [hpc3, hpc2]; exact hbr) rfl
      (by rw [isTrue_crossed]; exact hne)
    have hjmp := step_jmp (p := p) (t := base)
      (s := { s2 with pc := s2.pc + 26 + 1, astack := rs1, dstack := (i1 + k) :: l1 :: d1 })
      (by simp only [hpc2]; exact hj)
    have h5 := ihl lv base
      ({ s2 with pc := base, astack := rs1, dstack := (i1 + k) :: l1 :: d1 } : State n)
      hat rfl rfl hm2 rfl
    exact reaches_cast rfl hrs2
      (reaches_trans (hst.trans (hs2.trans (hs3.trans (.cons hfall (.single hjmp))))) h5)

/-- The dictionary laid out by `emitDefs` after any code `pre` satisfies `DefsAt` for the
addresses `wordAddr`. -/
theorem emitDefs_layout {n : Nat} (addr : Nat → Nat) :
    ∀ (defs : List Block) (pre : Prog n) (base : Nat), pre.length = base →
      (∀ i body, defs[i]? = some body →
        At (pre ++ emitDefs addr base defs) (wordAddr base defs i)
          ((compile addr (wordAddr base defs i + body.size) body : Frag n).emit
            (wordAddr base defs i) ++ [Instr.ret])) ∧
      (∀ i, defs[i]? = none → (pre ++ emitDefs addr base defs)[wordAddr base defs i]? = none) := by
  intro defs
  induction defs with
  | nil =>
    intro pre base hlen
    refine ⟨fun i body h => by simp at h, fun i _ => ?_⟩
    simp [wordAddr, emitDefs, ← hlen]
  | cons b bs ih =>
    intro pre base hlen
    have hlen' : (pre ++ ((compile addr (base + b.size) b : Frag n).emit base ++ [Instr.ret])).length =
        base + b.size + 1 := by
      simp [Frag.len, compile_size, hlen]; omega
    have hp : pre ++ emitDefs addr base (b :: bs) =
        (pre ++ ((compile addr (base + b.size) b : Frag n).emit base ++ [.ret])) ++
          emitDefs addr (base + b.size + 1) bs := by
      simp [emitDefs, List.append_assoc]
    obtain ⟨ih1, ih2⟩ := ih _ _ hlen'
    refine ⟨fun i body h => ?_, fun i h => ?_⟩
    · cases i with
      | zero =>
        simp only [List.getElem?_cons_zero, Option.some.injEq] at h
        subst h
        rw [hp]
        have := at_embed pre ((compile addr (base + b.size) b : Frag n).emit base ++ [.ret])
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
  have hlen : ((Forth.compile P.addr P.main.size P.main : Frag n).emit 0 ++ [Instr.halt]).length =
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
    | .leave st' =>
        ∃ s', Exec (P.compile : Prog n) (State.init mem) (.halted s') ∧
          s'.dstack = st'.stack ∧ s'.mem = st'.mem ∧ s'.astack = st'.rstack
    | .exit _ => Exec (P.compile : Prog n) (State.init mem) (.trapped .returnUnderflow)
    | .error t => Exec (P.compile : Prog n) (State.init mem) (.trapped t) := by
  have hat : At (P.compile : Prog n) 0
      ((Forth.compile P.addr P.main.size P.main : Frag n).emit 0) := by
    have := at_embed ([] : Prog n) ((Forth.compile P.addr P.main.size P.main : Frag n).emit 0)
      ([.halt] ++ emitDefs P.addr (P.main.size + 1) P.defs)
    simpa [Program.compile, List.append_assoc] using this
  have key := Forth.compile_correct (Program.defsAt P) h P.main.size 0 (State.init mem) hat rfl
    rfl rfl rfl
  rw [compile_size] at key
  have hfetch : ∀ s' : State n, s'.pc = P.main.size → (P.compile : Prog n)[s'.pc]? = some .halt := by
    intro s' hpc
    rw [hpc]
    simp [Program.compile, (Forth.compile P.addr P.main.size P.main : Frag n).len, compile_size,
      List.append_assoc]
  cases r with
  | ok st' =>
    obtain ⟨s', hs, hpc, _, hd, hm, ha⟩ := key
    refine ⟨s', Exec.of_steps hs (.halt ?_), hd, hm, ha⟩
    rw [step_of_fetch (hfetch s' (by simpa using hpc))]; rfl
  | leave st' =>
    obtain ⟨s', hs, hpc, _, hd, hm, ha⟩ := key
    refine ⟨s', Exec.of_steps hs (.halt ?_), hd, hm, ha⟩
    rw [step_of_fetch (hfetch s' hpc)]; rfl
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
    | .leave st' =>
        ∃ s', Exec (compileProgram b : Prog n) (State.init mem) (.halted s') ∧
          s'.dstack = st'.stack ∧ s'.mem = st'.mem ∧ s'.astack = st'.rstack
    | .exit _ => Exec (compileProgram b : Prog n) (State.init mem) (.trapped .returnUnderflow)
    | .error t => Exec (compileProgram b : Prog n) (State.init mem) (.trapped t) :=
  by cases r <;> exact Program.compile_correct (P := { defs := [], main := b }) h

end Forth
end WordDialect
