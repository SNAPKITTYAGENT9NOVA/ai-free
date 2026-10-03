import WordIR.Straight

/-!
# WordIR.RExpr

Register-and-memory word expressions: the IR-level building block frontends use for index
arithmetic and accumulators. `RExpr.code` leaves the expression's value on the data stack.
Correctness is proved against `RExpr.eval`, for success and for traps.
-/

namespace WordDialect
namespace IR

inductive RExpr (n : Nat) where
  | const (w : Word n)
  | reg (r : Nat)
  | add (a b : RExpr n)
  | sub (a b : RExpr n)
  | mul (a b : RExpr n)
  | load (a : RExpr n)

namespace RExpr

def eval {n : Nat} (regs : Nat → Word n) (mem : Memory n) : RExpr n → Except Trap (Word n)
  | .const w => .ok w
  | .reg r => .ok (regs r)
  | .add a b =>
    match eval regs mem a with
    | .error t => .error t
    | .ok x =>
      match eval regs mem b with
      | .error t => .error t
      | .ok y => .ok (x + y)
  | .sub a b =>
    match eval regs mem a with
    | .error t => .error t
    | .ok x =>
      match eval regs mem b with
      | .error t => .error t
      | .ok y => .ok (x - y)
  | .mul a b =>
    match eval regs mem a with
    | .error t => .error t
    | .ok x =>
      match eval regs mem b with
      | .error t => .error t
      | .ok y => .ok (x * y)
  | .load a =>
    match eval regs mem a with
    | .error t => .error t
    | .ok x =>
      match mem.read? x with
      | some v => .ok v
      | none => .error .badAddress

def code {n : Nat} : RExpr n → List (Instr n)
  | .const w => [.word w]
  | .reg r => [.push r]
  | .add a b => code a ++ code b ++ [.add]
  | .sub a b => code a ++ code b ++ [.sub]
  | .mul a b => code a ++ code b ++ [.mul]
  | .load a => code a ++ [.load]

theorem code_straight {n : Nat} (e : RExpr n) : ∀ i ∈ e.code, i.isStraight = true := by
  induction e with
  | const w => simp [code, Instr.isStraight]
  | reg r => simp [code, Instr.isStraight]
  | add a b iha ihb =>
    intro i hi; simp only [code, List.mem_append, List.mem_singleton] at hi
    rcases hi with (hi | hi) | rfl
    · exact iha i hi
    · exact ihb i hi
    · rfl
  | sub a b iha ihb =>
    intro i hi; simp only [code, List.mem_append, List.mem_singleton] at hi
    rcases hi with (hi | hi) | rfl
    · exact iha i hi
    · exact ihb i hi
    · rfl
  | mul a b iha ihb =>
    intro i hi; simp only [code, List.mem_append, List.mem_singleton] at hi
    rcases hi with (hi | hi) | rfl
    · exact iha i hi
    · exact ihb i hi
    · rfl
  | load a ih =>
    intro i hi; simp only [code, List.mem_append, List.mem_singleton] at hi
    rcases hi with hi | rfl
    · exact ih i hi
    · rfl

