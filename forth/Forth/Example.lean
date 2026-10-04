import Forth.Correct

/-!
# Forth.Example

The specification's own example, `5 DUP +`, through the whole pipeline: Forth reference
semantics, lowering, and machine execution.
-/

namespace WordDialect
namespace Forth

def fiveDupPlus : Block := .op (.lit 5) (.op .dup (.op .add .nil))

theorem fiveDupPlus_run (mem : Memory 64) :
    Run [] fiveDupPlus ⟨[], mem, []⟩ (.ok ⟨[10#64], mem, []⟩) :=
  .opOk (st' := ⟨[5#64], mem, []⟩) (by simp [Op.sem])
    (.opOk (st' := ⟨[5#64, 5#64], mem, []⟩) (by simp [Op.sem])
      (.opOk (st' := ⟨[10#64], mem, []⟩) (by simp [Op.sem]) .nil))

/-- The lowered program halts with exactly `[10]` on the machine's data stack. -/
theorem fiveDupPlus_machine (mem : Memory 64) :
    ∃ s', Exec (compileProgram fiveDupPlus : Prog 64) (State.init mem) (.halted s') ∧
      s'.dstack = [10#64] ∧ s'.mem = mem ∧ s'.astack = [] := by
  have := compileProgram_correct (fiveDupPlus_run mem)
  simpa using this

end Forth
end WordDialect
