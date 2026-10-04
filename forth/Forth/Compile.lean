import Forth.Semantics
import WordIR

/-!
# Forth.Compile

Lowering of Forth to Universal Word IR. Forth's data stack *is* the IR data stack, so the
stack words map one-to-one; only comparisons need more than one instruction, because Forth
true is `-1` while `CMP` yields `1`.

Colon definitions become IR subroutines. Program layout:

```
0:                 main block
size main:         HALT
wordAddr … 0:      body of word 0, RET
wordAddr … 1:      body of word 1, RET
…
```

A call of word `i` lowers to `CALL (wordAddr … i)`; `EXIT` lowers to `RET`, the same
instruction that ends a word body, so a word returns identically whether it falls off its end
or exits early. `MOD` lowers to `OVER OVER SDIV MUL SUB` and `0=` to `0 =`.
Variables need no code: they are literals (their cell addresses). Code sizes do not depend on the call
targets (`compile_size`), so the addresses are prefix sums of `Block.size`.

The return-data stack is the IR's auxiliary stack: `>R`, `R>`, `R@` and `I` lower to `TOR`,
`FROMR`, `RFETCH`, `RFETCH`, and `J` to `FROMR FROMR RFETCH SWAP TOR SWAP TOR`.
`DO body LOOP` lowers to

```
L:  SWAP TOR TOR                              ( limit index -- )   R: ( -- limit index )
    body
    FROMR 1 ADD FROMR SWAP OVER OVER SUB      ( -- index+1 limit limit-(index+1) )
    BRANCH L                                  nonzero: go around again (re-entering at L)
    DROP DROP
```

(`Frag.repeatLoop`). The test leaves `limit - (index + 1)`, which is nonzero exactly when the
loop must go around again, so no comparison flag is needed (a `CMP` flag would be `1`, which is
`0` when `n = 0`). Going around again re-enters at `L` with the parameters `index+1 limit` back
on the data stack, which is the `Run.doAgain` rule.
-/

namespace WordDialect
namespace Forth

open IR


def compileOp {n : Nat} : Op → List (Instr n)
  | .lit z => [.word (BitVec.ofInt n z)]
  | .dup => [.dup]
  | .drop => [.drop]
  | .swap => [.swap]
  | .over => [.over]
  | .rot => [.rot]
  | .add => [.add]
  | .sub => [.sub]
  | .mul => [.mul]
  | .div => [.sdiv]
  | .mod => [.over, .over, .sdiv, .mul, .sub]
  | .and => [.and]
  | .or => [.or]
  | .xor => [.xor]
  | .invert => [.not]
  | .lshift => [.shl]
  | .rshift => [.shr]
  | .eq => cmpFlagCode .eq
  | .ne => cmpFlagCode .ne
  | .lt => cmpFlagCode .slt
  | .gt => cmpFlagCode .sgt
  | .ult => cmpFlagCode .ult
  | .ugt => cmpFlagCode .ugt
  | .zeq => .word 0#n :: cmpFlagCode .eq
  | .fetch => [.load]
  | .store => [.store]
  | .tor => [.tor]
  | .fromr => [.fromr]
  | .rfetch => [.rfetch]
  | .loopI => [.rfetch]
  | .loopJ => [.fromr, .fromr, .rfetch, .swap, .tor, .swap, .tor]

/-- Number of IR instructions an operation lowers to. -/
def Op.len : Op → Nat
  | .eq | .ne | .lt | .gt | .ult | .ugt => 4
  | .mod | .zeq => 5
  | .loopJ => 7
  | _ => 1

theorem compileOp_length {n : Nat} (o : Op) : (compileOp o : List (Instr n)).length = o.len := by
  cases o <;> rfl

/-- `DO`: move `limit start` from the data stack to the auxiliary stack (index on top). -/
def loopEnter {n : Nat} : List (Instr n) := [.swap, .tor, .tor]

