import BCPL.Semantics

/-!
# BCPL.Compile

Lowering of BCPL to Universal Word IR. There is no BCPL runtime: variables are memory cells
at `addr x`, expressions leave their value on the data stack, and statements leave the data
stack as they found it.
-/

namespace WordDialect
namespace BCPL

open IR

def binCode {n : Nat} : BinOp → List (Instr n)
  | .add => [.add]
  | .sub => [.sub]
  | .mul => [.mul]
  | .div => [.sdiv]
  | .and => [.and]
  | .or => [.or]
  | .neqv => [.xor]
  | .shl => [.shl]
  | .shr => [.shr]
  | .eq => cmpFlagCode .eq
  | .ne => cmpFlagCode .ne
  | .lt => cmpFlagCode .slt
  | .gt => cmpFlagCode .sgt
  | .le => cmpFlagCode .sle
  | .ge => cmpFlagCode .sge

/-- `neg`: compute `0 - v` as `v 0 SWAP SUB`. -/
def unCode {n : Nat} : UnOp → List (Instr n)
  | .neg => [.word 0#n, .swap, .sub]
  | .not => [.not]

def compileE {n : Nat} (addr : Var → Word n) : Expr → List (Instr n)
  | .num z => [.word (BitVec.ofInt n z)]
  | .var x => [.word (addr x), .load]
  | .addrOf x => [.word (addr x)]
  | .rv e => compileE addr e ++ [.load]
  | .un o e => compileE addr e ++ unCode o
  | .bin o a b => compileE addr a ++ compileE addr b ++ binCode o

/-- Right-hand side first, then (for an indirect target) the address, then `STORE`. -/
def assignCode {n : Nat} (addr : Var → Word n) : LVal → Expr → List (Instr n)
  | .var x, e => compileE addr e ++ [.word (addr x), .store]
  | .rv a, e => compileE addr e ++ compileE addr a ++ [.store]

def compile {n : Nat} (addr : Var → Word n) : Stmt → Frag n
  | .skip => Frag.empty
  | .assign l e => Frag.ofCode (assignCode addr l e)
  | .seq a b => (compile addr a).seq (compile addr b)
  | .test c t e => (Frag.ofCode (compileE addr c)).seq (Frag.ite (compile addr t) (compile addr e))
  | .while c body => Frag.whileLoop (Frag.ofCode (compileE addr c)) (compile addr body)

/-- A complete program: the statement at address 0, followed by `HALT`. -/
def compileProgram {n : Nat} (addr : Var → Word n) (s : Stmt) : Prog n :=
  (compile addr s).emit 0 ++ [.halt]

end BCPL
end WordDialect
