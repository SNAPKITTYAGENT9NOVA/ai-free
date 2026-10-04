import Forth.Correct
import Forth.Parse
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

/-- `>R` is not in the supported subset (only the words listed in `Forth.Parse`). -/
theorem parse_not_in_subset : parse "1 >R" = .error "unknown word: >R" := by rfl

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
    Run sumProg.defs sumProg.main ⟨[], mem⟩ (.ok ⟨[55#64], mem⟩) :=
  eval_sound 100 _ _ _ (by rfl)

/-- The lowered program (with `SUM` as an IR subroutine) halts with exactly `[55]`. -/
theorem sumProg_machine (mem : Memory 64) :
    ∃ s', Exec (sumProg.compile : Prog 64) (State.init mem) (.halted s') ∧
      s'.dstack = [55#64] ∧ s'.mem = mem := by
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
    | error _ => simp [okStack?] at h

/-! ## `0=` and `MOD` -/

theorem parse_mod_zeq :
    parse "-7 2 MOD  7 -2 mod  0 0=  5 0=" =
      .ok ⟨[], .op (.lit (-7)) (.op (.lit 2) (.op .mod (.op (.lit 7) (.op (.lit (-2)) (.op .mod
        (.op (.lit 0) (.op .zeq (.op (.lit 5) (.op .zeq .nil))))))))), 0⟩ := by rfl

/-- `MOD` follows symmetric `/`: `-7 MOD 2 = -1`, `7 MOD -2 = 1`; `0=` gives `-1`/`0`. -/
theorem mod_zeq_run (mem : Memory 64) :
    Run [] (.op (.lit (-7)) (.op (.lit 2) (.op .mod (.op (.lit 7) (.op (.lit (-2)) (.op .mod
        (.op (.lit 0) (.op .zeq (.op (.lit 5) (.op .zeq .nil)))))))))) ⟨[], mem⟩
      (.ok ⟨[0#64, BitVec.ofInt 64 (-1), 1#64, BitVec.ofInt 64 (-1)], mem⟩) :=
  eval_sound 20 _ _ _ (by rfl)

theorem mod_zero_run (mem : Memory 64) :
    Run [] (.op (.lit 1) (.op (.lit 0) (.op .mod .nil))) ⟨[], mem⟩ (.error .divideByZero) :=
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
    parse ": F VARIABLE X ;" = .error "VARIABLE or CONSTANT inside definition of F" := by rfl

/-- With its two variable cells available, `varProg` leaves `42`, and so does the machine. -/
theorem varProg_machine :
    ∃ s', Exec (varProg.compile : Prog 64) (State.init (Memory.ofImage [0, 0])) (.halted s') ∧
      s'.dstack = [42#64] := by
  have h : (eval varProg.defs 40 varProg.main ⟨[], (Memory.ofImage [0, 0] : Memory 64)⟩).bind
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
    Run sumExitProg.defs sumExitProg.main ⟨[], mem⟩ (.ok ⟨[55#64], mem⟩) :=
  eval_sound 100 _ _ _ (by rfl)

theorem sumExitProg_machine (mem : Memory 64) :
    ∃ s', Exec (sumExitProg.compile : Prog 64) (State.init mem) (.halted s') ∧
      s'.dstack = [55#64] ∧ s'.mem = mem := by
  have := Program.compile_correct (sumExitProg_run mem)
  simpa using this

end Forth
end WordDialect
