import WordDialect.Exec

/-!
# WordDialect.Rules

Every semantic rule of `exec`, stated explicitly (word, pointer, memory, stack), and the
numeric denotation of each word operation.

The numeric lemmas give the integer meaning of word operations. They are what a lowering
from mathematical expressions relies on: `add`, `sub`, `mul` are arithmetic modulo `2^n`
and `div` is exact integer division whenever the divisor is nonzero.
-/

namespace WordDialect

section Rules

variable {n : Nat} {s : State n} {d : List (Word n)}

/-! ### Word operations -/

theorem exec_word (w : Word n) : exec (.word w) s = s.fall (w :: s.dstack) := by simp [exec]
theorem exec_ptr (q : Ptr n) : exec (.ptr q) s = s.fall (q.toWord :: s.dstack) := by simp [exec]

theorem exec_add {a b : Word n} (h : s.dstack = b :: a :: d) :
    exec .add s = s.fall ((a + b) :: d) := by simp [exec, h]
theorem exec_sub {a b : Word n} (h : s.dstack = b :: a :: d) :
    exec .sub s = s.fall ((a - b) :: d) := by simp [exec, h]
theorem exec_mul {a b : Word n} (h : s.dstack = b :: a :: d) :
    exec .mul s = s.fall ((a * b) :: d) := by simp [exec, h]
