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
* `/MOD ( a b -- rem quot )` is `MOD` and `/` together; `NEGATE` is `0 - a`; `ABS`, `MIN` and
  `MAX` compare as signed numbers (`ABS` of the most negative number is itself, as it wraps).
  `2DUP 2DROP 2SWAP` act on pairs.

Memory: `FState.mem` is the whole IR memory; `@`/`!` trap `badAddress` outside its valid
cells. The `VARIABLE`s of a program are the cells `0 … vars - 1` (`Program.vars`); a program
may assume exactly that those cells are valid (`Program.MemOk`) and nothing about any other
cell, nor about the initial contents of any cell. A variable's name pushes its address, so
after parsing it is a literal; a `CONSTANT` is likewise a literal.

`EXIT` leaves the word being executed and `LEAVE` the innermost loop, so a run of a block ends
in one of four ways (`Res`): it falls off the end, it executes `EXIT`, it executes `LEAVE`, or it
traps.

Return-data stack: `FState.rstack` is a stack of words *separate from the call frames*, exactly
like the IR's auxiliary stack `astack` (which a call or return never touches). `>R` moves the
data-stack top onto it (`stackUnderflow` if the data stack is empty), `R>` moves its top back and
`R@` copies it (both `returnUnderflow` if it is empty). Because call frames live elsewhere, using
it unbalanced across `EXIT`, a call or a return is *defined* behaviour here (the values simply
stay on it), whereas ANS Forth leaves it undefined.

`limit start DO body LOOP` (`Block.doLoop`): pushes `limit`, then `start` (the index) onto the
return-data stack (`stackUnderflow` if the data stack has fewer than two items), then runs
`body` at least once. After each run of `body` the two top return-data items are taken as
`index` (top) and `limit` (`returnUnderflow` if there are fewer than two); the index becomes
`index + 1`, and the loop ends, dropping both, exactly when `index + 1 = limit` (modular
equality, so `0 0 DO … LOOP` runs `2^n` times; this is ANS `LOOP`'s crossing rule specialised to
the equal case, which is the only case for a loop that counts up by one). Otherwise the
parameters `index + 1` and `limit` are put back and `body` runs again. `I` (`Op.loopI`) copies the
top of the return-data stack (the innermost index; it is `R@` under another name), `J`
(`Op.loopJ`) its third item (the next outer index): both are defined everywhere, trapping
`returnUnderflow` when the stack is too short, so they are also allowed outside a loop. Loop
parameters live on the return-data stack, so they survive calls and recursion. An `EXIT` (or a
trap) inside a loop body ends the loop and the word *without* removing the loop parameters: they
stay on the return-data stack, just as the compiled `RET` leaves the IR's auxiliary stack alone.
`UNLOOP` (`Op.unloop`) removes the top two return-data items (`returnUnderflow` if there are
fewer), so `UNLOOP EXIT` leaves a loop and its word cleanly.

