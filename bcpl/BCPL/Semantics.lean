import WordDialect
import WordIR

/-!
# BCPL.Semantics

Abstract syntax and reference semantics of the supported BCPL subset. Defined directly on
word-addressed memory, with no reference to the machine or the IR; the lowering is proved
correct against this definition.

BCPL is typeless: every value is a word, a variable is a memory cell, and `!e` / `@x` are
word indirection and address-of. Variable `x` lives at address `addr x` (the global vector).

Conventions:
* Relational operators yield BCPL truth values: `-1` (true) and `0` (false).
* A condition is true iff its value is nonzero.
* `/` is signed division truncating toward zero; division by zero traps.
* `<<` and `>>` are logical shifts.
* Order of evaluation is fixed: left operand before right; in `lhs := rhs`, the right-hand
  side is evaluated before an indirect left-hand side.
-/

namespace WordDialect
namespace BCPL

open IR

abbrev Var := Nat

inductive BinOp where
  | add | sub | mul | div
  | and | or | neqv
  | shl | shr
  | eq | ne | lt | gt | le | ge

inductive UnOp where
  | neg | not

inductive Expr where
  | num (z : Int)
  | var (x : Var)
  | addrOf (x : Var)
  | rv (e : Expr)
  | un (o : UnOp) (e : Expr)
  | bin (o : BinOp) (a b : Expr)

inductive LVal where
  | var (x : Var)
  | rv (e : Expr)

inductive Stmt where
  | skip
  | assign (l : LVal) (e : Expr)
  | seq (a b : Stmt)
  | test (c : Expr) (t e : Stmt)
  | while (c : Expr) (body : Stmt)

def readW {n : Nat} (m : Memory n) (a : Word n) : Except Trap (Word n) :=
  match m.read? a with
  | some v => .ok v
  | none => .error .badAddress

def writeW {n : Nat} (m : Memory n) (a v : Word n) : Except Trap (Memory n) :=
  match m.write? a v with
  | some m' => .ok m'
  | none => .error .badAddress

namespace BinOp

def sem {n : Nat} : BinOp → Word n → Word n → Except Trap (Word n)
  | .add, a, b => .ok (a + b)
  | .sub, a, b => .ok (a - b)
  | .mul, a, b => .ok (a * b)
  | .div, a, b => if b = 0#n then .error .divideByZero else .ok (a.sdiv b)
  | .and, a, b => .ok (a &&& b)
  | .or, a, b => .ok (a ||| b)
  | .neqv, a, b => .ok (a ^^^ b)
  | .shl, a, b => .ok (Word.shl a b)
  | .shr, a, b => .ok (Word.shr a b)
  | .eq, a, b => .ok (flag (Cond.eval .eq a b))
  | .ne, a, b => .ok (flag (Cond.eval .ne a b))
  | .lt, a, b => .ok (flag (Cond.eval .slt a b))
  | .gt, a, b => .ok (flag (Cond.eval .sgt a b))
  | .le, a, b => .ok (flag (Cond.eval .sle a b))
  | .ge, a, b => .ok (flag (Cond.eval .sge a b))

end BinOp

namespace UnOp

def sem {n : Nat} : UnOp → Word n → Word n
  | .neg, v => 0#n - v
  | .not, v => ~~~v

end UnOp

/-- Expression evaluation. Expressions read memory but never write it. -/
def evalE {n : Nat} (addr : Var → Word n) : Expr → Memory n → Except Trap (Word n)
  | .num z, _ => .ok (BitVec.ofInt n z)
  | .var x, m => readW m (addr x)
  | .addrOf x, _ => .ok (addr x)
  | .rv e, m =>
    match evalE addr e m with
    | .error t => .error t
    | .ok a => readW m a
  | .un o e, m =>
    match evalE addr e m with
    | .error t => .error t
    | .ok v => .ok (o.sem v)
  | .bin o a b, m =>
    match evalE addr a m with
    | .error t => .error t
    | .ok va =>
      match evalE addr b m with
      | .error t => .error t
      | .ok vb => o.sem va vb

def assignSem {n : Nat} (addr : Var → Word n) (l : LVal) (e : Expr) (m : Memory n) :
    Except Trap (Memory n) :=
  match evalE addr e m with
  | .error t => .error t
  | .ok v =>
    match l with
    | .var x => writeW m (addr x) v
    | .rv a =>
      match evalE addr a m with
      | .error t => .error t
      | .ok a' => writeW m a' v

