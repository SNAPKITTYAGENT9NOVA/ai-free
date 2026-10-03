import WordDialect
import WordIR

/-!
# Forth.Semantics

Reference semantics of the supported Forth subset, defined directly on a Forth state
(data stack + memory) with no reference to the machine or the IR. The translation to
Universal Word IR is proved correct against this definition.

Conventions (ANS Forth):
* `/` is signed division truncating toward zero (symmetric division); division by zero traps.
* Truth flags are all-ones (`-1`) for true and `0` for false.
* `@ ( addr -- x )`, `! ( x addr -- )`; memory is word-addressed.
* `lshift`/`rshift` are logical shifts.
-/

namespace WordDialect
namespace Forth

open IR

inductive Op where
  | lit (z : Int)
  | dup | drop | swap | over | rot
  | add | sub | mul | div
  | and | or | xor | invert | lshift | rshift
  | eq | ne | lt | gt | ult | ugt
  | fetch | store

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
`BEGIN body UNTIL rest`. -/
inductive Block where
  | nil
  | op (o : Op) (rest : Block)
  | ite (t e rest : Block)
  | untilL (body rest : Block)

/-- Big-step semantics. `Run b st r` says running `b` from `st` produces result `r`.
Non-terminating runs have no derivation. -/
inductive Run {n : Nat} : Block → FState n → Except Trap (FState n) → Prop where
  | nil {st} : Run .nil st (.ok st)
  | opOk {o rest st st' r} :
      o.sem st = .ok st' → Run rest st' r → Run (.op o rest) st r
  | opErr {o rest st t} :
      o.sem st = .error t → Run (.op o rest) st (.error t)
  | iteUnder {t e rest m} :
      Run (.ite t e rest) ⟨[], m⟩ (.error .stackUnderflow)
  | iteTrue {t e rest c d m st1 r} :
      Word.isTrue c = true → Run t ⟨d, m⟩ (.ok st1) → Run rest st1 r →
      Run (.ite t e rest) ⟨c :: d, m⟩ r
  | iteTrueErr {t e rest c d m x} :
      Word.isTrue c = true → Run t ⟨d, m⟩ (.error x) →
      Run (.ite t e rest) ⟨c :: d, m⟩ (.error x)
  | iteFalse {t e rest c d m st1 r} :
      Word.isTrue c = false → Run e ⟨d, m⟩ (.ok st1) → Run rest st1 r →
      Run (.ite t e rest) ⟨c :: d, m⟩ r
  | iteFalseErr {t e rest c d m x} :
      Word.isTrue c = false → Run e ⟨d, m⟩ (.error x) →
      Run (.ite t e rest) ⟨c :: d, m⟩ (.error x)
  | untilBodyErr {body rest st x} :
      Run body st (.error x) → Run (.untilL body rest) st (.error x)
  | untilUnder {body rest st m} :
      Run body st (.ok ⟨[], m⟩) → Run (.untilL body rest) st (.error .stackUnderflow)
  | untilExit {body rest st c d m r} :
      Run body st (.ok ⟨c :: d, m⟩) → Word.isTrue c = true → Run rest ⟨d, m⟩ r →
      Run (.untilL body rest) st r
  | untilAgain {body rest st c d m r} :
      Run body st (.ok ⟨c :: d, m⟩) → Word.isTrue c = false →
      Run (.untilL body rest) ⟨d, m⟩ r → Run (.untilL body rest) st r

/-- The run relation is functional: a block and a state determine the result. -/
theorem Run.deterministic {n : Nat} {b : Block} {st : FState n} {r₁ r₂ : Except Trap (FState n)}
    (h₁ : Run b st r₁) (h₂ : Run b st r₂) : r₁ = r₂ := by
  induction h₁ generalizing r₂ with
  | nil => cases h₂; rfl
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
    | iteTrueErr _ ht' => have := iht ht'; cases this
    | iteFalse hc' => rw [hc] at hc'; cases hc'
    | iteFalseErr hc' => rw [hc] at hc'; cases hc'
  | iteTrueErr hc ht iht =>
    cases h₂ with
    | iteTrue _ ht' _ => have := iht ht'; cases this
    | iteTrueErr _ ht' => have := iht ht'; cases this; rfl
    | iteFalse hc' => rw [hc] at hc'; cases hc'
    | iteFalseErr hc' => rw [hc] at hc'; cases hc'
  | iteFalse hc he hr ihe ihr =>
    cases h₂ with
    | iteTrue hc' => rw [hc] at hc'; cases hc'
    | iteTrueErr hc' => rw [hc] at hc'; cases hc'
    | iteFalse _ he' hr' =>
      have := ihe he'; cases this; exact ihr hr'
    | iteFalseErr _ he' => have := ihe he'; cases this
  | iteFalseErr hc he ihe =>
    cases h₂ with
    | iteTrue hc' => rw [hc] at hc'; cases hc'
    | iteTrueErr hc' => rw [hc] at hc'; cases hc'
    | iteFalse _ he' _ => have := ihe he'; cases this
    | iteFalseErr _ he' => have := ihe he'; cases this; rfl
  | untilBodyErr hb ihb =>
    cases h₂ with
    | untilBodyErr hb' => have := ihb hb'; cases this; rfl
    | untilUnder hb' => have := ihb hb'; cases this
    | untilExit hb' => have := ihb hb'; cases this
    | untilAgain hb' => have := ihb hb'; cases this
  | untilUnder hb ihb =>
    cases h₂ with
    | untilBodyErr hb' => have := ihb hb'; cases this
    | untilUnder hb' => rfl
    | untilExit hb' => have := ihb hb'; cases this
    | untilAgain hb' => have := ihb hb'; cases this
  | untilExit hb hc hr ihb ihr =>
    cases h₂ with
    | untilBodyErr hb' => have := ihb hb'; cases this
    | untilUnder hb' => have := ihb hb'; cases this
    | untilExit hb' _ hr' => have := ihb hb'; cases this; exact ihr hr'
    | untilAgain hb' hc' _ => have := ihb hb'; cases this; rw [hc] at hc'; cases hc'
  | untilAgain hb hc hl ihb ihl =>
    cases h₂ with
    | untilBodyErr hb' => have := ihb hb'; cases this
    | untilUnder hb' => have := ihb hb'; cases this
    | untilExit hb' hc' _ => have := ihb hb'; cases this; rw [hc] at hc'; cases hc'
    | untilAgain hb' _ hl' => have := ihb hb'; cases this; exact ihl hl'

end Forth
end WordDialect