`limit start DO body step +LOOP` (`Block.plusLoop`) is the same, except that after each run of
`body` the step is taken from the data stack (`returnUnderflow` first if the return-data stack
holds fewer than two items, then `stackUnderflow` if the data stack is empty), the index becomes
`index + step`, and the loop ends when `loopCrossed index limit step` holds: the index crossed
the boundary between `limit - 1` and `limit` (ANS Forth's rule, see `Forth.LoopProps`).

`LEAVE` (`Block.leave`) removes the loop parameters (`returnUnderflow` if there are fewer than
two return-data items) and ends the innermost enclosing loop at once: its result `Res.leave st`
propagates out of `IF` and `BEGIN … UNTIL` like `EXIT`, and the loop continues with the code
after `LOOP`/`+LOOP` from `st`. The parser only accepts `LEAVE` inside a loop of its own block;
elsewhere it is still defined: it ends a called word like `EXIT` (`Res.returned`), and the main
block like falling off its end. `?DO` needs no rule: it is parsed to an `IF` around `DO`.

`BEGIN cond WHILE body REPEAT` (`Block.whileL`) runs `cond`, which leaves a flag (`stackUnderflow`
if the data stack is then empty). A false flag ends the loop; a true one runs `body` and starts
again with `cond`. `EXIT`, `LEAVE` and traps in `cond` or `body` end it like any other block.
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
  | tor | fromr | rfetch | loopI | loopJ | unloop
  | twoDup | twoDrop | twoSwap | divMod | negate | abs | min | max
  deriving DecidableEq, Repr

/-- A Forth state: the data stack, memory, and the return-data stack (`>R`/`R>`/`R@` and the
`DO … LOOP` parameters; the IR's auxiliary stack `astack`). Call frames are not on it. -/
structure FState (n : Nat) where
  stack  : List (Word n)
  mem    : Memory n
  rstack : List (Word n)


namespace Op

def sem {n : Nat} : Op → FState n → Except Trap (FState n)
  | .lit z, st => .ok { st with stack := BitVec.ofInt n z :: st.stack }
  | .dup, ⟨a :: d, m, r⟩ => .ok ⟨a :: a :: d, m, r⟩
  | .drop, ⟨_ :: d, m, r⟩ => .ok ⟨d, m, r⟩
  | .swap, ⟨b :: a :: d, m, r⟩ => .ok ⟨a :: b :: d, m, r⟩
  | .over, ⟨b :: a :: d, m, r⟩ => .ok ⟨a :: b :: a :: d, m, r⟩
  | .rot, ⟨c :: b :: a :: d, m, r⟩ => .ok ⟨a :: c :: b :: d, m, r⟩
  | .add, ⟨b :: a :: d, m, r⟩ => .ok ⟨(a + b) :: d, m, r⟩
  | .sub, ⟨b :: a :: d, m, r⟩ => .ok ⟨(a - b) :: d, m, r⟩
  | .mul, ⟨b :: a :: d, m, r⟩ => .ok ⟨(a * b) :: d, m, r⟩
  | .div, ⟨b :: a :: d, m, r⟩ =>
      if b = 0#n then .error .divideByZero else .ok ⟨a.sdiv b :: d, m, r⟩
  | .mod, ⟨b :: a :: d, m, r⟩ =>
      if b = 0#n then .error .divideByZero else .ok ⟨(a - a.sdiv b * b) :: d, m, r⟩
  | .and, ⟨b :: a :: d, m, r⟩ => .ok ⟨(a &&& b) :: d, m, r⟩
  | .or, ⟨b :: a :: d, m, r⟩ => .ok ⟨(a ||| b) :: d, m, r⟩
  | .xor, ⟨b :: a :: d, m, r⟩ => .ok ⟨(a ^^^ b) :: d, m, r⟩
  | .invert, ⟨a :: d, m, r⟩ => .ok ⟨(~~~a) :: d, m, r⟩
  | .lshift, ⟨u :: x :: d, m, r⟩ => .ok ⟨Word.shl x u :: d, m, r⟩
  | .rshift, ⟨u :: x :: d, m, r⟩ => .ok ⟨Word.shr x u :: d, m, r⟩
  | .eq, ⟨b :: a :: d, m, r⟩ => .ok ⟨flag (Cond.eval .eq a b) :: d, m, r⟩
  | .ne, ⟨b :: a :: d, m, r⟩ => .ok ⟨flag (Cond.eval .ne a b) :: d, m, r⟩
  | .lt, ⟨b :: a :: d, m, r⟩ => .ok ⟨flag (Cond.eval .slt a b) :: d, m, r⟩
  | .gt, ⟨b :: a :: d, m, r⟩ => .ok ⟨flag (Cond.eval .sgt a b) :: d, m, r⟩
  | .ult, ⟨b :: a :: d, m, r⟩ => .ok ⟨flag (Cond.eval .ult a b) :: d, m, r⟩
  | .ugt, ⟨b :: a :: d, m, r⟩ => .ok ⟨flag (Cond.eval .ugt a b) :: d, m, r⟩
  | .zeq, ⟨a :: d, m, r⟩ => .ok ⟨flag (Cond.eval .eq a 0#n) :: d, m, r⟩
  | .fetch, ⟨a :: d, m, r⟩ =>
      match m.read? a with
      | some v => .ok ⟨v :: d, m, r⟩
      | none => .error .badAddress
  | .store, ⟨a :: v :: d, m, r⟩ =>
      match m.write? a v with
      | some m' => .ok ⟨d, m', r⟩
      | none => .error .badAddress
  | .twoDup, ⟨b :: a :: d, m, r⟩ => .ok ⟨b :: a :: b :: a :: d, m, r⟩
  | .twoDrop, ⟨_ :: _ :: d, m, r⟩ => .ok ⟨d, m, r⟩
  | .twoSwap, ⟨x4 :: x3 :: x2 :: x1 :: d, m, r⟩ => .ok ⟨x2 :: x1 :: x4 :: x3 :: d, m, r⟩
  | .divMod, ⟨b :: a :: d, m, r⟩ =>
      if b = 0#n then .error .divideByZero else .ok ⟨a.sdiv b :: (a - a.sdiv b * b) :: d, m, r⟩
  | .negate, ⟨a :: d, m, r⟩ => .ok ⟨(0#n - a) :: d, m, r⟩
  | .abs, ⟨a :: d, m, r⟩ => .ok ⟨(if Cond.eval .slt a 0#n then 0#n - a else a) :: d, m, r⟩
  | .min, ⟨b :: a :: d, m, r⟩ => .ok ⟨(if Cond.eval .slt a b then a else b) :: d, m, r⟩
  | .max, ⟨b :: a :: d, m, r⟩ => .ok ⟨(if Cond.eval .sgt a b then a else b) :: d, m, r⟩
  | .tor, ⟨a :: d, m, r⟩ => .ok ⟨d, m, a :: r⟩
  | .fromr, ⟨d, m, a :: r⟩ => .ok ⟨a :: d, m, r⟩
  | .fromr, ⟨_, _, []⟩ => .error .returnUnderflow
  | .rfetch, ⟨d, m, a :: r⟩ => .ok ⟨a :: d, m, a :: r⟩
  | .rfetch, ⟨_, _, []⟩ => .error .returnUnderflow
  | .loopI, ⟨d, m, a :: r⟩ => .ok ⟨a :: d, m, a :: r⟩
  | .loopI, ⟨_, _, []⟩ => .error .returnUnderflow
  | .loopJ, ⟨d, m, a :: b :: c :: r⟩ => .ok ⟨c :: d, m, a :: b :: c :: r⟩
  | .loopJ, _ => .error .returnUnderflow
  | .unloop, ⟨d, m, _ :: _ :: r⟩ => .ok ⟨d, m, r⟩
  | .unloop, _ => .error .returnUnderflow
  | _, _ => .error .stackUnderflow

end Op

/-- A Forth block. `ite t e rest` is `IF t ELSE e THEN rest`; `untilL body rest` is
`BEGIN body UNTIL rest`; `call i rest` executes the colon definition with index `i` in the
dictionary, then `rest`; `exit rest` is `EXIT`, which leaves the current word (`rest` is dead
code, kept so that a block records its source text); `doLoop body rest` is
`DO body LOOP rest`; `plusLoop body rest` is `DO body +LOOP rest`; `leave rest` is `LEAVE`
(`rest` is dead code too); `whileL cond body rest` is `BEGIN cond WHILE body REPEAT rest`. -/
inductive Block where
  | nil
  | op (o : Op) (rest : Block)
  | ite (t e rest : Block)
  | untilL (body rest : Block)
  | call (i : Nat) (rest : Block)
  | exit (rest : Block)
  | doLoop (body rest : Block)
  | plusLoop (body rest : Block)
  | leave (rest : Block)
  | whileL (cond body rest : Block)
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

/-- How a run of a block ends: it fell off the end (`ok`), it executed `EXIT` (`exit`), it
executed `LEAVE` (`leave`, with the loop parameters already removed), or it trapped (`error`). -/
inductive Res (n : Nat) where
  | ok (st : FState n)
  | exit (st : FState n)
  | leave (st : FState n)
  | error (t : Trap)

namespace Res

def isOk {n : Nat} : Res n → Bool
  | .ok _ => true
  | _ => false

/-- `EXIT` or a trap: the results a loop does not catch (it catches `LEAVE`). -/
def isStop {n : Nat} : Res n → Bool
  | .exit _ => true
  | .error _ => true
  | _ => false

/-- The state a called word returns with: after falling off its end, after `EXIT`, or after a
`LEAVE` outside any loop of the word. -/
def returned {n : Nat} : Res n → Option (FState n)
  | .ok st => some st
  | .exit st => some st
  | .leave st => some st
  | .error _ => none

end Res

/-- The `+LOOP` exit test, on the index `i`, limit `l` and step `k`: with `o = i - l`, the sign of
`((k + o) xor o) and (o xor k)`, i.e. `o + k` and `o` differ in sign while `o` and `k` differ in
sign too. This is the signed overflow of `(o - 2^(n-1)) + k`, i.e. ANS Forth's rule that the loop
ends when the index crosses the boundary between `l - 1` and `l`
(`Forth.loopCrossed_eq_saddOverflow`); with step `1` it is `i + 1 = l`, the `LOOP` test
(`Forth.loopCrossed_one`). -/
def loopCrossed {n : Nat} (i l k : Word n) : Bool :=
  Cond.eval .slt (((k + (i - l)) ^^^ (i - l)) &&& ((i - l) ^^^ k)) 0#n

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
  | iteUnder {t e rest m rs} :
      Run defs (.ite t e rest) ⟨[], m, rs⟩ (.error .stackUnderflow)
  | iteTrue {t e rest c d m rs st1 r} :
      Word.isTrue c = true → Run defs t ⟨d, m, rs⟩ (.ok st1) → Run defs rest st1 r →
      Run defs (.ite t e rest) ⟨c :: d, m, rs⟩ r
  | iteTrueStop {t e rest c d m rs r} :
      Word.isTrue c = true → Run defs t ⟨d, m, rs⟩ r → r.isOk = false →
      Run defs (.ite t e rest) ⟨c :: d, m, rs⟩ r
  | iteFalse {t e rest c d m rs st1 r} :
      Word.isTrue c = false → Run defs e ⟨d, m, rs⟩ (.ok st1) → Run defs rest st1 r →
      Run defs (.ite t e rest) ⟨c :: d, m, rs⟩ r
  | iteFalseStop {t e rest c d m rs r} :
      Word.isTrue c = false → Run defs e ⟨d, m, rs⟩ r → r.isOk = false →
      Run defs (.ite t e rest) ⟨c :: d, m, rs⟩ r
  | untilBodyStop {body rest st r} :
      Run defs body st r → r.isOk = false → Run defs (.untilL body rest) st r
  | untilUnder {body rest st m rs} :
      Run defs body st (.ok ⟨[], m, rs⟩) → Run defs (.untilL body rest) st (.error .stackUnderflow)
  | untilDone {body rest st c d m rs r} :
      Run defs body st (.ok ⟨c :: d, m, rs⟩) → Word.isTrue c = true → Run defs rest ⟨d, m, rs⟩ r →
      Run defs (.untilL body rest) st r
  | untilAgain {body rest st c d m rs r} :
      Run defs body st (.ok ⟨c :: d, m, rs⟩) → Word.isTrue c = false →
      Run defs (.untilL body rest) ⟨d, m, rs⟩ r → Run defs (.untilL body rest) st r
  | whileCondStop {cond body rest st r} :
      Run defs cond st r → r.isOk = false → Run defs (.whileL cond body rest) st r
  | whileUnder {cond body rest st m rs} :
      Run defs cond st (.ok ⟨[], m, rs⟩) →
      Run defs (.whileL cond body rest) st (.error .stackUnderflow)
  | whileExit {cond body rest st c d m rs r} :
      Run defs cond st (.ok ⟨c :: d, m, rs⟩) → Word.isTrue c = false →
      Run defs rest ⟨d, m, rs⟩ r → Run defs (.whileL cond body rest) st r
  | whileBodyStop {cond body rest st c d m rs r} :
      Run defs cond st (.ok ⟨c :: d, m, rs⟩) → Word.isTrue c = true →
      Run defs body ⟨d, m, rs⟩ r → r.isOk = false → Run defs (.whileL cond body rest) st r
  | whileAgain {cond body rest st c d m rs st2 r} :
      Run defs cond st (.ok ⟨c :: d, m, rs⟩) → Word.isTrue c = true →
      Run defs body ⟨d, m, rs⟩ (.ok st2) → Run defs (.whileL cond body rest) st2 r →
      Run defs (.whileL cond body rest) st r
  | callOk {i rest st body r1 st1 r} :
      defs[i]? = some body → Run defs body st r1 → r1.returned = some st1 →
      Run defs rest st1 r → Run defs (.call i rest) st r
  | callErr {i rest st body x} :
      defs[i]? = some body → Run defs body st (.error x) → Run defs (.call i rest) st (.error x)
  | callUndef {i rest st} :
      defs[i]? = none → Run defs (.call i rest) st (.error .badPc)
  | leaveOk {rest d m a b rs} :
      Run defs (.leave rest) ⟨d, m, a :: b :: rs⟩ (.leave ⟨d, m, rs⟩)
  | leaveUnder {rest st} :
      st.rstack.length < 2 → Run defs (.leave rest) st (.error .returnUnderflow)
  | doUnder {body rest st} :
      st.stack.length < 2 → Run defs (.doLoop body rest) st (.error .stackUnderflow)
  | doBodyStop {body rest i l d m rs r} :
      Run defs body ⟨d, m, i :: l :: rs⟩ r → r.isStop = true →
      Run defs (.doLoop body rest) ⟨i :: l :: d, m, rs⟩ r
  | doLeave {body rest i l d m rs st1 r} :
      Run defs body ⟨d, m, i :: l :: rs⟩ (.leave st1) → Run defs rest st1 r →
      Run defs (.doLoop body rest) ⟨i :: l :: d, m, rs⟩ r
  | doTestUnder {body rest i l d m rs st1} :
      Run defs body ⟨d, m, i :: l :: rs⟩ (.ok st1) → st1.rstack.length < 2 →
      Run defs (.doLoop body rest) ⟨i :: l :: d, m, rs⟩ (.error .returnUnderflow)
  | doDone {body rest i l d m rs i1 l1 d1 m1 rs1 r} :
      Run defs body ⟨d, m, i :: l :: rs⟩ (.ok ⟨d1, m1, i1 :: l1 :: rs1⟩) → i1 + 1#n = l1 →
      Run defs rest ⟨d1, m1, rs1⟩ r → Run defs (.doLoop body rest) ⟨i :: l :: d, m, rs⟩ r
  | doAgain {body rest i l d m rs i1 l1 d1 m1 rs1 r} :
      Run defs body ⟨d, m, i :: l :: rs⟩ (.ok ⟨d1, m1, i1 :: l1 :: rs1⟩) → i1 + 1#n ≠ l1 →
      Run defs (.doLoop body rest) ⟨(i1 + 1#n) :: l1 :: d1, m1, rs1⟩ r →
      Run defs (.doLoop body rest) ⟨i :: l :: d, m, rs⟩ r
  | plusUnder {body rest st} :
      st.stack.length < 2 → Run defs (.plusLoop body rest) st (.error .stackUnderflow)
  | plusBodyStop {body rest i l d m rs r} :
      Run defs body ⟨d, m, i :: l :: rs⟩ r → r.isStop = true →
      Run defs (.plusLoop body rest) ⟨i :: l :: d, m, rs⟩ r
  | plusLeave {body rest i l d m rs st1 r} :
      Run defs body ⟨d, m, i :: l :: rs⟩ (.leave st1) → Run defs rest st1 r →
      Run defs (.plusLoop body rest) ⟨i :: l :: d, m, rs⟩ r
  | plusTestUnder {body rest i l d m rs st1} :
      Run defs body ⟨d, m, i :: l :: rs⟩ (.ok st1) → st1.rstack.length < 2 →
      Run defs (.plusLoop body rest) ⟨i :: l :: d, m, rs⟩ (.error .returnUnderflow)
  | plusStepUnder {body rest i l d m rs i1 l1 m1 rs1} :
      Run defs body ⟨d, m, i :: l :: rs⟩ (.ok ⟨[], m1, i1 :: l1 :: rs1⟩) →
      Run defs (.plusLoop body rest) ⟨i :: l :: d, m, rs⟩ (.error .stackUnderflow)
  | plusDone {body rest i l d m rs i1 l1 k d1 m1 rs1 r} :
      Run defs body ⟨d, m, i :: l :: rs⟩ (.ok ⟨k :: d1, m1, i1 :: l1 :: rs1⟩) →
      loopCrossed i1 l1 k = true →
      Run defs rest ⟨d1, m1, rs1⟩ r → Run defs (.plusLoop body rest) ⟨i :: l :: d, m, rs⟩ r
  | plusAgain {body rest i l d m rs i1 l1 k d1 m1 rs1 r} :
      Run defs body ⟨d, m, i :: l :: rs⟩ (.ok ⟨k :: d1, m1, i1 :: l1 :: rs1⟩) →
      loopCrossed i1 l1 k = false →
      Run defs (.plusLoop body rest) ⟨(i1 + k) :: l1 :: d1, m1, rs1⟩ r →
      Run defs (.plusLoop body rest) ⟨i :: l :: d, m, rs⟩ r

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
  | whileCondStop hc hk ihc =>
    cases h₂ with
    | whileCondStop hc' => exact ihc hc'
    | whileUnder hc' => have := ihc hc'; subst this; cases hk
    | whileExit hc' => have := ihc hc'; subst this; cases hk
    | whileBodyStop hc' => have := ihc hc'; subst this; cases hk
    | whileAgain hc' => have := ihc hc'; subst this; cases hk
  | whileUnder hc ihc =>
    cases h₂ with
    | whileCondStop hc' hk => have := ihc hc'; subst this; cases hk
    | whileUnder => rfl
    | whileExit hc' => have := ihc hc'; cases this
    | whileBodyStop hc' => have := ihc hc'; cases this
    | whileAgain hc' => have := ihc hc'; cases this
  | whileExit hc hf hr ihc ihr =>
    cases h₂ with
    | whileCondStop hc' hk => have := ihc hc'; subst this; cases hk
    | whileUnder hc' => have := ihc hc'; cases this
    | whileExit hc' _ hr' => have := ihc hc'; cases this; exact ihr hr'
    | whileBodyStop hc' ht => have := ihc hc'; cases this; rw [hf] at ht; cases ht
    | whileAgain hc' ht => have := ihc hc'; cases this; rw [hf] at ht; cases ht
  | whileBodyStop hc ht hb hk ihc ihb =>
    cases h₂ with
    | whileCondStop hc' hk' => have := ihc hc'; subst this; cases hk'
    | whileUnder hc' => have := ihc hc'; cases this
    | whileExit hc' hf => have := ihc hc'; cases this; rw [ht] at hf; cases hf
    | whileBodyStop hc' _ hb' => have := ihc hc'; cases this; exact ihb hb'
    | whileAgain hc' _ hb' => have := ihc hc'; cases this; have := ihb hb'; subst this; cases hk
  | whileAgain hc ht hb hl ihc ihb ihl =>
    cases h₂ with
    | whileCondStop hc' hk' => have := ihc hc'; subst this; cases hk'
    | whileUnder hc' => have := ihc hc'; cases this
    | whileExit hc' hf => have := ihc hc'; cases this; rw [ht] at hf; cases hf
    | whileBodyStop hc' _ hb' hk => have := ihc hc'; cases this; have := ihb hb'; subst this; cases hk
    | whileAgain hc' _ hb' hl' => have := ihc hc'; cases this; have := ihb hb'; cases this; exact ihl hl'
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
  | leaveOk => cases h₂ with
    | leaveOk => rfl
    | leaveUnder hl => (simp at hl; try omega)
  | leaveUnder hl => cases h₂ with
    | leaveOk => (simp at hl; try omega)
    | leaveUnder => rfl
  | doUnder hl =>
    cases h₂ with
    | doUnder => rfl
    | _ => (simp at hl; try omega)
  | doBodyStop hb hk ihb =>
    cases h₂ with
    | doUnder hl => (simp at hl; try omega)
    | doBodyStop hb' => exact ihb hb'
    | doLeave hb' => have := ihb hb'; subst this; cases hk
    | doTestUnder hb' => have := ihb hb'; subst this; cases hk
    | doDone hb' => have := ihb hb'; subst this; cases hk
    | doAgain hb' => have := ihb hb'; subst this; cases hk
  | doLeave hb hr ihb ihr =>
    cases h₂ with
    | doUnder hl => (simp at hl; try omega)
    | doBodyStop hb' hk => have := ihb hb'; subst this; cases hk
    | doLeave hb' hr' => have := ihb hb'; cases this; exact ihr hr'
    | doTestUnder hb' => have := ihb hb'; cases this
    | doDone hb' => have := ihb hb'; cases this
    | doAgain hb' => have := ihb hb'; cases this
  | doTestUnder hb hl ihb =>
    cases h₂ with
    | doUnder hl' => (simp at hl'; try omega)
    | doBodyStop hb' hk => have := ihb hb'; subst this; cases hk
    | doLeave hb' => have := ihb hb'; cases this
    | doTestUnder => rfl
    | doDone hb' => have := ihb hb'; cases this; (simp at hl; try omega)
    | doAgain hb' => have := ihb hb'; cases this; (simp at hl; try omega)
  | doDone hb he hr ihb ihr =>
    cases h₂ with
    | doUnder hl => (simp at hl; try omega)
    | doBodyStop hb' hk => have := ihb hb'; subst this; cases hk
    | doLeave hb' => have := ihb hb'; cases this
    | doTestUnder hb' hl => have := ihb hb'; cases this; (simp at hl; try omega)
    | doDone hb' _ hr' => have := ihb hb'; cases this; exact ihr hr'
    | doAgain hb' hne _ => have := ihb hb'; cases this; exact absurd he hne
  | doAgain hb hne hl ihb ihl =>
    cases h₂ with
    | doUnder hl' => (simp at hl'; try omega)
    | doBodyStop hb' hk => have := ihb hb'; subst this; cases hk
    | doLeave hb' => have := ihb hb'; cases this
    | doTestUnder hb' hl' => have := ihb hb'; cases this; (simp at hl'; try omega)
    | doDone hb' he _ => have := ihb hb'; cases this; exact absurd he hne
    | doAgain hb' _ hl' => have := ihb hb'; cases this; exact ihl hl'
  | plusUnder hl =>
    cases h₂ with
    | plusUnder => rfl
    | _ => (simp at hl; try omega)
  | plusBodyStop hb hk ihb =>
    cases h₂ with
    | plusUnder hl => (simp at hl; try omega)
    | plusBodyStop hb' => exact ihb hb'
    | plusLeave hb' => have := ihb hb'; subst this; cases hk
    | plusTestUnder hb' => have := ihb hb'; subst this; cases hk
    | plusStepUnder hb' => have := ihb hb'; subst this; cases hk
    | plusDone hb' => have := ihb hb'; subst this; cases hk
    | plusAgain hb' => have := ihb hb'; subst this; cases hk
  | plusLeave hb hr ihb ihr =>
    cases h₂ with
    | plusUnder hl => (simp at hl; try omega)
    | plusBodyStop hb' hk => have := ihb hb'; subst this; cases hk
    | plusLeave hb' hr' => have := ihb hb'; cases this; exact ihr hr'
    | plusTestUnder hb' => have := ihb hb'; cases this
    | plusStepUnder hb' => have := ihb hb'; cases this
    | plusDone hb' => have := ihb hb'; cases this
    | plusAgain hb' => have := ihb hb'; cases this
  | plusTestUnder hb hl ihb =>
    cases h₂ with
    | plusUnder hl' => (simp at hl'; try omega)
    | plusBodyStop hb' hk => have := ihb hb'; subst this; cases hk
    | plusLeave hb' => have := ihb hb'; cases this
    | plusTestUnder => rfl
    | plusStepUnder hb' => have := ihb hb'; cases this; (simp at hl; try omega)
    | plusDone hb' => have := ihb hb'; cases this; (simp at hl; try omega)
    | plusAgain hb' => have := ihb hb'; cases this; (simp at hl; try omega)
  | plusStepUnder hb ihb =>
    cases h₂ with
    | plusUnder hl' => (simp at hl'; try omega)
    | plusBodyStop hb' hk => have := ihb hb'; subst this; cases hk
    | plusLeave hb' => have := ihb hb'; cases this
    | plusTestUnder hb' hl => have := ihb hb'; cases this; (simp at hl; try omega)
    | plusStepUnder => rfl
    | plusDone hb' => have := ihb hb'; cases this
    | plusAgain hb' => have := ihb hb'; cases this
  | plusDone hb he hr ihb ihr =>
    cases h₂ with
    | plusUnder hl => (simp at hl; try omega)
    | plusBodyStop hb' hk => have := ihb hb'; subst this; cases hk
    | plusLeave hb' => have := ihb hb'; cases this
    | plusTestUnder hb' hl => have := ihb hb'; cases this; (simp at hl; try omega)
    | plusStepUnder hb' => have := ihb hb'; cases this
    | plusDone hb' _ hr' => have := ihb hb'; cases this; exact ihr hr'
    | plusAgain hb' hne _ => have := ihb hb'; cases this; rw [he] at hne; cases hne
  | plusAgain hb hne hl ihb ihl =>
    cases h₂ with
    | plusUnder hl' => (simp at hl'; try omega)
    | plusBodyStop hb' hk => have := ihb hb'; subst this; cases hk
    | plusLeave hb' => have := ihb hb'; cases this
    | plusTestUnder hb' hl' => have := ihb hb'; cases this; (simp at hl'; try omega)
    | plusStepUnder hb' => have := ihb hb'; cases this
    | plusDone hb' he _ => have := ihb hb'; cases this; rw [he] at hne; cases hne
    | plusAgain hb' _ hl' => have := ihb hb'; cases this; exact ihl hl'

end Forth
end WordDialect