theorem code_ok {n : Nat} (e : RExpr n) :
    ∀ (s : State n) (v : Word n), e.eval s.regs s.mem = .ok v →
      execSeq e.code s = .next { s with pc := s.pc + e.code.length, dstack := v :: s.dstack } := by
  induction e with
  | const w =>
    intro s v h; simp only [eval] at h; cases h
    simp [code, execSeq, exec, State.fall]
  | reg r =>
    intro s v h; simp only [eval] at h; cases h
    simp [code, execSeq, exec, State.fall]
  | add a b iha ihb =>
    intro s v h
    simp only [eval] at h
    split at h
    · cases h
    · rename_i x hx
      split at h
      · cases h
      · rename_i y hy; cases h
        rw [code, execSeq_append, execSeq_append, iha s x hx]
        simp only [Outcome.andThen]
        rw [ihb { s with pc := s.pc + a.code.length, dstack := x :: s.dstack } y hy]
        simp [Outcome.andThen, execSeq, exec, State.fall, Nat.add_assoc]
  | sub a b iha ihb =>
    intro s v h
    simp only [eval] at h
    split at h
    · cases h
    · rename_i x hx
      split at h
      · cases h
      · rename_i y hy; cases h
        rw [code, execSeq_append, execSeq_append, iha s x hx]
        simp only [Outcome.andThen]
        rw [ihb { s with pc := s.pc + a.code.length, dstack := x :: s.dstack } y hy]
        simp [Outcome.andThen, execSeq, exec, State.fall, Nat.add_assoc]
  | mul a b iha ihb =>
    intro s v h
    simp only [eval] at h
    split at h
    · cases h
    · rename_i x hx
      split at h
      · cases h
      · rename_i y hy; cases h
        rw [code, execSeq_append, execSeq_append, iha s x hx]
        simp only [Outcome.andThen]
        rw [ihb { s with pc := s.pc + a.code.length, dstack := x :: s.dstack } y hy]
        simp [Outcome.andThen, execSeq, exec, State.fall, Nat.add_assoc]
  | load a ih =>
    intro s v h
    simp only [eval] at h
    split at h
    · cases h
    · rename_i x hx
      split at h
      · rename_i hr; cases h
        rw [code, execSeq_append, ih s x hx]
        simp [Outcome.andThen, execSeq, exec, State.fall, hr, Nat.add_assoc]
      · cases h

theorem code_err {n : Nat} (e : RExpr n) :
    ∀ (s : State n) (t : Trap), e.eval s.regs s.mem = .error t →
      execSeq e.code s = .trapped t := by
  induction e with
  | const w => intro s t h; simp [eval] at h
  | reg r => intro s t h; simp [eval] at h
  | add a b iha ihb =>
    intro s t h
    simp only [eval] at h
    split at h
    · rename_i _ hx; cases h
      rw [code, execSeq_append, execSeq_append, iha s _ hx] <;> rfl
    · rename_i x hx
      split at h
      · rename_i _ hy; cases h
        rw [code, execSeq_append, execSeq_append, code_ok a s x hx]
        simp only [Outcome.andThen]
        rw [ihb { s with pc := s.pc + a.code.length, dstack := x :: s.dstack } _ hy] <;> rfl
      · cases h
  | sub a b iha ihb =>
    intro s t h
    simp only [eval] at h
    split at h
    · rename_i _ hx; cases h
      rw [code, execSeq_append, execSeq_append, iha s _ hx] <;> rfl
    · rename_i x hx
      split at h
      · rename_i _ hy; cases h
        rw [code, execSeq_append, execSeq_append, code_ok a s x hx]
        simp only [Outcome.andThen]
        rw [ihb { s with pc := s.pc + a.code.length, dstack := x :: s.dstack } _ hy] <;> rfl
      · cases h
  | mul a b iha ihb =>
    intro s t h
    simp only [eval] at h
    split at h
    · rename_i _ hx; cases h
      rw [code, execSeq_append, execSeq_append, iha s _ hx] <;> rfl
    · rename_i x hx
      split at h
      · rename_i _ hy; cases h
        rw [code, execSeq_append, execSeq_append, code_ok a s x hx]
        simp only [Outcome.andThen]
        rw [ihb { s with pc := s.pc + a.code.length, dstack := x :: s.dstack } _ hy] <;> rfl
      · cases h
  | load a ih =>
    intro s t h
    simp only [eval] at h
    split at h
    · rename_i _ hx; cases h
      rw [code, execSeq_append, ih s _ hx] <;> rfl
    · rename_i x hx
      split at h
      · cases h
      · rename_i hr; cases h
        rw [code, execSeq_append, code_ok a s x hx]
        simp [Outcome.andThen, execSeq, exec, State.fall, hr]

end RExpr

end IR
end WordDialect
