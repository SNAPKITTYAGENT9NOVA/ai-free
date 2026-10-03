import WordDialect
import WordIR

/-!
# Wolfram.Scalar

Wolfram scalar arithmetic: `Plus`, `Times`, `Subtract`, `Minus` over integers, with symbols
bound to memory cells.

Mathematical meaning: a scalar expression denotes an *integer* (`evalZ`); a symbol denotes the
signed integer stored in its cell. The machine computes in `Word n`, i.e. modulo `2^n`, so the
correctness theorems say the machine's word is `ofInt n z` where `z` is the mathematical
value: exact integer arithmetic reduced modulo `2^n`.
-/

namespace WordDialect
namespace Wolfram

open IR

inductive WExpr where
  | int (z : Int)
  | sym (x : Nat)
  | plus (a b : WExpr)
  | times (a b : WExpr)
  | subtract (a b : WExpr)
  | minus (a : WExpr)

/-- Mathematical value. Left operand before right; reading an unaddressable cell traps. -/
def evalZ {n : Nat} (addr : Nat → Word n) : WExpr → Memory n → Except Trap Int
  | .int z, _ => .ok z
  | .sym x, m =>
    match m.read? (addr x) with
    | some w => .ok w.toInt
    | none => .error .badAddress
  | .plus a b, m =>
    match evalZ addr a m with
    | .error t => .error t
    | .ok x =>
      match evalZ addr b m with
      | .error t => .error t
      | .ok y => .ok (x + y)
  | .times a b, m =>
    match evalZ addr a m with
    | .error t => .error t
    | .ok x =>
      match evalZ addr b m with
      | .error t => .error t
      | .ok y => .ok (x * y)
  | .subtract a b, m =>
    match evalZ addr a m with
    | .error t => .error t
    | .ok x =>
      match evalZ addr b m with
      | .error t => .error t
      | .ok y => .ok (x - y)
  | .minus a, m =>
    match evalZ addr a m with
    | .error t => .error t
    | .ok x => .ok (-x)

