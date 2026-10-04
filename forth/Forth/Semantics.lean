import WordDialect
import WordIR

/-!
# Forth.Semantics

Reference semantics of the supported Forth subset, defined directly on a Forth state
(data stack + memory) with no reference to the machine or the IR. The translation to
Universal Word IR is proved correct against this definition.

Conventions (ANS Forth):
* `/` is signed division truncating toward zero (symmetric division); division by zero traps.
* `MOD` is the remainder consistent with `/`: `a MOD b = a - (a / b) * b`, so its sign follows
  `a`; `MOD` by zero traps `divideByZero`, like `/`.
* Truth flags are all-ones (`-1`) for true and `0` for false; `0=` turns zero into `-1` and
  anything else into `0`.
* `@ ( addr -- x )`, `! ( x addr -- )`; memory is word-addressed.
* `lshift`/`rshift` are logical shifts.

Memory: `FState.mem` is the whole IR memory; `@`/`!` trap `badAddress` outside its valid
cells. The `VARIABLE`s of a program are the cells `0 … vars - 1` (`Program.vars`); a program
may assume exactly that those cells are valid (`Program.MemOk`) and nothing about any other
cell, nor about the initial contents of any cell. A variable's name pushes its address, so
after parsing it is a literal; a `CONSTANT` is likewise a literal.

`EXIT` leaves the word being executed, so a run of a block ends in one of three ways (`Res`):
it falls off the end, it executes `EXIT`, or it traps.
-/

namespace WordDialect
namespace Forth

open IR

inductive Op where
  | lit (z : Int)
  | dup | drop | swap | over | rot
  | add | sub | mul | div | mod
  | and | or | xor | invert | lshift | rshift
  | eq | ne | lt | gt | ult | ugt | zeq
  | fetch | store
  deriving DecidableEq, Repr

structure FState (n : Nat) where
  stack : List (Word n)
  mem   : Memory n


namespace Op

