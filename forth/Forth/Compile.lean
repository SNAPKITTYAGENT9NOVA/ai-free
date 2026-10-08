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
targets or on the leave target (`compile_size`), so the addresses are prefix sums of `Block.size`.

The return-data stack is the IR's auxiliary stack: `>R`, `R>`, `R@` and `I` lower to `TOR`,
`FROMR`, `RFETCH`, `RFETCH`, `J` to `FROMR FROMR RFETCH SWAP TOR SWAP TOR`, and `UNLOOP` to
`FROMR FROMR DROP DROP`. `DO body LOOP` lowers to

```
L:  SWAP TOR TOR                              ( limit index -- )   R: ( -- limit index )
    body
    FROMR 1 ADD FROMR SWAP OVER OVER SUB      ( -- index+1 limit limit-(index+1) )
    BRANCH L                                  nonzero: go around again (re-entering at L)
    DROP DROP
E:
```

The test leaves `limit - (index + 1)`, which is nonzero exactly when the loop must go around
again, so no comparison flag is needed (a `CMP` flag would be `1`, which is `0` when `n = 0`).
Going around again re-enters at `L` with the parameters `index+1 limit` back on the data stack,
which is the `Run.doAgain` rule. `DO body +LOOP` lowers to

```
L:  SWAP TOR TOR
    body                                      ( -- step )
    plusTest                                  ( step -- index+step limit crossed )
    BRANCH X                                  crossed: leave the loop
    JMP L
X:  DROP DROP
E:
```

where `plusTest` (`FROMR FROMR`, then 24 stack instructions) computes `index + step` and the
`CMP SLT` flag of `loopCrossed`. Here the flag says when to *stop*, so it is a forward branch:
at `n = 0` the flag is `0` and `loopCrossed` is `false`, and both agree.

`LEAVE` lowers to `FROMR FROMR DROP DROP JMP E`, where `E` (the *leave target*) is the address
just past the innermost enclosing loop. `compile addr lv b` builds `b` with leave target `lv`;
a loop builds its body with its own end address. Outside any loop (which the parser rejects)
the target is the `RET` after a word body, or the `HALT` after the main block.
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
  | .unloop => [.fromr, .fromr, .drop, .drop]

/-- Number of IR instructions an operation lowers to. -/
def Op.len : Op → Nat
  | .eq | .ne | .lt | .gt | .ult | .ugt => 4
  | .mod | .zeq => 5
  | .loopJ => 7
  | .unloop => 4
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

