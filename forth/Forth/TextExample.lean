import Forth.Correct
import Forth.Parse
import Forth.Print
import Forth.ParseProps
import Forth.Eval
import Forth.Example

/-!
# Forth.TextExample

Forth source text through the whole pipeline: parsing, reference semantics (by the sound
evaluator `eval`), lowering with colon definitions, and machine execution.
-/

namespace WordDialect
namespace Forth

/-! ## Parsing facts -/

theorem parse_fiveDupPlus : parse "5 DUP +" = .ok ⟨[], fiveDupPlus, 0⟩ := by rfl

theorem parse_case_and_comments :
    parse "( a comment ) 1 2 \\ a line comment, ignored: 3 +\n swap -7 if 4 else 5 then" =
      .ok ⟨[], .op (.lit 1) (.op (.lit 2) (.op .swap (.op (.lit (-7))
        (.ite (.op (.lit 4) .nil) (.op (.lit 5) .nil) .nil)))), 0⟩ := by rfl

theorem parse_square :
    parse ": SQ DUP * ; 7 sq" = .ok ⟨[.op .dup (.op .mul .nil)], .op (.lit 7) (.call 0 .nil), 0⟩ := by
  rfl

theorem parse_begin_until :
    parse "10 BEGIN 1 - DUP 0 = UNTIL" =
      .ok ⟨[], .op (.lit 10)
        (.untilL (.op (.lit 1) (.op .sub (.op .dup (.op (.lit 0) (.op .eq .nil))))) .nil), 0⟩ := by
  rfl

/-- Words outside the supported subset (only the words listed in `Forth.Parse`) are errors. -/
theorem parse_not_in_subset : parse "1 2 3 D+" = .error "unknown word: D+" := by rfl

theorem parse_unknown : parse "1 FOO" = .error "unknown word: FOO" := by rfl

theorem parse_use_before_definition : parse "SQ : SQ DUP * ;" = .error "unknown word: SQ" := by
  rfl

theorem parse_missing_semicolon : parse ": SQ DUP *" = .error "definition of SQ has no ;" := by
  rfl

theorem parse_unbalanced : parse "1 IF 2" = .error "IF without THEN" := by rfl

/-! ## A recursive word, end to end -/

/-- Triangular numbers by recursion: `SUM ( n -- 0+1+…+n )`. -/
def sumSrc : String :=
  ": SUM ( n -- 0+1+...+n ) DUP IF DUP 1 - SUM + THEN ;  \\ recursive\n10 SUM"

def sumBody : Block := .op .dup (.ite (.op .dup (.op (.lit 1) (.op .sub (.call 0 (.op .add .nil))))) .nil .nil)

def sumProg : Program := ⟨[sumBody], .op (.lit 10) (.call 0 .nil), 0⟩

theorem parse_sum : parse sumSrc = .ok sumProg := by rfl

/-- The reference semantics: `10 SUM` leaves `55`. -/
theorem sumProg_run (mem : Memory 64) :
    Run sumProg.defs sumProg.main ⟨[], mem, []⟩ (.ok ⟨[55#64], mem, []⟩) :=
  eval_sound 100 _ _ _ (by rfl)

/-- The lowered program (with `SUM` as an IR subroutine) halts with exactly `[55]`. -/
theorem sumProg_machine (mem : Memory 64) :
    ∃ s', Exec (sumProg.compile : Prog 64) (State.init mem) (.halted s') ∧
      s'.dstack = [55#64] ∧ s'.mem = mem ∧ s'.astack = [] := by
  have := Program.compile_correct (sumProg_run mem)
  simpa using this

/-- If the evaluator ends normally with data stack `stk`, the reference semantics derives a
normal end with that stack (whatever the memory then is). -/
def okStack? {n : Nat} : Res n → Option (List (Word n))
  | .ok st' => some st'.stack
  | _ => none

theorem run_of_eval_stack {n : Nat} {defs : List Block} {fuel : Nat} {b : Block}
    {st : FState n} {stk : List (Word n)}
    (h : (eval defs fuel b st).bind okStack? = some stk) :
    ∃ st', Run defs b st (.ok st') ∧ st'.stack = stk := by
  cases he : eval defs fuel b st with
  | none => rw [he] at h; cases h
  | some r =>
    rw [he] at h
    cases r with
    | ok st' => simp [okStack?] at h; exact ⟨st', eval_sound _ _ _ _ he, h⟩
    | exit _ => simp [okStack?] at h
    | leave _ => simp [okStack?] at h
    | error _ => simp [okStack?] at h

