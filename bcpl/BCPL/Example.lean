import BCPL.Correct

/-!
# BCPL.Example

End-to-end statement for the BCPL pipeline: the assignment `x := 2 + 3`, compiled and run on
the machine, halts with the word `5` stored in `x`'s cell, whenever that cell is addressable.
-/

namespace WordDialect
namespace BCPL

/-- `x := 2 + 3`, with `x` as variable `0`. -/
def setX : Stmt := .assign (.var 0) (.bin .add (.num 2) (.num 3))

theorem setX_exec (addr : Var → Word 64) (mem : Memory 64) (hv : mem.valid (addr 0) = true) :
    ∃ m', Exec addr setX mem (.ok m') ∧ m'.read? (addr 0) = some 5#64 := by
  have hw : mem.write? (addr 0) 5#64 =
      some { mem with cell := fun b => if b = addr 0 then 5#64 else mem.cell b } := by
    simp [Memory.write?, hv]
  refine ⟨_, .assign ?_, Memory.read_write_same hw⟩
  simp [setX, assignSem, evalE, BinOp.sem, writeW, hw]

theorem setX_machine (addr : Var → Word 64) (mem : Memory 64) (hv : mem.valid (addr 0) = true) :
    ∃ s', WordDialect.Exec (compileProgram addr setX) (State.init mem) (.halted s') ∧
      s'.mem.read? (addr 0) = some 5#64 := by
  obtain ⟨m', he, hr⟩ := setX_exec addr mem hv
  have := compileProgram_correct he
  obtain ⟨s', hex, _, hm⟩ := this
  exact ⟨s', hex, by rw [hm]; exact hr⟩

end BCPL
end WordDialect