/-- After a `+LOOP` body: from `step` on the data stack and `index limit` on the auxiliary
stack, leave `index+step limit flag`, the flag being `Word.ofBool (loopCrossed index limit step)`.
With `o = index - limit` it computes `k + o`, `((k + o) xor o) and (o xor k)`, its sign by
`CMP SLT 0`, and `limit + (k + o) = index + step`. -/
def plusTest {n : Nat} : List (Instr n) :=
  [.fromr, .fromr, .swap, .over, .sub, .rot, .over, .over, .xor, .rot, .rot, .over, .add, .dup,
    .rot, .xor, .rot, .and, .word 0#n, .cmp .slt, .swap, .rot, .dup, .rot, .add, .rot]

/-- Number of IR instructions a block lowers to (independent of call and leave targets). -/
def Block.size : Block → Nat
  | .nil => 0
  | .op o rest => o.len + rest.size
  | .ite t e rest => (e.size + t.size + 2) + rest.size
  | .untilL body rest => (body.size + 2) + rest.size
  | .call _ rest => 1 + rest.size
  | .exit rest => 1 + rest.size
  | .doLoop body rest => (body.size + 14) + rest.size
  | .plusLoop body rest => (body.size + 33) + rest.size
  | .leave rest => 5 + rest.size

/-- The code of `DO … LOOP` (without what follows), its body built by `mk` for the leave
target, which is the end of this code. -/
def loopFrag {n : Nat} (S : Nat) (mk : Nat → Frag n) (hmk : ∀ a, (mk a).size = S) : Frag n where
  size := S + 14
  emit := fun b => loopEnter ++ (mk (b + S + 14)).emit (b + 3) ++ loopTest ++ [.branch b] ++ loopLeave
  len := fun b => by simp [Frag.len, hmk, loopEnter, loopTest, loopLeave]

/-- The code of `DO … +LOOP` (without what follows). -/
def plusFrag {n : Nat} (S : Nat) (mk : Nat → Frag n) (hmk : ∀ a, (mk a).size = S) : Frag n where
  size := S + 33
  emit := fun b => loopEnter ++ (mk (b + S + 33)).emit (b + 3) ++ plusTest ++
    [.branch (b + S + 31), .jmp b] ++ loopLeave
  len := fun b => by simp [Frag.len, hmk, loopEnter, plusTest, loopLeave]

/-- Lower a block, with its size; `addr i` is the code address of word `i`, `lv` the leave
target. -/
def compileS {n : Nat} (addr : Nat → Nat) : Nat → (b : Block) → { f : Frag n // f.size = b.size }
  | _, .nil => ⟨Frag.empty, rfl⟩
  | lv, .op o rest =>
    ⟨(Frag.ofCode (compileOp o)).seq (compileS addr lv rest).1, by
      simp [Frag.seq_size, Frag.ofCode_size, compileOp_length, (compileS addr lv rest).2,
        Block.size]⟩
  | lv, .ite t e rest =>
    ⟨(Frag.ite (compileS addr lv t).1 (compileS addr lv e).1).seq (compileS addr lv rest).1, by
      simp [Frag.seq_size, Frag.ite_size, (compileS addr lv t).2, (compileS addr lv e).2,
        (compileS addr lv rest).2, Block.size]⟩
  | lv, .untilL body rest =>
    ⟨(Frag.untilLoop (compileS addr lv body).1).seq (compileS addr lv rest).1, by
      simp [Frag.seq_size, Frag.until_size, (compileS addr lv body).2, (compileS addr lv rest).2,
        Block.size]⟩
  | lv, .call i rest =>
    ⟨(Frag.ofCode [.call (addr i)]).seq (compileS addr lv rest).1, by
      simp [Frag.seq_size, Frag.ofCode_size, (compileS addr lv rest).2, Block.size]⟩
  | lv, .exit rest =>
    ⟨(Frag.ofCode [.ret]).seq (compileS addr lv rest).1, by
      simp [Frag.seq_size, Frag.ofCode_size, (compileS addr lv rest).2, Block.size]⟩
  | lv, .doLoop body rest =>
    ⟨(loopFrag body.size (fun a => (compileS addr a body).1) (fun a => (compileS addr a body).2)).seq
        (compileS addr lv rest).1, by
      simp [Frag.seq_size, loopFrag, (compileS addr lv rest).2, Block.size]⟩
  | lv, .plusLoop body rest =>
    ⟨(plusFrag body.size (fun a => (compileS addr a body).1) (fun a => (compileS addr a body).2)).seq
        (compileS addr lv rest).1, by
      simp [Frag.seq_size, plusFrag, (compileS addr lv rest).2, Block.size]⟩
  | lv, .leave rest =>
    ⟨(Frag.ofCode (compileOp .unloop ++ [.jmp lv])).seq (compileS addr lv rest).1, by
      simp [Frag.seq_size, Frag.ofCode_size, compileOp, (compileS addr lv rest).2, Block.size]⟩

/-- Lower a block; `addr i` is the code address of word `i`, `lv` the leave target. -/
def compile {n : Nat} (addr : Nat → Nat) (lv : Nat) (b : Block) : Frag n := (compileS addr lv b).1

theorem compile_size {n : Nat} (addr : Nat → Nat) (lv : Nat) (b : Block) :
    (compile addr lv b : Frag n).size = b.size := (compileS addr lv b).2

section Eqns
variable {n : Nat} (addr : Nat → Nat) (lv : Nat)

theorem compile_nil : (compile addr lv .nil : Frag n) = Frag.empty := rfl
theorem compile_op (o : Op) (rest : Block) :
    (compile addr lv (.op o rest) : Frag n) =
      (Frag.ofCode (compileOp o)).seq (compile addr lv rest) := rfl
theorem compile_ite (t e rest : Block) :
    (compile addr lv (.ite t e rest) : Frag n) =
      (Frag.ite (compile addr lv t) (compile addr lv e)).seq (compile addr lv rest) := rfl
theorem compile_until (body rest : Block) :
    (compile addr lv (.untilL body rest) : Frag n) =
      (Frag.untilLoop (compile addr lv body)).seq (compile addr lv rest) := rfl
theorem compile_call (i : Nat) (rest : Block) :
    (compile addr lv (.call i rest) : Frag n) =
      (Frag.ofCode [.call (addr i)]).seq (compile addr lv rest) := rfl
theorem compile_exit (rest : Block) :
    (compile addr lv (.exit rest) : Frag n) = (Frag.ofCode [.ret]).seq (compile addr lv rest) := rfl
theorem compile_doLoop (body rest : Block) :
    (compile addr lv (.doLoop body rest) : Frag n) =
      (loopFrag body.size (fun a => compile addr a body) (fun a => compile_size addr a body)).seq
        (compile addr lv rest) := rfl
theorem compile_plusLoop (body rest : Block) :
    (compile addr lv (.plusLoop body rest) : Frag n) =
      (plusFrag body.size (fun a => compile addr a body) (fun a => compile_size addr a body)).seq
        (compile addr lv rest) := rfl
theorem compile_leave (rest : Block) :
    (compile addr lv (.leave rest) : Frag n) =
      (Frag.ofCode (compileOp .unloop ++ [.jmp lv])).seq (compile addr lv rest) := rfl

end Eqns

/-- Address of word `i` when the dictionary `defs` is laid out from `base`, each body followed
by `RET`. For `i ≥ defs.length` this is the address just past the last body. -/
def wordAddr : Nat → List Block → Nat → Nat
  | base, [], _ => base
  | base, _ :: _, 0 => base
  | base, b :: bs, i + 1 => wordAddr (base + b.size + 1) bs i

/-- The dictionary's code, laid out from `base`: each body followed by `RET` (also its leave
target). -/
def emitDefs {n : Nat} (addr : Nat → Nat) : Nat → List Block → List (Instr n)
  | _, [] => []
  | base, b :: bs =>
    (compile addr (base + b.size) b : Frag n).emit base ++ [.ret] ++ emitDefs addr (base + b.size + 1) bs

/-- Code addresses of the words of program `P`. -/
def Program.addr (P : Program) : Nat → Nat := wordAddr (P.main.size + 1) P.defs

/-- A complete program: the main block at address 0, then `HALT` (the main block's leave
target), then the definitions. -/
def Program.compile {n : Nat} (P : Program) : Prog n :=
  (Forth.compile P.addr P.main.size P.main : Frag n).emit 0 ++ [.halt] ++ emitDefs P.addr (P.main.size + 1) P.defs

/-- A program with no definitions: the block at address 0, followed by `HALT`. -/
def compileProgram {n : Nat} (b : Block) : Prog n := Program.compile { defs := [], main := b }

end Forth
end WordDialect