/-! ## `0=` and `MOD` -/

theorem parse_mod_zeq :
    parse "-7 2 MOD  7 -2 mod  0 0=  5 0=" =
      .ok ⟨[], .op (.lit (-7)) (.op (.lit 2) (.op .mod (.op (.lit 7) (.op (.lit (-2)) (.op .mod
        (.op (.lit 0) (.op .zeq (.op (.lit 5) (.op .zeq .nil))))))))), 0⟩ := by rfl

/-- `MOD` follows symmetric `/`: `-7 MOD 2 = -1`, `7 MOD -2 = 1`; `0=` gives `-1`/`0`. -/
theorem mod_zeq_run (mem : Memory 64) :
    Run [] (.op (.lit (-7)) (.op (.lit 2) (.op .mod (.op (.lit 7) (.op (.lit (-2)) (.op .mod
        (.op (.lit 0) (.op .zeq (.op (.lit 5) (.op .zeq .nil)))))))))) ⟨[], mem, []⟩
      (.ok ⟨[0#64, BitVec.ofInt 64 (-1), 1#64, BitVec.ofInt 64 (-1)], mem, []⟩) :=
  eval_sound 20 _ _ _ (by rfl)

theorem mod_zero_run (mem : Memory 64) :
    Run [] (.op (.lit 1) (.op (.lit 0) (.op .mod .nil))) ⟨[], mem, []⟩ (.error .divideByZero) :=
  eval_sound 20 _ _ _ (by rfl)

/-! ## `VARIABLE` and `CONSTANT` -/

def varSrc : String :=
  "VARIABLE X  VARIABLE Y  10 CONSTANT TEN\n TEN X !  32 Y !  X @ Y @ +  Y !  Y @"

/-- Variables are cells `0` and `1`; the constant is a literal. -/
def varProg : Program :=
  ⟨[], .op (.lit 10) (.op (.lit 0) (.op .store (.op (.lit 32) (.op (.lit 1) (.op .store
    (.op (.lit 0) (.op .fetch (.op (.lit 1) (.op .fetch (.op .add (.op (.lit 1) (.op .store
    (.op (.lit 1) (.op .fetch .nil)))))))))))))), 2⟩

theorem parse_var : parse varSrc = .ok varProg := by rfl

theorem parse_constant_needs_literal :
    parse "1 2 + CONSTANT X" = .error "CONSTANT needs a number literal immediately before it" := by
  rfl

theorem parse_variable_in_definition :
    parse ": F VARIABLE X ;" = .error "VARIABLE, CONSTANT, CREATE, ALLOT or , inside definition of F" := by rfl

/-- With its two variable cells available, `varProg` leaves `42`, and so does the machine. -/
theorem varProg_machine :
    ∃ s', Exec (varProg.compile : Prog 64) (State.init (Memory.ofImage [0, 0])) (.halted s') ∧
      s'.dstack = [42#64] := by
  have h : (eval varProg.defs 40 varProg.main ⟨[], (Memory.ofImage [0, 0] : Memory 64), []⟩).bind
      okStack? = some [42#64] := by rfl
  obtain ⟨st', hrun, hst⟩ := run_of_eval_stack h
  obtain ⟨s', hs, hd, _⟩ := Program.compile_correct hrun
  exact ⟨s', hs, hd.trans hst⟩

theorem varProg_memOk : varProg.MemOk (Memory.ofImage [0, 0] : Memory 64) := by
  intro a ha
  simp only [varProg] at ha
  simp [Memory.ofImage]
  omega

/-! ## `RECURSE` and `EXIT` -/

theorem parse_recurse :
    parse ": SUM DUP IF DUP 1 - RECURSE + THEN ; 10 SUM" = .ok sumProg := by rfl

theorem parse_recurse_outside : parse "1 RECURSE" = .error "RECURSE outside a definition" := by
  rfl

theorem parse_exit_outside : parse "1 EXIT" = .error "EXIT outside a definition" := by rfl

theorem parse_exit_dead_code :
    parse ": F 1 EXIT 2 ; F" = .ok ⟨[.op (.lit 1) (.exit (.op (.lit 2) .nil))], .call 0 .nil, 0⟩ := by
  rfl

/-- A recursive word that leaves early with `EXIT` at its base case. -/
def sumExitSrc : String :=
  ": SUM ( n -- 0+...+n ) DUP 0= IF EXIT THEN DUP 1 - RECURSE + ;\n10 SUM"

def sumExitProg : Program :=
  ⟨[.op .dup (.op .zeq (.ite (.exit .nil) .nil
      (.op .dup (.op (.lit 1) (.op .sub (.call 0 (.op .add .nil)))))))],
    .op (.lit 10) (.call 0 .nil), 0⟩

theorem parse_sumExit : parse sumExitSrc = .ok sumExitProg := by rfl

theorem sumExitProg_run (mem : Memory 64) :
    Run sumExitProg.defs sumExitProg.main ⟨[], mem, []⟩ (.ok ⟨[55#64], mem, []⟩) :=
  eval_sound 100 _ _ _ (by rfl)

theorem sumExitProg_machine (mem : Memory 64) :
    ∃ s', Exec (sumExitProg.compile : Prog 64) (State.init mem) (.halted s') ∧
      s'.dstack = [55#64] ∧ s'.mem = mem ∧ s'.astack = [] := by
  have := Program.compile_correct (sumExitProg_run mem)
  simpa using this

/-! ## Printing -/

theorem print_sumExit :
    print sumExitProg = ": W0 DUP 0= IF EXIT ELSE THEN DUP 1 - W0 + ; 10 W0 " := by rfl

theorem print_var :
    print varProg = "VARIABLE V VARIABLE V 10 0 ! 32 1 ! 0 @ 1 @ + 1 ! 1 @ " := by rfl

theorem sumExitProg_wf : sumExitProg.WF := by
  refine ⟨fun i body h => ?_, by simp [sumExitProg, Block.WF], by decide⟩
  match i, h with
  | 0, h => simp only [sumExitProg, List.getElem?_cons_zero, Option.some.injEq] at h; subst h
            simp [Block.WF]

/-- An instance of the proved round trip `parse_print`. -/
theorem parse_print_sumExit : parse (print sumExitProg) = .ok sumExitProg :=
  parse_print _ sumExitProg_wf

/-! ## The converse direction (`Forth.ParseProps`) -/

/-- Well-formedness comes from the parse, with no case analysis. -/
theorem varProg_wf : varProg.WF := parse_wf parse_var

/-- Printing is canonical: the printed text of any parsed program parses back to it. -/
theorem parse_print_var : parse (print varProg) = .ok varProg := parse_print_of_parse parse_var

/-- Case-insensitivity, proved for all sources by `parse_case_insensitive`. -/
theorem parse_square_lower :
    (parse ": sq dup * ; 7 SQ").toOption = (parse ": SQ DUP * ; 7 sq").toOption :=
  parse_case_insensitive (String.ext (by simp only [String.toList_map]; decide))

/-- Only error messages keep the original spelling. -/
theorem parse_unknown_lower : parse "1 foo" = .error "unknown word: foo" := by rfl

/-- A `( … )` comment tokenizes like a space (`tokenize_paren_comment`). -/
theorem tokenize_paren_example :
    Parse.tokenize ("1 \\ x" ++ " ( " ++ "any ( text" ++ " ) " ++ "2") =
      Parse.tokenize ("1 \\ x" ++ " " ++ "2") :=
  tokenize_paren_comment ⟨_, rfl⟩ (by decide)

/-- A `\` comment runs to the end of the line (`tokenize_line_comment`). -/
theorem tokenize_line_example :
    Parse.tokenize ("1" ++ " \\ " ++ "2 ( 3" ++ "\n" ++ "4") = Parse.tokenize ("1" ++ "\n" ++ "4") :=
  tokenize_line_comment (by decide)

/-- `5 CONSTANT five`: the literal leaves the main block and `five` (any case) is `5`. -/
theorem parse_constant_case :
    parse "5 CONSTANT five FIVE Five +" =
      .ok ⟨[], .op (.lit 5) (.op (.lit 5) (.op .add .nil)), 0⟩ := by rfl

theorem constant_step :
    Parse.parseTop 3 [] [] 0 .nil [['5'], ['c', 'o', 'n', 's', 't', 'a', 'n', 't'], ['X']] =
      Parse.parseTop 2 [(['X'], Block.op (.lit 5))] [] 0 .nil [] :=
  parseTop_constant_lit rfl rfl rfl

/-- `RECURSE` and the word's own name parse the same inside its definition. -/
theorem parse_recurse_name :
    parse ": F DUP IF 1 - RECURSE THEN ; 3 F" = parse ": F DUP IF 1 - F THEN ; 3 F" := by
  have e : ∀ src, src = ": F DUP IF 1 - RECURSE THEN ; 3 F" ∨ src = ": F DUP IF 1 - F THEN ; 3 F" →
      parse src = .ok ⟨[.op .dup (.ite (.op (.lit 1) (.op .sub (.call 0 .nil))) .nil .nil)],
        .op (.lit 3) (.call 0 .nil), 0⟩ := by
    rintro src (rfl | rfl) <;> rfl
  rw [e _ (.inl rfl), e _ (.inr rfl)]

/-! ## Return-data stack and `DO … LOOP` -/

theorem parse_rstack_words :
    parse "1 >r r@ R> i j" =
      .ok ⟨[], .op (.lit 1) (.op .tor (.op .rfetch (.op .fromr (.op .loopI (.op .loopJ .nil))))),
        0⟩ := by rfl

theorem parse_do_loop :
    parse "0 10 0 do i + loop" =
      .ok ⟨[], .op (.lit 0) (.op (.lit 10) (.op (.lit 0)
        (.doLoop (.op .loopI (.op .add .nil)) .nil))), 0⟩ := by rfl

theorem parse_do_without_loop : parse "10 0 DO I" = .error "DO without LOOP or +LOOP" := by rfl

theorem parse_loop_without_do : parse "1 LOOP" = .error "unexpected LOOP" := by rfl

theorem parse_do_then : parse "1 IF 10 0 DO THEN LOOP" = .error "DO without LOOP or +LOOP" := by
  rfl

/-- `0 10 0 DO I + LOOP` sums the indices `0 … 9`. -/
def loopSumProg : Program :=
  ⟨[], .op (.lit 0) (.op (.lit 10) (.op (.lit 0) (.doLoop (.op .loopI (.op .add .nil)) .nil))), 0⟩

theorem loopSum_run (mem : Memory 64) :
    Run loopSumProg.defs loopSumProg.main ⟨[], mem, []⟩ (.ok ⟨[45#64], mem, []⟩) :=
  eval_sound 30 _ _ _ (by rfl)

theorem loopSum_machine (mem : Memory 64) :
    ∃ s', Exec (loopSumProg.compile : Prog 64) (State.init mem) (.halted s') ∧
      s'.dstack = [45#64] ∧ s'.mem = mem ∧ s'.astack = [] := by
  have := Program.compile_correct (loopSum_run mem)
  simpa using this

/-- Nested loops: `J` is the outer index. `Σ_{j<3} Σ_{i<4} i*j = 18`. -/
theorem nested_loops :
    parse "0 3 0 DO 4 0 DO I J * + LOOP LOOP" = .ok ⟨[], .op (.lit 0) (.op (.lit 3) (.op (.lit 0)
      (.doLoop (.op (.lit 4) (.op (.lit 0) (.doLoop (.op .loopI (.op .loopJ (.op .mul
        (.op .add .nil)))) .nil))) .nil))), 0⟩ := by rfl

theorem nested_loops_run (mem : Memory 64) :
    Run [] (.op (.lit 0) (.op (.lit 3) (.op (.lit 0)
      (.doLoop (.op (.lit 4) (.op (.lit 0) (.doLoop (.op .loopI (.op .loopJ (.op .mul
        (.op .add .nil)))) .nil))) .nil)))) ⟨[], mem, []⟩ (.ok ⟨[18#64], mem, []⟩) :=
  eval_sound 30 _ _ _ (by rfl)

/-- `R>` on an empty return-data stack traps `returnUnderflow`, and so does the machine. -/
theorem fromr_empty_run (mem : Memory 64) :
    Run [] (.op (.lit 1) (.op .fromr .nil)) ⟨[], mem, []⟩ (.error .returnUnderflow) :=
  eval_sound 5 _ _ _ (by rfl)

theorem fromr_empty_machine (mem : Memory 64) :
    Exec (compileProgram (.op (.lit 1) (.op .fromr .nil)) : Prog 64) (State.init mem)
      (.trapped .returnUnderflow) :=
  compileProgram_correct (fromr_empty_run mem)

/-- A value parked with `>R` survives calls, and a word may change it. -/
def bumpSrc : String := ": BUMP R> 1 + >R ; 5 >R BUMP BUMP R>"

def bumpProg : Program :=
  ⟨[.op .fromr (.op (.lit 1) (.op .add (.op .tor .nil)))],
    .op (.lit 5) (.op .tor (.call 0 (.call 0 (.op .fromr .nil)))), 0⟩

theorem parse_bump : parse bumpSrc = .ok bumpProg := by rfl

theorem bump_run (mem : Memory 64) :
    Run bumpProg.defs bumpProg.main ⟨[], mem, []⟩ (.ok ⟨[7#64], mem, []⟩) :=
  eval_sound 20 _ _ _ (by rfl)

/-- `EXIT` inside a loop leaves the loop parameters (index on top, then limit) on the
return-data stack. -/
def find3Prog : Program :=
  ⟨[.op (.lit 10) (.op (.lit 0) (.doLoop (.op .loopI (.op (.lit 3) (.op .eq
      (.ite (.op .loopI (.exit .nil)) .nil .nil)))) (.op (.lit 99) .nil)))],
    .call 0 .nil, 0⟩

theorem parse_find3 :
    parse ": FIND3 10 0 DO I 3 = IF I EXIT THEN LOOP 99 ; FIND3" = .ok find3Prog := by rfl

theorem find3_run (mem : Memory 64) :
    Run find3Prog.defs find3Prog.main ⟨[], mem, []⟩ (.ok ⟨[3#64], mem, [3#64, 10#64]⟩) :=
  eval_sound 40 _ _ _ (by rfl)

theorem print_find3 :
    print find3Prog = ": W0 10 0 DO I 3 = IF I EXIT ELSE THEN LOOP 99 ; W0 " := by rfl

theorem parse_print_find3 : parse (print find3Prog) = .ok find3Prog :=
  parse_print_of_parse parse_find3

/-! ## `+LOOP`, `?DO`, `LEAVE` and `UNLOOP` -/

theorem parse_plus_loop :
    parse "10 0 DO I 2 +LOOP" =
      .ok ⟨[], .op (.lit 10) (.op (.lit 0) (.plusLoop (.op .loopI (.op (.lit 2) .nil)) .nil)), 0⟩ := by
  rfl

/-- `?DO` parses to the `IF` that skips the loop when limit and index are equal. -/
theorem parse_qdo :
    parse "5 0 ?DO I LOOP 7" =
      .ok ⟨[], .op (.lit 5) (.op (.lit 0)
        (Block.qdo (.doLoop (.op .loopI .nil) .nil) (.op (.lit 7) .nil))), 0⟩ := by rfl

theorem parse_leave_unloop :
    parse "3 0 DO LEAVE UNLOOP LOOP" =
      .ok ⟨[], .op (.lit 3) (.op (.lit 0) (.doLoop (.leave (.op .unloop .nil)) .nil)), 0⟩ := by rfl

/-- `LEAVE` must be inside a loop of its own word: not at top level, not in an `IF` outside a
loop, and not in a word called from a loop. -/
theorem parse_leave_outside : parse "LEAVE" = .error "LEAVE outside DO … LOOP" := by rfl
theorem parse_leave_if : parse "1 IF LEAVE THEN" = .error "LEAVE outside DO … LOOP" := by rfl
theorem parse_leave_word :
    parse ": F LEAVE ; 3 0 DO F LOOP" = .error "LEAVE outside DO … LOOP" := by rfl
theorem parse_plus_loop_without_do : parse "1 +LOOP" = .error "unexpected +LOOP" := by rfl

/-- The crossing rule on concrete values: counting up by one it ends exactly when
`index + 1 = limit`; counting down it ends after the limit itself has been run. -/
example : loopCrossed (9#64) 10#64 1#64 = true := by decide
example : loopCrossed (8#64) 10#64 1#64 = false := by decide
example : loopCrossed (8#64) 10#64 2#64 = true := by decide
example : loopCrossed (8#64) 11#64 2#64 = false := by decide
example : loopCrossed (9#64) 11#64 2#64 = true := by decide
example : loopCrossed (0#64) 0#64 (-1#64) = true := by decide
example : loopCrossed (1#64) 0#64 (-1#64) = false := by decide

/-- `0 10 0 DO I + 2 +LOOP`: `0 + 2 + 4 + 6 + 8`. -/
def evensBlock : Block :=
  .op (.lit 0) (.op (.lit 10) (.op (.lit 0) (.plusLoop (.op .loopI (.op .add (.op (.lit 2) .nil))) .nil)))

theorem evens_run (mem : Memory 64) :
    Run [] evensBlock ⟨[], mem, []⟩ (.ok ⟨[20#64], mem, []⟩) :=
  eval_sound 30 _ _ _ (by rfl)

theorem evens_machine (mem : Memory 64) :
    ∃ s', Exec (compileProgram evensBlock : Prog 64) (State.init mem) (.halted s') ∧
      s'.dstack = [20#64] ∧ s'.mem = mem ∧ s'.astack = [] := by
  have := compileProgram_correct (evens_run mem)
  simpa using this

/-- `0 0 10 DO I + -1 +LOOP`: `10 + 9 + … + 0`, the limit included. -/
theorem down_run (mem : Memory 64) :
    Run [] (.op (.lit 0) (.op (.lit 0) (.op (.lit 10)
      (.plusLoop (.op .loopI (.op .add (.op (.lit (-1)) .nil))) .nil)))) ⟨[], mem, []⟩
      (.ok ⟨[55#64], mem, []⟩) :=
  eval_sound 40 _ _ _ (by rfl)

/-- `100 0 DO I 5 > IF I LEAVE THEN LOOP`: the loop ends at index 6, its parameters removed. -/
def first5Block : Block :=
  .op (.lit 100) (.op (.lit 0) (.doLoop (.op .loopI (.op (.lit 5) (.op .gt
    (.ite (.op .loopI (.leave .nil)) .nil .nil)))) .nil))

theorem first5_run (mem : Memory 64) :
    Run [] first5Block ⟨[], mem, []⟩ (.ok ⟨[6#64], mem, []⟩) :=
  eval_sound 30 _ _ _ (by rfl)

theorem first5_machine (mem : Memory 64) :
    ∃ s', Exec (compileProgram first5Block : Prog 64) (State.init mem) (.halted s') ∧
      s'.dstack = [6#64] ∧ s'.mem = mem ∧ s'.astack = [] := by
  have := compileProgram_correct (first5_run mem)
  simpa using this

/-- `0 5 5 ?DO 1 + LOOP` skips the loop. -/
theorem qskip_run (mem : Memory 64) :
    Run [] (.op (.lit 0) (.op (.lit 5) (.op (.lit 5)
      (Block.qdo (.doLoop (.op (.lit 1) (.op .add .nil)) .nil) .nil)))) ⟨[], mem, []⟩
      (.ok ⟨[0#64], mem, []⟩) :=
  eval_sound 20 _ _ _ (by rfl)

/-- `UNLOOP EXIT` inside a loop leaves the return-data stack empty (compare `find3_run`). -/
def find7Prog : Program :=
  ⟨[.op (.lit 20) (.op (.lit 0) (.doLoop (.op .loopI (.op (.lit 7) (.op .eq
      (.ite (.op .loopI (.op .unloop (.exit .nil))) .nil .nil)))) (.op (.lit 99) .nil)))],
    .call 0 .nil, 0⟩

theorem parse_find7 :
    parse ": FIND7 20 0 DO I 7 = IF I UNLOOP EXIT THEN LOOP 99 ; FIND7" = .ok find7Prog := by rfl

theorem find7_run (mem : Memory 64) :
    Run find7Prog.defs find7Prog.main ⟨[], mem, []⟩ (.ok ⟨[7#64], mem, []⟩) :=
  eval_sound 40 _ _ _ (by rfl)

theorem parse_print_find7 : parse (print find7Prog) = .ok find7Prog :=
  parse_print_of_parse parse_find7

/-! ## `BEGIN … WHILE … REPEAT` -/

theorem parse_while :
    parse "BEGIN DUP WHILE 1 - REPEAT 7" =
      .ok ⟨[], .whileL (.op .dup .nil) (.op (.lit 1) (.op .sub .nil)) (.op (.lit 7) .nil), 0⟩ := by
  rfl

theorem parse_while_without_repeat :
    parse "BEGIN 1 WHILE 2" = .error "WHILE without REPEAT" := by rfl
theorem parse_begin_without_end :
    parse "BEGIN 1" = .error "BEGIN without UNTIL or WHILE" := by rfl
theorem parse_repeat_without_while : parse "1 REPEAT" = .error "unexpected REPEAT" := by rfl

/-- Euclid's algorithm with `WHILE`: `1071 462 GCD` is `21`. -/
def gcdProg : Program :=
  ⟨[.whileL (.op .dup .nil) (.op .swap (.op .over (.op .mod .nil))) (.op .drop .nil)],
    .op (.lit 1071) (.op (.lit 462) (.call 0 .nil)), 0⟩

theorem parse_gcd :
    parse ": GCD BEGIN DUP WHILE SWAP OVER MOD REPEAT DROP ; 1071 462 GCD" = .ok gcdProg := by rfl

theorem gcd_run (mem : Memory 64) :
    Run gcdProg.defs gcdProg.main ⟨[], mem, []⟩ (.ok ⟨[21#64], mem, []⟩) :=
  eval_sound 30 _ _ _ (by rfl)

theorem gcd_machine (mem : Memory 64) :
    ∃ s', Exec (gcdProg.compile : Prog 64) (State.init mem) (.halted s') ∧
      s'.dstack = [21#64] ∧ s'.mem = mem ∧ s'.astack = [] := by
  have := Program.compile_correct (gcd_run mem)
  simpa using this

theorem print_gcd :
    print gcdProg = ": W0 BEGIN DUP WHILE SWAP OVER MOD REPEAT DROP ; 1071 462 W0 " := by rfl

theorem parse_print_gcd : parse (print gcdProg) = .ok gcdProg :=
  parse_print_of_parse parse_gcd

/-- A false first test skips the body. -/
theorem while_zero_run (mem : Memory 64) :
    Run [] (.op (.lit 7) (.whileL (.op (.lit 0) .nil) (.op (.lit 1) (.op .add .nil))
      (.op (.lit 8) .nil))) ⟨[], mem, []⟩ (.ok ⟨[8#64, 7#64], mem, []⟩) :=
  eval_sound 10 _ _ _ (by rfl)

/-! ## More core words, `CASE`, and data space -/

theorem parse_core_ops :
    parse "2DUP 2DROP 2SWAP /MOD NEGATE ABS MIN MAX" =
      .ok ⟨[], .op .twoDup (.op .twoDrop (.op .twoSwap (.op .divMod (.op .negate (.op .abs
        (.op .min (.op .max .nil))))))), 0⟩ := by rfl

/-- `?DUP` is `DUP IF DUP THEN`. -/
theorem parse_qdup : parse "?DUP 1" = .ok ⟨[], Block.qdup (.op (.lit 1) .nil), 0⟩ := by rfl

theorem core_ops_run (mem : Memory 64) :
    Run [] (.op (.lit (-7)) (.op (.lit 2) (.op .divMod (.op (.lit 3) (.op (.lit (-4)) (.op .min
      (.op (.lit (-9)) (.op .abs (.op (.lit 0) (Block.qdup (.op (.lit 6) (Block.qdup .nil))))))))))))
      ⟨[], mem, []⟩
      (.ok ⟨[6#64, 6#64, 0#64, 9#64, BitVec.ofInt 64 (-4), BitVec.ofInt 64 (-3),
        BitVec.ofInt 64 (-1)], mem, []⟩) :=
  eval_sound 30 _ _ _ (by rfl)

/-- `CASE`: each `OF` compares with the selector; the default sees the selector and `ENDCASE`
drops it. -/
def caseBlock : Block :=
  (Block.ofClause (.op (.lit 100) .nil)
    (.op (.lit 2) (Block.ofClause (.op (.lit 200) .nil) (.op .dup (.op (.lit 1000) (.op .add
      (.op .swap .nil))))))).append (.op .drop .nil)

theorem parse_case :
    parse "CASE 1 OF 100 ENDOF 2 OF 200 ENDOF DUP 1000 + SWAP ENDCASE" =
      .ok ⟨[], .op (.lit 1) caseBlock, 0⟩ := by rfl

theorem case_run_7 (mem : Memory 64) :
    Run [] (.op (.lit 7) (.op (.lit 1) caseBlock)) ⟨[], mem, []⟩ (.ok ⟨[1007#64], mem, []⟩) :=
  eval_sound 30 _ _ _ (by rfl)

theorem case_run_2 (mem : Memory 64) :
    Run [] (.op (.lit 2) (.op (.lit 1) caseBlock)) ⟨[], mem, []⟩ (.ok ⟨[200#64], mem, []⟩) :=
  eval_sound 30 _ _ _ (by rfl)

theorem parse_of_outside_case :
    parse "1 1 OF 2 ENDOF 3" = .error "OF … ENDOF without ENDCASE" := by rfl
theorem parse_case_without_endcase :
    parse "1 CASE 1 OF 2 ENDOF" = .error "OF … ENDOF without ENDCASE" := by rfl
theorem parse_of_without_endof : parse "1 CASE 1 OF 2 ENDCASE" = .error "OF without ENDOF" := by rfl

/-- `CREATE`, `,` and `ALLOT` lay out data at parse time: `T` is cell 0, the main block stores
its two values in cells 0 and 1, `1 ALLOT` reserves cell 2, and `X` is cell 3. -/
theorem parse_data_space :
    parse "CREATE T 10 , 20 , 1 ALLOT VARIABLE X T X" =
      .ok ⟨[], .op (.lit 10) (.op (.lit 0) (.op .store (.op (.lit 20) (.op (.lit 1) (.op .store
        (.op (.lit 0) (.op (.lit 3) .nil))))))), 4⟩ := by rfl

theorem parse_create_in_def :
    parse ": F CREATE X ;" =
      .error "VARIABLE, CONSTANT, CREATE, ALLOT or , inside definition of F" := by rfl
theorem parse_comma_needs_literal :
    parse "1 DUP ," = .error ", needs a number literal immediately before it" := by rfl

/-! ## Double-cell arithmetic -/

theorem parse_double :
    parse "UM* UM/MOD M* SM/REM */MOD */ FM/MOD" =
      .ok ⟨[], .op .umStar (.op .umDivMod (.op .mStar (.op .smRem (.op .starSlashMod
        (.op .starSlash (.op .fmMod .nil)))))), 0⟩ := by rfl

/-- `M*` gives the double-cell product (low word, then high word); `UM*` the unsigned one. -/
theorem mstar_run (mem : Memory 64) :
    Run [] (.op (.lit (-3)) (.op (.lit 7) (.op .mStar (.op (.lit (-1)) (.op (.lit 2)
        (.op .umStar .nil)))))) ⟨[], mem, []⟩
      (.ok ⟨[1#64, BitVec.ofInt 64 (-2), BitVec.ofInt 64 (-1), BitVec.ofInt 64 (-21)], mem, []⟩) :=
  eval_sound 10 _ _ _ (by rfl)

/-- `SM/REM` divides `(lo, hi)` symmetrically; `UM/MOD` unsigned: `2^64 / 3`. -/
theorem smrem_run (mem : Memory 64) :
    Run [] (.op (.lit (-7)) (.op (.lit (-1)) (.op (.lit 2) (.op .smRem (.op (.lit 0) (.op (.lit 1)
        (.op (.lit 3) (.op .umDivMod .nil)))))))) ⟨[], mem, []⟩
      (.ok ⟨[6148914691236517205#64, 1#64, BitVec.ofInt 64 (-3), BitVec.ofInt 64 (-1)], mem, []⟩) :=
  eval_sound 10 _ _ _ (by rfl)

/-- `*/MOD` and `*/` keep the full product: `2^62 * 4 / 8 = 2^61` although `2^62 * 4` overflows. -/
theorem starSlash_run (mem : Memory 64) :
    Run [] (.op (.lit 6) (.op (.lit 7) (.op (.lit 4) (.op .starSlashMod (.op (.lit 4611686018427387904)
        (.op (.lit 4) (.op (.lit 8) (.op .starSlash .nil)))))))) ⟨[], mem, []⟩
      (.ok ⟨[2305843009213693952#64, 10#64, 2#64], mem, []⟩) :=
  eval_sound 10 _ _ _ (by rfl)

/-- `FM/MOD` rounds toward negative infinity: `-7 / 2` is `-4` remainder `1`, and `7 / -2` is
`-4` remainder `-1` (the remainder takes the divisor's sign). -/
theorem fmMod_run (mem : Memory 64) :
    Run [] (.op (.lit (-7)) (.op (.lit (-1)) (.op (.lit 2) (.op .fmMod (.op (.lit 7) (.op (.lit 0)
        (.op (.lit (-2)) (.op .fmMod .nil)))))))) ⟨[], mem, []⟩
      (.ok ⟨[BitVec.ofInt 64 (-4), BitVec.ofInt 64 (-1), BitVec.ofInt 64 (-4), 1#64], mem, []⟩) :=
  eval_sound 10 _ _ _ (by rfl)

/-- The floored quotient `-2^63 - 1` does not fit, although the truncated one would. -/
theorem fmMod_overflow (mem : Memory 64) :
    Run [] (.op (.lit (-1)) (.op (.lit (-2)) (.op (.lit 2) (.op .fmMod .nil)))) ⟨[], mem, []⟩
      (.error .divideByZero) :=
  eval_sound 10 _ _ _ (by rfl)

/-- A quotient that does not fit a word traps, like division by zero. -/
theorem starSlash_overflow (mem : Memory 64) :
    Run [] (.op (.lit 4611686018427387904) (.op (.lit 4) (.op (.lit 2) (.op .starSlash .nil))))
      ⟨[], mem, []⟩ (.error .divideByZero) :=
  eval_sound 10 _ _ _ (by rfl)

end Forth
end WordDialect