/-- Lowering to register/memory word expressions. The IR never sees a Wolfram head. -/
def lower {n : Nat} (addr : Nat → Word n) : WExpr → RExpr n
  | .int z => .const (BitVec.ofInt n z)
  | .sym x => .load (.const (addr x))
  | .plus a b => .add (lower addr a) (lower addr b)
  | .times a b => .mul (lower addr a) (lower addr b)
  | .subtract a b => .sub (lower addr a) (lower addr b)
  | .minus a => .sub (.const 0#n) (lower addr a)

theorem ofInt_sub' {n : Nat} (x y : Int) :
    BitVec.ofInt n (x - y) = BitVec.ofInt n x - BitVec.ofInt n y := by
  rw [Int.sub_eq_add_neg, BitVec.ofInt_add, BitVec.ofInt_neg, BitVec.sub_eq_add_neg]

theorem lower_eval_ok {n : Nat} (addr : Nat → Word n) (e : WExpr) :
    ∀ (regs : Nat → Word n) (mem : Memory n) (z : Int), evalZ addr e mem = .ok z →
      (lower addr e).eval regs mem = .ok (BitVec.ofInt n z) := by
  induction e with
  | int z => intro regs mem z' h; simp only [evalZ] at h; cases h; simp [lower, RExpr.eval]
  | sym x =>
    intro regs mem z h
    simp only [evalZ] at h
    split at h
    · rename_i w hr; cases h
      simp [lower, RExpr.eval, hr, BitVec.ofInt_toInt]
    · cases h
  | plus a b iha ihb =>
    intro regs mem z h
    simp only [evalZ] at h
    split at h
    · cases h
    · rename_i x hx
      split at h
      · cases h
      · rename_i y hy; cases h
        simp [lower, RExpr.eval, iha regs mem x hx, ihb regs mem y hy, BitVec.ofInt_add]
  | times a b iha ihb =>
    intro regs mem z h
    simp only [evalZ] at h
    split at h
    · cases h
    · rename_i x hx
      split at h
      · cases h
      · rename_i y hy; cases h
        simp [lower, RExpr.eval, iha regs mem x hx, ihb regs mem y hy, BitVec.ofInt_mul]
  | subtract a b iha ihb =>
    intro regs mem z h
    simp only [evalZ] at h
    split at h
    · cases h
    · rename_i x hx
      split at h
      · cases h
      · rename_i y hy; cases h
        simp [lower, RExpr.eval, iha regs mem x hx, ihb regs mem y hy, ofInt_sub']
  | minus a iha =>
    intro regs mem z h
    simp only [evalZ] at h
    split at h
    · cases h
    · rename_i x hx; cases h
      simp [lower, RExpr.eval, iha regs mem x hx, BitVec.ofInt_neg, BitVec.sub_eq_add_neg]

theorem lower_eval_err {n : Nat} (addr : Nat → Word n) (e : WExpr) :
    ∀ (regs : Nat → Word n) (mem : Memory n) (t : Trap), evalZ addr e mem = .error t →
      (lower addr e).eval regs mem = .error t := by
  induction e with
  | int z => intro regs mem t h; simp [evalZ] at h
  | sym x =>
    intro regs mem t h
    simp only [evalZ] at h
    split at h
    · cases h
    · rename_i hr; cases h; simp [lower, RExpr.eval, hr]
  | plus a b iha ihb =>
    intro regs mem t h
    simp only [evalZ] at h
    split at h
    · rename_i _ hx; cases h; simp [lower, RExpr.eval, iha regs mem _ hx]
    · rename_i x hx
      split at h
      · rename_i _ hy; cases h; simp [lower, RExpr.eval, lower_eval_ok addr a regs mem x hx, ihb regs mem _ hy]
      · cases h
  | times a b iha ihb =>
    intro regs mem t h
    simp only [evalZ] at h
    split at h
    · rename_i _ hx; cases h; simp [lower, RExpr.eval, iha regs mem _ hx]
    · rename_i x hx
      split at h
      · rename_i _ hy; cases h; simp [lower, RExpr.eval, lower_eval_ok addr a regs mem x hx, ihb regs mem _ hy]
      · cases h
  | subtract a b iha ihb =>
    intro regs mem t h
    simp only [evalZ] at h
    split at h
    · rename_i _ hx; cases h; simp [lower, RExpr.eval, iha regs mem _ hx]
    · rename_i x hx
      split at h
      · rename_i _ hy; cases h; simp [lower, RExpr.eval, lower_eval_ok addr a regs mem x hx, ihb regs mem _ hy]
      · cases h
  | minus a iha =>
    intro regs mem t h
    simp only [evalZ] at h
    split at h
    · rename_i _ hx; cases h; simp [lower, RExpr.eval, iha regs mem _ hx]
    · cases h

/-- Straight-line code for a scalar expression; leaves its value on the data stack. -/
def compile {n : Nat} (addr : Nat → Word n) (e : WExpr) : List (Instr n) := (lower addr e).code

theorem compile_straight {n : Nat} (addr : Nat → Word n) (e : WExpr) :
    ∀ i ∈ compile addr e, i.isStraight = true := RExpr.code_straight _

/-- The machine leaves exactly `ofInt n z` (the mathematical value, mod `2^n`) on the stack. -/
theorem compile_ok {n : Nat} (addr : Nat → Word n) (e : WExpr) (s : State n) (z : Int)
    (h : evalZ addr e s.mem = .ok z) :
    execSeq (compile addr e) s =
      .next { s with pc := s.pc + (compile addr e).length,
                     dstack := BitVec.ofInt n z :: s.dstack } :=
  RExpr.code_ok _ s _ (lower_eval_ok addr e s.regs s.mem z h)

theorem compile_err {n : Nat} (addr : Nat → Word n) (e : WExpr) (s : State n) (t : Trap)
    (h : evalZ addr e s.mem = .error t) :
    execSeq (compile addr e) s = .trapped t :=
  RExpr.code_err _ s t (lower_eval_err addr e s.regs s.mem t h)

/-! ## `Set[x, e]` -/

def setSem {n : Nat} (addr : Nat → Word n) (x : Nat) (e : WExpr) (m : Memory n) :
    Except Trap (Memory n) :=
  match evalZ addr e m with
  | .error t => .error t
  | .ok z =>
    match m.write? (addr x) (BitVec.ofInt n z) with
    | some m' => .ok m'
    | none => .error .badAddress

def setCode {n : Nat} (addr : Nat → Word n) (x : Nat) (e : WExpr) : List (Instr n) :=
  compile addr e ++ [.word (addr x), .store]

theorem setCode_straight {n : Nat} (addr : Nat → Word n) (x : Nat) (e : WExpr) :
    ∀ i ∈ setCode addr x e, i.isStraight = true := by
  intro i hi
  simp only [setCode, List.mem_append, List.mem_cons, List.not_mem_nil, or_false] at hi
  rcases hi with hi | rfl | rfl
  · exact compile_straight addr e i hi
  · rfl
  · rfl

theorem setCode_ok {n : Nat} (addr : Nat → Word n) (x : Nat) (e : WExpr) (s : State n)
    (m' : Memory n) (h : setSem addr x e s.mem = .ok m') :
    execSeq (setCode addr x e) s =
      .next { s with pc := s.pc + (setCode addr x e).length, mem := m' } := by
  simp only [setSem] at h
  split at h
  · cases h
  · rename_i z hz
    split at h
    · rename_i hw; cases h
      rw [setCode, execSeq_append, compile_ok addr e s z hz]
      simp [Outcome.andThen, execSeq, exec, State.fall, hw, Nat.add_assoc]
    · cases h

theorem setCode_err {n : Nat} (addr : Nat → Word n) (x : Nat) (e : WExpr) (s : State n)
    (t : Trap) (h : setSem addr x e s.mem = .error t) :
    execSeq (setCode addr x e) s = .trapped t := by
  simp only [setSem] at h
  split at h
  · rename_i _ hz; cases h
    rw [setCode, execSeq_append, compile_err addr e s _ hz] <;> rfl
  · rename_i z hz
    split at h
    · cases h
    · rename_i hw; cases h
      rw [setCode, execSeq_append, compile_ok addr e s z hz]
      simp [Outcome.andThen, execSeq, exec, State.fall, hw]

/-- Whole program `Set[x, e]` from the initial machine state. -/
theorem setProgram_ok {n : Nat} (addr : Nat → Word n) (x : Nat) (e : WExpr) (mem m' : Memory n)
    (h : setSem addr x e mem = .ok m') :
    ∃ s', WordDialect.Exec (setCode addr x e ++ [.halt]) (State.init mem) (.halted s') ∧
      s'.mem = m' ∧ s'.dstack = [] := by
  have := setCode_ok addr x e (State.init mem) m' h
  exact ⟨_, exec_straight_halt (setCode_straight addr x e) rfl this, rfl, rfl⟩

theorem setProgram_err {n : Nat} (addr : Nat → Word n) (x : Nat) (e : WExpr) (mem : Memory n)
    (t : Trap) (h : setSem addr x e mem = .error t) :
    WordDialect.Exec (setCode addr x e ++ [.halt]) (State.init mem) (.trapped t) :=
  exec_straight_trap (setCode_straight addr x e) rfl (setCode_err addr x e (State.init mem) t h)

end Wolfram
end WordDialect