/-- Big-step statement semantics. Non-terminating runs have no derivation. -/
inductive Exec {n : Nat} (addr : Var → Word n) : Stmt → Memory n → Except Trap (Memory n) → Prop where
  | skip {m} : Exec addr .skip m (.ok m)
  | assign {l e m r} : assignSem addr l e m = r → Exec addr (.assign l e) m r
  | seqOk {a b m m1 r} : Exec addr a m (.ok m1) → Exec addr b m1 r → Exec addr (.seq a b) m r
  | seqErr {a b m t} : Exec addr a m (.error t) → Exec addr (.seq a b) m (.error t)
  | testErr {c t e m x} : evalE addr c m = .error x → Exec addr (.test c t e) m (.error x)
  | testTrue {c t e m v r} :
      evalE addr c m = .ok v → Word.isTrue v = true → Exec addr t m r → Exec addr (.test c t e) m r
  | testFalse {c t e m v r} :
      evalE addr c m = .ok v → Word.isTrue v = false → Exec addr e m r → Exec addr (.test c t e) m r
  | whileErr {c body m x} : evalE addr c m = .error x → Exec addr (.while c body) m (.error x)
  | whileExit {c body m v} :
      evalE addr c m = .ok v → Word.isTrue v = false → Exec addr (.while c body) m (.ok m)
  | whileBodyErr {c body m v x} :
      evalE addr c m = .ok v → Word.isTrue v = true → Exec addr body m (.error x) →
      Exec addr (.while c body) m (.error x)
  | whileAgain {c body m v m1 r} :
      evalE addr c m = .ok v → Word.isTrue v = true → Exec addr body m (.ok m1) →
      Exec addr (.while c body) m1 r → Exec addr (.while c body) m r

/-- The statement semantics is functional: a statement and a memory determine the result. -/
theorem Exec.deterministic {n : Nat} {addr : Var → Word n} {s : Stmt} {m : Memory n}
    {r₁ r₂ : Except Trap (Memory n)} (h₁ : Exec addr s m r₁) (h₂ : Exec addr s m r₂) :
    r₁ = r₂ := by
  induction h₁ generalizing r₂ with
  | skip => cases h₂; rfl
  | assign hr => cases h₂ with | assign hr' => rw [← hr, ← hr']
  | seqOk ha hb iha ihb =>
    cases h₂ with
    | seqOk ha' hb' => have := iha ha'; cases this; exact ihb hb'
    | seqErr ha' => have := iha ha'; cases this
  | seqErr ha iha =>
    cases h₂ with
    | seqOk ha' _ => have := iha ha'; cases this
    | seqErr ha' => have := iha ha'; cases this; rfl
  | testErr hc =>
    cases h₂ with
    | testErr hc' => rw [hc] at hc'; cases hc'; rfl
    | testTrue hc' => rw [hc] at hc'; cases hc'
    | testFalse hc' => rw [hc] at hc'; cases hc'
  | testTrue hc ht _ ih =>
    cases h₂ with
    | testErr hc' => rw [hc] at hc'; cases hc'
    | testTrue hc' _ h' => exact ih h'
    | testFalse hc' hf _ => rw [hc] at hc'; cases hc'; rw [ht] at hf; cases hf
  | testFalse hc hf _ ih =>
    cases h₂ with
    | testErr hc' => rw [hc] at hc'; cases hc'
    | testTrue hc' ht _ => rw [hc] at hc'; cases hc'; rw [hf] at ht; cases ht
    | testFalse hc' _ h' => exact ih h'
  | whileErr hc =>
    cases h₂ with
    | whileErr hc' => rw [hc] at hc'; cases hc'; rfl
    | whileExit hc' => rw [hc] at hc'; cases hc'
    | whileBodyErr hc' => rw [hc] at hc'; cases hc'
    | whileAgain hc' => rw [hc] at hc'; cases hc'
  | whileExit hc hf =>
    cases h₂ with
    | whileErr hc' => rw [hc] at hc'; cases hc'
    | whileExit => rfl
    | whileBodyErr hc' ht => rw [hc] at hc'; cases hc'; rw [hf] at ht; cases ht
    | whileAgain hc' ht => rw [hc] at hc'; cases hc'; rw [hf] at ht; cases ht
  | whileBodyErr hc ht hb ihb =>
    cases h₂ with
    | whileErr hc' => rw [hc] at hc'; cases hc'
    | whileExit hc' hf => rw [hc] at hc'; cases hc'; rw [ht] at hf; cases hf
    | whileBodyErr _ _ hb' => have := ihb hb'; cases this; rfl
    | whileAgain _ _ hb' => have := ihb hb'; cases this
  | whileAgain hc ht hb hl ihb ihl =>
    cases h₂ with
    | whileErr hc' => rw [hc] at hc'; cases hc'
    | whileExit hc' hf => rw [hc] at hc'; cases hc'; rw [ht] at hf; cases hf
    | whileBodyErr _ _ hb' => have := ihb hb'; cases this
    | whileAgain _ _ hb' hl' => have := ihb hb'; cases this; exact ihl hl'

end BCPL
end WordDialect