def sem {n : Nat} : Op → FState n → Except Trap (FState n)
  | .lit z, st => .ok { st with stack := BitVec.ofInt n z :: st.stack }
  | .dup, ⟨a :: d, m⟩ => .ok ⟨a :: a :: d, m⟩
  | .drop, ⟨_ :: d, m⟩ => .ok ⟨d, m⟩
  | .swap, ⟨b :: a :: d, m⟩ => .ok ⟨a :: b :: d, m⟩
  | .over, ⟨b :: a :: d, m⟩ => .ok ⟨a :: b :: a :: d, m⟩
  | .rot, ⟨c :: b :: a :: d, m⟩ => .ok ⟨a :: c :: b :: d, m⟩
  | .add, ⟨b :: a :: d, m⟩ => .ok ⟨(a + b) :: d, m⟩
  | .sub, ⟨b :: a :: d, m⟩ => .ok ⟨(a - b) :: d, m⟩
  | .mul, ⟨b :: a :: d, m⟩ => .ok ⟨(a * b) :: d, m⟩
  | .div, ⟨b :: a :: d, m⟩ =>
      if b = 0#n then .error .divideByZero else .ok ⟨a.sdiv b :: d, m⟩
  | .mod, ⟨b :: a :: d, m⟩ =>
      if b = 0#n then .error .divideByZero else .ok ⟨(a - a.sdiv b * b) :: d, m⟩
  | .and, ⟨b :: a :: d, m⟩ => .ok ⟨(a &&& b) :: d, m⟩
  | .or, ⟨b :: a :: d, m⟩ => .ok ⟨(a ||| b) :: d, m⟩
  | .xor, ⟨b :: a :: d, m⟩ => .ok ⟨(a ^^^ b) :: d, m⟩
  | .invert, ⟨a :: d, m⟩ => .ok ⟨(~~~a) :: d, m⟩
  | .lshift, ⟨u :: x :: d, m⟩ => .ok ⟨Word.shl x u :: d, m⟩
  | .rshift, ⟨u :: x :: d, m⟩ => .ok ⟨Word.shr x u :: d, m⟩
  | .eq, ⟨b :: a :: d, m⟩ => .ok ⟨flag (Cond.eval .eq a b) :: d, m⟩
  | .ne, ⟨b :: a :: d, m⟩ => .ok ⟨flag (Cond.eval .ne a b) :: d, m⟩
  | .lt, ⟨b :: a :: d, m⟩ => .ok ⟨flag (Cond.eval .slt a b) :: d, m⟩
  | .gt, ⟨b :: a :: d, m⟩ => .ok ⟨flag (Cond.eval .sgt a b) :: d, m⟩
  | .ult, ⟨b :: a :: d, m⟩ => .ok ⟨flag (Cond.eval .ult a b) :: d, m⟩
  | .ugt, ⟨b :: a :: d, m⟩ => .ok ⟨flag (Cond.eval .ugt a b) :: d, m⟩
  | .zeq, ⟨a :: d, m⟩ => .ok ⟨flag (Cond.eval .eq a 0#n) :: d, m⟩
  | .fetch, ⟨a :: d, m⟩ =>
      match m.read? a with
      | some v => .ok ⟨v :: d, m⟩
      | none => .error .badAddress
  | .store, ⟨a :: v :: d, m⟩ =>
      match m.write? a v with
      | some m' => .ok ⟨d, m'⟩
      | none => .error .badAddress
  | _, _ => .error .stackUnderflow

end Op

/-- A Forth block. `ite t e rest` is `IF t ELSE e THEN rest`; `untilL body rest` is
`BEGIN body UNTIL rest`; `call i rest` executes the colon definition with index `i` in the
dictionary, then `rest`; `exit rest` is `EXIT`, which leaves the current word (`rest` is dead
code, kept so that a block records its source text). -/
inductive Block where
  | nil
  | op (o : Op) (rest : Block)
  | ite (t e rest : Block)
  | untilL (body rest : Block)
  | call (i : Nat) (rest : Block)
  | exit (rest : Block)
  deriving DecidableEq, Repr

/-- A Forth program: a dictionary of colon definitions (word `i` is `defs[i]`), the main
block, and the number of `VARIABLE` cells (memory cells `0 … vars - 1`). Definitions may call
themselves and each other. -/
structure Program where
  defs : List Block
  main : Block
  vars : Nat := 0
  deriving DecidableEq, Repr

/-- The memory a program may assume: every variable cell is valid. -/
def Program.MemOk {n : Nat} (P : Program) (mem : Memory n) : Prop :=
  ∀ a, a < P.vars → mem.valid (BitVec.ofNat n a) = true

/-- How a run of a block ends: it fell off the end (`ok`), it executed `EXIT` (`exit`), or it
trapped (`error`). -/
inductive Res (n : Nat) where
  | ok (st : FState n)
  | exit (st : FState n)
  | error (t : Trap)

namespace Res

def isOk {n : Nat} : Res n → Bool
  | .ok _ => true
  | _ => false

/-- The state a called word returns with: after falling off its end or after `EXIT`. -/
def returned {n : Nat} : Res n → Option (FState n)
  | .ok st => some st
  | .exit st => some st
  | .error _ => none

end Res

/-- Big-step semantics. `Run defs b st r` says running `b` from `st`, with dictionary `defs`,
produces result `r`. Non-terminating runs (including unbounded recursion) have no derivation.

An abrupt result (`exit` or `error`, i.e. `isOk = false`) of a sub-block ends the enclosing
block with the same result. A call continues after the callee returns, whether the callee fell
off its end or executed `EXIT`; an `EXIT` thus never propagates out of a call.

Calling an index outside the dictionary is an explicit error, `badPc`: it is the trap the
lowered code raises, since such a call targets the address just past the program. The parser
never produces such a call. -/
inductive Run {n : Nat} (defs : List Block) : Block → FState n → Res n → Prop where
  | nil {st} : Run defs .nil st (.ok st)
  | exit {rest st} : Run defs (.exit rest) st (.exit st)
  | opOk {o rest st st' r} :
      o.sem st = .ok st' → Run defs rest st' r → Run defs (.op o rest) st r
  | opErr {o rest st t} :
      o.sem st = .error t → Run defs (.op o rest) st (.error t)
  | iteUnder {t e rest m} :
      Run defs (.ite t e rest) ⟨[], m⟩ (.error .stackUnderflow)
  | iteTrue {t e rest c d m st1 r} :
      Word.isTrue c = true → Run defs t ⟨d, m⟩ (.ok st1) → Run defs rest st1 r →
      Run defs (.ite t e rest) ⟨c :: d, m⟩ r
  | iteTrueStop {t e rest c d m r} :
      Word.isTrue c = true → Run defs t ⟨d, m⟩ r → r.isOk = false →
      Run defs (.ite t e rest) ⟨c :: d, m⟩ r
  | iteFalse {t e rest c d m st1 r} :
      Word.isTrue c = false → Run defs e ⟨d, m⟩ (.ok st1) → Run defs rest st1 r →
      Run defs (.ite t e rest) ⟨c :: d, m⟩ r
  | iteFalseStop {t e rest c d m r} :
      Word.isTrue c = false → Run defs e ⟨d, m⟩ r → r.isOk = false →
      Run defs (.ite t e rest) ⟨c :: d, m⟩ r
  | untilBodyStop {body rest st r} :
      Run defs body st r → r.isOk = false → Run defs (.untilL body rest) st r
  | untilUnder {body rest st m} :
      Run defs body st (.ok ⟨[], m⟩) → Run defs (.untilL body rest) st (.error .stackUnderflow)
  | untilDone {body rest st c d m r} :
      Run defs body st (.ok ⟨c :: d, m⟩) → Word.isTrue c = true → Run defs rest ⟨d, m⟩ r →
      Run defs (.untilL body rest) st r
  | untilAgain {body rest st c d m r} :
      Run defs body st (.ok ⟨c :: d, m⟩) → Word.isTrue c = false →
      Run defs (.untilL body rest) ⟨d, m⟩ r → Run defs (.untilL body rest) st r
  | callOk {i rest st body r1 st1 r} :
      defs[i]? = some body → Run defs body st r1 → r1.returned = some st1 →
      Run defs rest st1 r → Run defs (.call i rest) st r
  | callErr {i rest st body x} :
      defs[i]? = some body → Run defs body st (.error x) → Run defs (.call i rest) st (.error x)
  | callUndef {i rest st} :
      defs[i]? = none → Run defs (.call i rest) st (.error .badPc)

/-- The run relation is functional: a block and a state determine the result. -/
theorem Run.deterministic {n : Nat} {defs : List Block} {b : Block} {st : FState n}
    {r₁ r₂ : Res n}
    (h₁ : Run defs b st r₁) (h₂ : Run defs b st r₂) : r₁ = r₂ := by
  induction h₁ generalizing r₂ with
  | nil => cases h₂; rfl
  | exit => cases h₂; rfl
  | opOk hs _ ih =>
    cases h₂ with
    | opOk hs' h' => rw [hs] at hs'; cases hs'; exact ih h'
    | opErr hs' => rw [hs] at hs'; cases hs'
  | opErr hs =>
    cases h₂ with
    | opOk hs' _ => rw [hs] at hs'; cases hs'
    | opErr hs' => rw [hs] at hs'; cases hs'; rfl
  | iteUnder => cases h₂ <;> rfl
  | iteTrue hc ht hr iht ihr =>
    cases h₂ with
    | iteTrue _ ht' hr' =>
      have := iht ht'; cases this; exact ihr hr'
    | iteTrueStop _ ht' hk => have := iht ht'; subst this; cases hk
    | iteFalse hc' => rw [hc] at hc'; cases hc'
    | iteFalseStop hc' => rw [hc] at hc'; cases hc'
  | iteTrueStop hc ht hk iht =>
    cases h₂ with
    | iteTrue _ ht' _ => have := iht ht'; subst this; cases hk
    | iteTrueStop _ ht' => exact iht ht'
    | iteFalse hc' => rw [hc] at hc'; cases hc'
    | iteFalseStop hc' => rw [hc] at hc'; cases hc'
  | iteFalse hc he hr ihe ihr =>
    cases h₂ with
    | iteTrue hc' => rw [hc] at hc'; cases hc'
    | iteTrueStop hc' => rw [hc] at hc'; cases hc'
    | iteFalse _ he' hr' =>
      have := ihe he'; cases this; exact ihr hr'
    | iteFalseStop _ he' hk => have := ihe he'; subst this; cases hk
  | iteFalseStop hc he hk ihe =>
    cases h₂ with
    | iteTrue hc' => rw [hc] at hc'; cases hc'
    | iteTrueStop hc' => rw [hc] at hc'; cases hc'
    | iteFalse _ he' _ => have := ihe he'; subst this; cases hk
    | iteFalseStop _ he' => exact ihe he'
  | untilBodyStop hb hk ihb =>
    cases h₂ with
    | untilBodyStop hb' => exact ihb hb'
    | untilUnder hb' => have := ihb hb'; subst this; cases hk
    | untilDone hb' => have := ihb hb'; subst this; cases hk
    | untilAgain hb' => have := ihb hb'; subst this; cases hk
  | untilUnder hb ihb =>
    cases h₂ with
    | untilBodyStop hb' hk => have := ihb hb'; subst this; cases hk
    | untilUnder hb' => rfl
    | untilDone hb' => have := ihb hb'; cases this
    | untilAgain hb' => have := ihb hb'; cases this
  | untilDone hb hc hr ihb ihr =>
    cases h₂ with
    | untilBodyStop hb' hk => have := ihb hb'; subst this; cases hk
    | untilUnder hb' => have := ihb hb'; cases this
    | untilDone hb' _ hr' => have := ihb hb'; cases this; exact ihr hr'
    | untilAgain hb' hc' _ => have := ihb hb'; cases this; rw [hc] at hc'; cases hc'
  | untilAgain hb hc hl ihb ihl =>
    cases h₂ with
    | untilBodyStop hb' hk => have := ihb hb'; subst this; cases hk
    | untilUnder hb' => have := ihb hb'; cases this
    | untilDone hb' hc' _ => have := ihb hb'; cases this; rw [hc] at hc'; cases hc'
    | untilAgain hb' _ hl' => have := ihb hb'; cases this; exact ihl hl'
  | callOk hd hb hret hr ihb ihr =>
    cases h₂ with
    | callOk hd' hb' hret' hr' =>
      rw [hd] at hd'; cases hd'; have := ihb hb'; subst this
      rw [hret] at hret'; cases hret'; exact ihr hr'
    | callErr hd' hb' =>
      rw [hd] at hd'; cases hd'; have := ihb hb'; subst this; cases hret
    | callUndef hd' => rw [hd] at hd'; cases hd'
  | callErr hd hb ihb =>
    cases h₂ with
    | callOk hd' hb' hret' =>
      rw [hd] at hd'; cases hd'; have := ihb hb'; subst this; cases hret'
    | callErr hd' hb' => rw [hd] at hd'; cases hd'; have := ihb hb'; cases this; rfl
    | callUndef hd' => rw [hd] at hd'; cases hd'
  | callUndef hd =>
    cases h₂ with
    | callOk hd' => rw [hd] at hd'; cases hd'
    | callErr hd' => rw [hd] at hd'; cases hd'
    | callUndef => rfl

end Forth
end WordDialect
