import WordDialect.Stack

/-!
# WordDialect.Invariants

Frame conditions for a single instruction: what `exec` is allowed to change.

* data-stack depth moves by exactly `pushes - pops`
* the set of valid addresses never changes
* only `store` changes memory, and it changes exactly one cell
* only `pop` changes registers
* only `call`/`ret` change the return stack
* only `halt` halts, and halting leaves the state untouched
* every trap has a specific cause
-/

namespace WordDialect

theorem exec_depth {n : Nat} (i : Instr n) (s s' : State n)
    (h : exec i s = .next s') :
    s'.dstack.length + i.pops = s.dstack.length + i.pushes := by
  obtain ⟨pc, d, rs, regs, mem⟩ := s
  cases i <;> rcases d with _ | ⟨x, _ | ⟨y, _ | ⟨z, d⟩⟩⟩ <;>
    simp only [exec, State.fall] at h <;>
    (try split at h) <;> (try split at h) <;> (try cases h) <;>
    simp_all [Instr.pops, Instr.pushes] <;> omega

theorem exec_valid {n : Nat} (i : Instr n) (s s' : State n)
    (h : exec i s = .next s') : s'.mem.valid = s.mem.valid := by
  obtain ⟨pc, d, rs, regs, mem⟩ := s
  cases i <;> rcases d with _ | ⟨x, _ | ⟨y, _ | ⟨z, d⟩⟩⟩ <;>
    simp only [exec, State.fall] at h <;>
    (try split at h) <;> (try split at h) <;> (try cases h) <;> simp_all <;>
    exact Memory.write?_valid (by assumption)

/-- Only `store` changes memory contents. -/
theorem exec_mem_frame {n : Nat} (i : Instr n) (s s' : State n)
    (hi : i ≠ .store) (h : exec i s = .next s') : s'.mem = s.mem := by
  obtain ⟨pc, d, rs, regs, mem⟩ := s
  cases i <;> rcases d with _ | ⟨x, _ | ⟨y, _ | ⟨z, d⟩⟩⟩ <;>
    simp only [exec, State.fall] at h <;>
    (try split at h) <;> (try split at h) <;> (try cases h) <;> simp_all

/-- Only `pop` changes registers. -/
theorem exec_regs_frame {n : Nat} (i : Instr n) (s s' : State n)
    (hi : ∀ r, i ≠ .pop r) (h : exec i s = .next s') : s'.regs = s.regs := by
  obtain ⟨pc, d, rs, regs, mem⟩ := s
  cases i <;> rcases d with _ | ⟨x, _ | ⟨y, _ | ⟨z, d⟩⟩⟩ <;>
    simp only [exec, State.fall] at h <;>
    (try split at h) <;> (try split at h) <;> (try cases h) <;> simp_all

/-- Only `call` and `ret` change the return stack. -/
theorem exec_rstack_frame {n : Nat} (i : Instr n) (s s' : State n)
    (hc : ∀ t, i ≠ .call t) (hr : i ≠ .ret) (h : exec i s = .next s') :
    s'.rstack = s.rstack := by
  obtain ⟨pc, d, rs, regs, mem⟩ := s
  cases i <;> rcases d with _ | ⟨x, _ | ⟨y, _ | ⟨z, d⟩⟩⟩ <;>
    simp only [exec, State.fall] at h <;>
    (try split at h) <;> (try split at h) <;> (try cases h) <;> simp_all

/-- Only `halt` halts, and halting leaves the machine state untouched. -/
theorem exec_halted {n : Nat} (i : Instr n) (s s' : State n)
    (h : exec i s = .halted s') : i = .halt ∧ s' = s := by
  obtain ⟨pc, d, rs, regs, mem⟩ := s
  cases i <;> rcases d with _ | ⟨x, _ | ⟨y, _ | ⟨z, d⟩⟩⟩ <;>
    simp only [exec, State.fall] at h <;>
    (try split at h) <;> (try split at h) <;> (try cases h) <;> simp_all

/-- Every trap has exactly one of four causes. -/
theorem exec_trap {n : Nat} (i : Instr n) (s : State n) (t : Trap)
    (h : exec i s = .trapped t) :
    (t = .stackUnderflow ∧ s.dstack.length < i.pops) ∨
    (t = .badAddress ∧ (i = .load ∨ i = .store)) ∨
    (t = .divideByZero ∧ i = .div) ∨
    (t = .returnUnderflow ∧ i = .ret) := by
  obtain ⟨pc, d, rs, regs, mem⟩ := s
  cases i <;> rcases d with _ | ⟨x, _ | ⟨y, _ | ⟨z, d⟩⟩⟩ <;>
    simp only [exec, State.fall] at h <;>
    (try split at h) <;> (try split at h) <;> (try cases h) <;>
    simp_all [Instr.pops]

end WordDialect
