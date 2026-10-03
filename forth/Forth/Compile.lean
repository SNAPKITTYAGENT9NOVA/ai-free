import Forth.Semantics
import WordIR

/-!
# Forth.Compile

Lowering of Forth to Universal Word IR. Forth's data stack *is* the IR data stack, so the
stack words map one-to-one; only comparisons need more than one instruction, because Forth
true is `-1` while `CMP` yields `1`.
-/

namespace WordDialect
namespace Forth

open IR

/-- `CMP c` gives 1/0; `0 - x` turns that into Forth's -1/0. -/
def cmpFlagCode {n : Nat} (c : Cond) : List (Instr n) := [.cmp c, .word 0#n, .swap, .sub]

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
  | .fetch => [.load]
  | .store => [.store]

def compile {n : Nat} : Block → Frag n
  | .nil => Frag.empty
  | .op o rest => (Frag.ofCode (compileOp o)).seq (compile rest)
  | .ite t e rest => (Frag.ite (compile t) (compile e)).seq (compile rest)
  | .untilL body rest => (Frag.untilLoop (compile body)).seq (compile rest)

/-- A complete program: the block placed at address 0, followed by `HALT`. -/
def compileProgram {n : Nat} (b : Block) : Prog n := (compile b).emit 0 ++ [.halt]

end Forth
end WordDialect
