import WordDialect.Rules

/-!
# WordDialect.Init

Initial machine state and the final data stack of an outcome. Used to state end-to-end
execution results.
-/

namespace WordDialect

/-- Start of execution: `pc = 0`, empty stacks, all registers zero, given memory. -/
def State.init {n : Nat} (mem : Memory n) : State n :=
  { pc := 0, dstack := [], rstack := [], regs := fun _ => 0#n, mem := mem }

def Outcome.finalStack {n : Nat} : Outcome n → Option (List (Word n))
  | .halted s => some s.dstack
  | _ => none

/-- Forth `5 DUP +` as a Universal Word IR program. -/
def forthFiveDupPlus : Prog 64 := [.word 5#64, .dup, .add, .halt]

/-- Running it under the Lean semantics halts with the single word `10` on the stack. -/
theorem forthFiveDupPlus_result (mem : Memory 64) :
    ((run forthFiveDupPlus 10 (State.init mem)).bind Outcome.finalStack) = some [10#64] := by
  simp [run, step, forthFiveDupPlus, State.init, exec, State.fall, Outcome.finalStack]

theorem forthFiveDupPlus_exec (mem : Memory 64) :
    ∃ s, Exec forthFiveDupPlus (State.init mem) (.halted s) ∧ s.dstack = [10#64] := by
  have h : run forthFiveDupPlus 10 (State.init mem) =
      some (.halted { pc := 3, dstack := [10#64], rstack := [], regs := fun _ => 0#64, mem := mem }) := by
    simp [run, step, forthFiveDupPlus, State.init, exec, State.fall]
  exact ⟨_, run_sound h, rfl⟩

end WordDialect
