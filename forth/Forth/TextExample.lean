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

theorem parse_fiveDupPlus : parse "5 DUP +" = .ok ⟨[], fiveDupPlus⟩ := by rfl

theorem parse_case_and_comments :
    parse "( a comment ) 1 2 \\ a line comment, ignored: 3 +\n swap -7 if 4 else 5 then" =
      .ok ⟨[], .op (.lit 1) (.op (.lit 2) (.op .swap (.op (.lit (-7))
        (.ite (.op (.lit 4) .nil) (.op (.lit 5) .nil) .nil))))⟩ := by rfl

theorem parse_square :
    parse ": SQ DUP * ; 7 sq" = .ok ⟨[.op .dup (.op .mul .nil)], .op (.lit 7) (.call 0 .nil)⟩ := by
  rfl

theorem parse_begin_until :
    parse "10 BEGIN 1 - DUP 0 = UNTIL" =
      .ok ⟨[], .op (.lit 10)
        (.untilL (.op (.lit 1) (.op .sub (.op .dup (.op (.lit 0) (.op .eq .nil))))) .nil)⟩ := by
  rfl

/-- `0=` is not in the supported subset (only the words listed in `Forth.Parse`). -/
theorem parse_not_in_subset : parse "1 0=" = .error "unknown word: 0=" := by rfl

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

def sumProg : Program := ⟨[sumBody], .op (.lit 10) (.call 0 .nil)⟩

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

end Forth
end WordDialect
