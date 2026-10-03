import WordIR.Straight

/-!
# WordIR.Program

Whole-program lifting for straight-line code: `code ++ [HALT]` run from `pc = 0` halts with
the state `execSeq` computes, or traps with the trap `execSeq` reports.
-/

namespace WordDialect
namespace IR

theorem exec_straight_halt {n : Nat} {code : List (Instr n)} {s s1 : State n}
    (hs : ∀ i ∈ code, i.isStraight = true) (hpc : s.pc = 0)
    (h : execSeq code s = .next s1) :
    Exec (code ++ [.halt]) s (.halted s1) := by
  have hat : At (code ++ [.halt]) s.pc code := by
    have := at_embed ([] : Prog n) code [.halt]
    simpa [hpc] using this
  obtain ⟨hst, hpc1⟩ := execSeq_steps hs hat h
  refine Exec.of_steps hst (.halt ?_)
  have hfetch : (code ++ [.halt])[s1.pc]? = some .halt := by
    rw [hpc1, hpc]; simp
  rw [step_of_fetch hfetch]; rfl

theorem exec_straight_trap {n : Nat} {code : List (Instr n)} {s : State n} {t : Trap}
    (hs : ∀ i ∈ code, i.isStraight = true) (hpc : s.pc = 0)
    (h : execSeq code s = .trapped t) :
    Exec (code ++ [.halt]) s (.trapped t) := by
  have hat : At (code ++ [.halt]) s.pc code := by
    have := at_embed ([] : Prog n) code [.halt]
    simpa [hpc] using this
  obtain ⟨s1, hst, ht⟩ := execSeq_trap hs hat h
  exact Exec.of_steps hst (.trap ht)

end IR
end WordDialect
