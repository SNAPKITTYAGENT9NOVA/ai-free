import WordDialect
import Wasm.Isa

/-!
# Wasm.Lower

Lowering of Universal Word IR (64-bit words) to WebAssembly.

The IR has arbitrary jumps, calls and returns; WebAssembly has structured control. Standard
solution: a dispatch loop. The program is one `loop` whose body is `n + 1` nested blocks with a
`br_table` on the local `pc` at the centre; label `i` of the table leaves block `i`, which
lands on the code for IR instruction `i`. Each instruction's code ends by setting `pc` and
branching back to the loop, or falls through into the next instruction's code. Index `n` is a
bad-pc stub; every jump target is clamped to `n` at lowering time, so a jump past the end traps
`badPc` exactly as in the IR semantics.

Locals: `0 = pc` (i32), `1 = sp` data-stack pointer (i32, grows down, empty = `dEnd`), `2 = rp`
return-stack pointer (i32, grows down, empty = `rEnd`). The register file, IR memory and both stacks
live in linear memory at the static addresses of `Layout`; the operand stack is used only for
temporaries and is empty between IR instructions. `call` pushes the IR index of the return
instruction onto the return stack; `ret` pops it.

Every `load`/`store` is bounds-checked against the IR memory size, and every popping instruction
checks the operand count against `dEnd`, so traps match the IR semantics.
-/

namespace WordDialect
namespace Wasm

structure Layout where
  dEnd : Nat      -- data stack: empty at `dEnd`
  rEnd : Nat      -- return stack: empty at `rEnd`
  rf : Nat        -- virtual register file, cell `r` at `rf + 8r`
  mb : Nat        -- IR memory, word `a` at `mb + 8a`
  M : Nat         -- IR memory size in words

def pcL : Nat := 0
def spL : Nat := 1
def rpL : Nat := 2

def i32c (n : Nat) : WI := .i32const (BitVec.ofNat 32 n)
def i64c (n : Nat) : WI := .i64const (BitVec.ofNat 64 n)

def spAdd (d : Nat) : List WI := [.localGet spL, i32c d, .i32add, .localSet spL]
def spSub (d : Nat) : List WI := [.localGet spL, i32c d, .i32sub, .localSet spL]

/-- Operand-count guard for `k` operands: trap `stackUnderflow` unless `sp ≤ dEnd - 8k`. -/
def uf (L : Layout) (k : Nat) : List WI :=
  if k = 0 then [] else [.localGet spL, i32c (L.dEnd - 8 * k), .i32gtu, .ite [.exitTrap 1]]

/-- Push `v` (a word whose bits are on the operand stack as the last thing in `val`). -/
def pushWith (val : List WI) : List WI :=
  spSub 8 ++ [.localGet spL] ++ val ++ [.i64store 0]

/-- `[sp + off]` as an `i64` on the operand stack. -/
def ldS (off : Nat) : List WI := [.localGet spL, .i64load off]

/-- Address of IR memory word `[sp+0]`, bounds-checked first. -/
def memAddr (L : Layout) : List WI :=
  ldS 0 ++ [.i64const (BitVec.ofNat 64 L.M), .i64geu, .ite [.exitTrap 2]] ++
    ldS 0 ++ [.i32wrap, i32c 3, .i32shl, i32c L.mb, .i32add]

def jumpTo (n t dep : Nat) : List WI := [i32c (min t n), .localSet pcL, .br dep]

/-- Binary operation `f` on `[sp+8] (op) [sp+0]`, result in `[sp+8]`, then pop one. -/
def binBody (op : List WI) : List WI :=
  [.localGet spL] ++ ldS 8 ++ ldS 0 ++ op ++ [.i64store 8] ++ spAdd 8

def binOp (L : Layout) (op : List WI) : List WI :=
  uf L 2 ++ binBody op

