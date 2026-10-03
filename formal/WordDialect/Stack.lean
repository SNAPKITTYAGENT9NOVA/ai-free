import WordDialect.Machine

/-!
# WordDialect.Stack

Stack-operation correctness for `exec`.

* `exec_underflow`: an instruction whose operands are not all present traps with
  `stackUnderflow` and does nothing else.
* `exec_not_underflow`: with enough operands, the instruction never traps with
  `stackUnderflow`.
* `exec_depth`: whenever an instruction continues, the data-stack depth changes by exactly
  `pushes - pops`.
-/

namespace WordDialect

namespace Instr

/-- Operands consumed from the data stack. -/
def pops {n : Nat} : Instr n → Nat
  | .word _ | .ptr _ | .jmp _ | .call _ | .ret | .push _ | .halt => 0
  | .load | .not | .branch _ | .pop _ | .dup | .drop => 1
  | .store | .add | .sub | .mul | .div | .sdiv | .and | .or | .xor
  | .shl | .shr | .rotl | .rotr | .cmp _ | .swap | .over => 2
  | .select | .rot => 3

/-- Results produced on the data stack. -/
def pushes {n : Nat} : Instr n → Nat
  | .word _ | .ptr _ | .load | .push _ => 1
  | .add | .sub | .mul | .div | .sdiv | .and | .or | .xor | .not
  | .shl | .shr | .rotl | .rotr | .cmp _ | .select => 1
  | .store | .jmp _ | .branch _ | .call _ | .ret | .pop _ | .drop | .halt => 0
  | .dup => 2
  | .swap => 2
  | .over => 3
  | .rot => 3

end Instr

theorem exec_underflow {n : Nat} (i : Instr n) (s : State n)
    (h : s.dstack.length < i.pops) : exec i s = .trapped .stackUnderflow := by
  obtain ⟨pc, d, rs, regs, mem⟩ := s
  cases i <;> simp only [Instr.pops] at h <;>
    (rcases d with _ | ⟨x, _ | ⟨y, _ | ⟨z, d⟩⟩⟩ <;>
      first | (simp at h; done) | (simp at h; omega) | (exfalso; omega) | simp [exec])

theorem exec_not_underflow {n : Nat} (i : Instr n) (s : State n)
    (h : i.pops ≤ s.dstack.length) : exec i s ≠ .trapped .stackUnderflow := by
  obtain ⟨pc, d, rs, regs, mem⟩ := s
  cases i <;> simp only [Instr.pops] at h <;>
    (rcases d with _ | ⟨x, _ | ⟨y, _ | ⟨z, d⟩⟩⟩ <;>
      first | (simp at h; done) | (simp at h; omega) | (exfalso; omega) |
        (simp [exec, State.fall]; try split <;> simp))

end WordDialect