theorem exec_div {a b : Word n} (h : s.dstack = b :: a :: d) (hb : b ≠ 0#n) :
    exec .div s = s.fall (a.udiv b :: d) := by simp [exec, h, hb]
theorem exec_div_zero {a : Word n} (h : s.dstack = 0#n :: a :: d) :
    exec .div s = .trapped .divideByZero := by simp [exec, h]

theorem exec_sdiv {a b : Word n} (h : s.dstack = b :: a :: d) (hb : b ≠ 0#n) :
    exec .sdiv s = s.fall (a.sdiv b :: d) := by simp [exec, h, hb]
theorem exec_sdiv_zero {a : Word n} (h : s.dstack = 0#n :: a :: d) :
    exec .sdiv s = .trapped .divideByZero := by simp [exec, h]

theorem exec_and {a b : Word n} (h : s.dstack = b :: a :: d) :
    exec .and s = s.fall ((a &&& b) :: d) := by simp [exec, h]
theorem exec_or {a b : Word n} (h : s.dstack = b :: a :: d) :
    exec .or s = s.fall ((a ||| b) :: d) := by simp [exec, h]
theorem exec_xor {a b : Word n} (h : s.dstack = b :: a :: d) :
    exec .xor s = s.fall ((a ^^^ b) :: d) := by simp [exec, h]
theorem exec_not {a : Word n} (h : s.dstack = a :: d) :
    exec .not s = s.fall ((~~~a) :: d) := by simp [exec, h]

theorem exec_shl {a b : Word n} (h : s.dstack = b :: a :: d) :
    exec .shl s = s.fall (Word.shl a b :: d) := by simp [exec, h]
theorem exec_shr {a b : Word n} (h : s.dstack = b :: a :: d) :
    exec .shr s = s.fall (Word.shr a b :: d) := by simp [exec, h]
theorem exec_rotl {a b : Word n} (h : s.dstack = b :: a :: d) :
    exec .rotl s = s.fall (Word.rotl a b :: d) := by simp [exec, h]
theorem exec_rotr {a b : Word n} (h : s.dstack = b :: a :: d) :
    exec .rotr s = s.fall (Word.rotr a b :: d) := by simp [exec, h]

theorem exec_cmp {c : Cond} {a b : Word n} (h : s.dstack = b :: a :: d) :
    exec (.cmp c) s = s.fall (Word.ofBool (c.eval a b) :: d) := by simp [exec, h]

theorem exec_select {c x y : Word n} (h : s.dstack = c :: y :: x :: d) :
    exec .select s = s.fall ((if Word.isTrue c then x else y) :: d) := by simp [exec, h]

/-! ### Memory operations -/

theorem exec_load {a v : Word n} (h : s.dstack = a :: d) (hm : s.mem.read? a = some v) :
    exec .load s = s.fall (v :: d) := by simp [exec, h, hm]

theorem exec_load_bad {a : Word n} (h : s.dstack = a :: d) (hm : s.mem.read? a = none) :
    exec .load s = .trapped .badAddress := by simp [exec, h, hm]

theorem exec_store {a v : Word n} {m : Memory n} (h : s.dstack = a :: v :: d)
    (hm : s.mem.write? a v = some m) :
    exec .store s = .next { s with pc := s.pc + 1, dstack := d, mem := m } := by
  simp [exec, h, hm]

theorem exec_store_bad {a v : Word n} (h : s.dstack = a :: v :: d)
    (hm : s.mem.write? a v = none) : exec .store s = .trapped .badAddress := by
  simp [exec, h, hm]

/-! ### Stack operations (Forth `DUP DROP SWAP OVER ROT`) -/

theorem exec_dup {a : Word n} (h : s.dstack = a :: d) :
    exec .dup s = s.fall (a :: a :: d) := by simp [exec, h]
theorem exec_drop {a : Word n} (h : s.dstack = a :: d) :
    exec .drop s = s.fall d := by simp [exec, h]
theorem exec_swap {a b : Word n} (h : s.dstack = b :: a :: d) :
    exec .swap s = s.fall (a :: b :: d) := by simp [exec, h]
theorem exec_over {a b : Word n} (h : s.dstack = b :: a :: d) :
    exec .over s = s.fall (a :: b :: a :: d) := by simp [exec, h]
theorem exec_rot {a b c : Word n} (h : s.dstack = c :: b :: a :: d) :
    exec .rot s = s.fall (a :: c :: b :: d) := by simp [exec, h]

/-! ### Registers -/

theorem exec_push (r : Nat) : exec (.push r) s = s.fall (s.regs r :: s.dstack) := by simp [exec]

theorem exec_pop {r : Nat} {v : Word n} (h : s.dstack = v :: d) :
    exec (.pop r) s =
      .next { s with pc := s.pc + 1, dstack := d, regs := State.setReg s.regs r v } := by
  simp [exec, h]

theorem exec_halt : exec .halt s = .halted s := by simp [exec]

end Rules

/-! ## Stack-effect algebra -/

theorem dup_is_push_top {n : Nat} {a : Word n} {d : List (Word n)} :
    (a :: a :: d).length = d.length + 2 := by simp

/-- `swap` is an involution on the data stack. -/
theorem swap_swap {n : Nat} {a b : Word n} {d : List (Word n)} {s : State n}
    (h : s.dstack = b :: a :: d) :
    ∃ s1, exec .swap s = .next s1 ∧ exec .swap s1 = .next { s with pc := s.pc + 2 } := by
  refine ⟨{ s with pc := s.pc + 1, dstack := a :: b :: d }, by simp [exec, h, State.fall], ?_⟩
  simp [exec, State.fall, h]

/-- `rot` applied three times is the identity on the data stack. -/
theorem rot_rot_rot {n : Nat} {a b c : Word n} {d : List (Word n)} {s : State n}
    (h : s.dstack = c :: b :: a :: d) :
    ∃ s1 s2, exec .rot s = .next s1 ∧ exec .rot s1 = .next s2 ∧
      exec .rot s2 = .next { s with pc := s.pc + 3 } := by
  refine ⟨{ s with pc := s.pc + 1, dstack := a :: c :: b :: d },
          { s with pc := s.pc + 2, dstack := b :: a :: c :: d }, ?_, ?_, ?_⟩ <;>
    simp [exec, h, State.fall, Nat.add_assoc]

/-! ## Numeric denotation of word operations -/

section Numeric

variable {n : Nat}

theorem add_toNat (a b : Word n) : (a + b).toNat = (a.toNat + b.toNat) % 2 ^ n :=
  BitVec.toNat_add a b

theorem mul_toNat (a b : Word n) : (a * b).toNat = (a.toNat * b.toNat) % 2 ^ n :=
  BitVec.toNat_mul a b

theorem sub_toNat (a b : Word n) : (a - b).toNat = ((2 ^ n - b.toNat) + a.toNat) % 2 ^ n :=
  BitVec.toNat_sub a b

theorem udiv_toNat (a b : Word n) : (a.udiv b).toNat = a.toNat / b.toNat :=
  BitVec.toNat_udiv

/-- When no overflow occurs, `ADD` is integer addition. -/
theorem add_exact (a b : Word n) (h : a.toNat + b.toNat < 2 ^ n) :
    (a + b).toNat = a.toNat + b.toNat := by
  rw [add_toNat, Nat.mod_eq_of_lt h]

theorem mul_exact (a b : Word n) (h : a.toNat * b.toNat < 2 ^ n) :
    (a * b).toNat = a.toNat * b.toNat := by
  rw [mul_toNat, Nat.mod_eq_of_lt h]

/-- `DIV` is Euclidean division: quotient times divisor plus remainder recovers the dividend. -/
theorem udiv_spec (a b : Word n) :
    (a.udiv b).toNat * b.toNat + a.toNat % b.toNat = a.toNat := by
  rw [udiv_toNat]
  exact Nat.div_add_mod' a.toNat b.toNat

theorem sub_add_cancel' (a b : Word n) : (a - b) + b = a := by
  simp [BitVec.sub_add_cancel]

theorem add_sub_cancel' (a b : Word n) : (a + b) - b = a := by
  exact BitVec.add_sub_cancel a b

end Numeric

end WordDialect