/-- After the body: increment the index and leave `index+1 limit (limit - (index+1))`. -/
def loopTest {n : Nat} : List (Instr n) :=
  [.fromr, .word 1#n, .add, .fromr, .swap, .over, .over, .sub]

/-- After the loop: drop `index+1 limit`. -/
def loopLeave {n : Nat} : List (Instr n) := [.drop, .drop]

/-- Number of IR instructions a block lowers to (independent of call targets). -/
def Block.size : Block → Nat
  | .nil => 0
  | .op o rest => o.len + rest.size
  | .ite t e rest => (e.size + t.size + 2) + rest.size
  | .untilL body rest => (body.size + 2) + rest.size
  | .call _ rest => 1 + rest.size
  | .exit rest => 1 + rest.size
  | .doLoop body rest => ((3 + (body.size + 8)) + 1) + (2 + rest.size)

/-- Lower a block; `addr i` is the code address of word `i`. -/
def compile {n : Nat} (addr : Nat → Nat) : Block → Frag n
  | .nil => Frag.empty
  | .op o rest => (Frag.ofCode (compileOp o)).seq (compile addr rest)
  | .ite t e rest => (Frag.ite (compile addr t) (compile addr e)).seq (compile addr rest)
  | .untilL body rest => (Frag.untilLoop (compile addr body)).seq (compile addr rest)
  | .call i rest => (Frag.ofCode [.call (addr i)]).seq (compile addr rest)
  | .exit rest => (Frag.ofCode [.ret]).seq (compile addr rest)
  | .doLoop body rest =>
    (Frag.repeatLoop ((Frag.ofCode loopEnter).seq ((compile addr body).seq (Frag.ofCode loopTest)))).seq
      ((Frag.ofCode loopLeave).seq (compile addr rest))

theorem compile_size {n : Nat} (addr : Nat → Nat) (b : Block) :
    (compile addr b : Frag n).size = b.size := by
  induction b with
  | nil => rfl
  | op o rest ih =>
    simp only [compile, Frag.seq_size, Frag.ofCode_size, compileOp_length, ih, Block.size]
  | ite t e rest iht ihe ihr =>
    simp only [compile, Frag.seq_size, Frag.ite_size, iht, ihe, ihr, Block.size]
  | untilL body rest ihb ihr =>
    simp only [compile, Frag.seq_size, Frag.until_size, ihb, ihr, Block.size]
  | call i rest ih =>
    simp only [compile, Frag.seq_size, Frag.ofCode_size, ih, Block.size, List.length_singleton]
  | exit rest ih =>
    simp only [compile, Frag.seq_size, Frag.ofCode_size, ih, Block.size, List.length_singleton]
  | doLoop body rest ihb ihr =>
    simp only [compile, Frag.seq_size, Frag.repeat_size, Frag.ofCode_size, ihb, ihr, Block.size]
    rfl

/-- Address of word `i` when the dictionary `defs` is laid out from `base`, each body followed
by `RET`. For `i ≥ defs.length` this is the address just past the last body. -/
def wordAddr : Nat → List Block → Nat → Nat
  | base, [], _ => base
  | base, _ :: _, 0 => base
  | base, b :: bs, i + 1 => wordAddr (base + b.size + 1) bs i

/-- The dictionary's code, laid out from `base`: each body followed by `RET`. -/
def emitDefs {n : Nat} (addr : Nat → Nat) : Nat → List Block → List (Instr n)
  | _, [] => []
  | base, b :: bs => (compile addr b : Frag n).emit base ++ [.ret] ++ emitDefs addr (base + b.size + 1) bs

/-- Code addresses of the words of program `P`. -/
def Program.addr (P : Program) : Nat → Nat := wordAddr (P.main.size + 1) P.defs

/-- A complete program: the main block at address 0, then `HALT`, then the definitions. -/
def Program.compile {n : Nat} (P : Program) : Prog n :=
  (Forth.compile P.addr P.main : Frag n).emit 0 ++ [.halt] ++ emitDefs P.addr (P.main.size + 1) P.defs

/-- A program with no definitions: the block at address 0, followed by `HALT`. -/
def compileProgram {n : Nat} (b : Block) : Prog n := Program.compile { defs := [], main := b }

end Forth
end WordDialect