/-- Shifts: a count of 64 or more yields 0. -/
def shiftOp (L : Layout) (op : WI) : List WI :=
  uf L 2 ++ [.localGet spL, .i64const 0#64] ++ ldS 8 ++ ldS 0 ++ [op] ++
    ldS 0 ++ [.i64const 64#64, .i64geu, .select, .i64store 8] ++ spAdd 8

def cmpOp : WordDialect.Cond → WI
  | .eq => .i64eq | .ne => .i64ne | .ult => .i64ltu | .ule => .i64leu | .ugt => .i64gtu
  | .uge => .i64geu | .slt => .i64lts | .sle => .i64les | .sgt => .i64gts | .sge => .i64ges

/-- Code for IR instruction number `k` of a program of `n` instructions; `n - k` is the label
depth of the dispatch loop from the top level of this code. -/
def lowerInstr (L : Layout) (n k : Nat) : WordDialect.Instr 64 → List WI
  | .word w => pushWith [.i64const w]
  | .ptr p => pushWith [.i64const p.toWord]
  | .load =>
    uf L 1 ++ [.localGet spL] ++ memAddr L ++ [.i64load 0, .i64store 0]
  | .store =>
    uf L 2 ++ memAddr L ++ ldS 8 ++ [.i64store 0] ++ spAdd 16
  | .add => binOp L [.i64add]
  | .sub => binOp L [.i64sub]
  | .mul => binOp L [.i64mul]
  | .and => binOp L [.i64and]
  | .or => binOp L [.i64or]
  | .xor => binOp L [.i64xor]
  | .div =>
    uf L 2 ++ ldS 0 ++ [.i64eqz, .ite [.exitTrap 3]] ++ binBody [.i64divu]
  | .sdiv =>
    uf L 2 ++ ldS 0 ++ [.i64eqz, .ite [.exitTrap 3]] ++
      [.localGet spL, .i64const 0#64] ++ ldS 8 ++ [.i64sub] ++
      ldS 8 ++ [.i64const 1#64] ++ ldS 0 ++ ldS 0 ++ [.i64const (BitVec.allOnes 64), .i64eq, .select,
        .i64divs] ++ ldS 0 ++ [.i64const (BitVec.allOnes 64), .i64eq, .select, .i64store 8] ++ spAdd 8
  | .not => uf L 1 ++ [.localGet spL] ++ ldS 0 ++ [.i64const (BitVec.allOnes 64), .i64xor, .i64store 0]
  | .shl => shiftOp L .i64shl
  | .shr => shiftOp L .i64shru
  | .rotl => binOp L [.i64rotl]
  | .rotr => binOp L [.i64rotr]
  | .cmp c => binOp L [cmpOp c, .i64extu]
  | .select =>
    uf L 3 ++ [.localGet spL] ++ ldS 16 ++ ldS 8 ++ ldS 0 ++ [.i64const 0#64, .i64ne, .select,
      .i64store 16] ++ spAdd 16
  | .jmp t => jumpTo n t (n - k)
  | .branch t =>
    uf L 1 ++ ldS 0 ++ spAdd 8 ++ [.i64const 0#64, .i64ne, .ite (jumpTo n t (n - k + 1))]
  | .call t =>
    [.localGet rpL, i32c 8, .i32sub, .localSet rpL, .localGet rpL, i64c (k + 1), .i64store 0] ++
      jumpTo n t (n - k)
  | .ret =>
    [.localGet rpL, i32c L.rEnd, .i32eq, .ite [.exitTrap 5], .localGet rpL, .i64load 0, .i32wrap,
      .localSet pcL, .localGet rpL, i32c 8, .i32add, .localSet rpL, .br (n - k)]
  | .push r => pushWith [i32c (L.rf + 8 * r), .i64load 0]
  | .pop r => uf L 1 ++ [i32c (L.rf + 8 * r)] ++ ldS 0 ++ [.i64store 0] ++ spAdd 8
  | .dup => uf L 1 ++ spSub 8 ++ [.localGet spL] ++ ldS 8 ++ [.i64store 0]
  | .drop => uf L 1 ++ spAdd 8
  | .swap => uf L 2 ++ [.localGet spL] ++ ldS 8 ++ [.localGet spL] ++ ldS 0 ++ [.i64store 8, .i64store 0]
  | .over => uf L 2 ++ spSub 8 ++ [.localGet spL, .localGet spL, .i64load 16, .i64store 0]
  | .rot =>
    uf L 3 ++ [.localGet spL] ++ ldS 16 ++ [.localGet spL] ++ ldS 0 ++ [.localGet spL] ++ ldS 8 ++
      [.i64store 16, .i64store 8, .i64store 0]
  | .halt => [.exitHalt]

/-- Code for IR instruction `k`, or the bad-pc stub when `k` is past the end. -/
def instrCode (L : Layout) (p : Prog 64) (k : Nat) : List WI :=
  match p[k]? with
  | some i => lowerInstr L p.length k i
  | none => [.exitTrap 4]

/-- Body of block `L_j`: the dispatch (`j = 0`) or block `L_{j-1}` followed by the code of
instruction `j - 1`. -/
def nestC (n : Nat) (code : Nat → List WI) : Nat → List WI
  | 0 => [.localGet pcL, .brTable (List.range n) n]
  | j + 1 => .block (nestC n code j) :: code j

/-- The whole program: one dispatch loop. -/
def lowerProg (L : Layout) (p : Prog 64) : List WI :=
  [.loop (.block (nestC p.length (instrCode L p) p.length) :: instrCode L p p.length)]

end Wasm
end WordDialect
