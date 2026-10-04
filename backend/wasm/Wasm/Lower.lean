import WordDialect
import Wasm.Isa

/-!
# Wasm.Lower

Lowering of Universal Word IR (64-bit words) to WebAssembly.

The IR has arbitrary jumps, calls and returns; WebAssembly has structured control. Solution: every
IR instruction `k` becomes its own function `f_k : () → i32` that performs the instruction and
returns the index of the next IR instruction; the module is a dispatch loop

    loop { pc := call_indirect (table[pc]) ; br 0 }

Function `n` (past the last instruction) is the bad-pc stub. Every jump target is clamped to `n` at
lowering time, so a jump past the end traps `badPc` exactly as in the IR semantics.

Globals: `0 = pc` (i32), `1 = sp` data-stack pointer (i32, grows down, empty = `dEnd`), `2 = rp`
return-stack pointer (i32, grows down, empty = `rEnd`), `3 = ap` auxiliary-stack pointer (i32, grows
down, empty = `aEnd`). The register file, IR memory and the three stacks live in linear memory at the
static addresses of `Layout`; the operand stack is used only for temporaries. `call` pushes the IR
index of the return instruction onto the return stack; `ret` pops it. `tor`/`fromr`/`rfetch` move or
copy words between the data stack and the auxiliary stack; taking from an empty auxiliary stack
exits 5 (`returnUnderflow`), as `ret` does on an empty return stack.

Every `load`/`store` is bounds-checked against the IR memory size, and every popping instruction
checks the operand count against `dEnd`, so traps match the IR semantics. Every instruction that
grows the data stack checks for room above `dBase`, `call` checks for room above `rBase`, and `tor`
checks for room above `aBase`; on
overflow the module exits with code 6. The IR has unbounded stacks, so this exit has no IR
counterpart: it reports that the run exceeded the target's stack capacity.
-/

namespace WordDialect
namespace Wasm

structure Layout where
  dEnd : Nat      -- data stack: empty at `dEnd`
  rEnd : Nat      -- return stack: empty at `rEnd`
  rf : Nat        -- virtual register file, cell `r` at `rf + 8r`
  mb : Nat        -- IR memory, word `a` at `mb + 8a`
  M : Nat         -- IR memory size in words
  dBase : Nat     -- data stack: full at `dBase`
  rBase : Nat     -- return stack: full at `rBase`
  aEnd : Nat      -- auxiliary stack: empty at `aEnd`
  aBase : Nat     -- auxiliary stack: full at `aBase`

def pcG : Nat := 0
def spG : Nat := 1
def rpG : Nat := 2
def apG : Nat := 3

def i32c (n : Nat) : WI := .i32const (BitVec.ofNat 32 n)
def i64c (n : Nat) : WI := .i64const (BitVec.ofNat 64 n)

def spAdd (d : Nat) : List WI := [.globalGet spG, i32c d, .i32add, .globalSet spG]
def spSub (d : Nat) : List WI := [.globalGet spG, i32c d, .i32sub, .globalSet spG]

/-- Operand-count guard for `k` operands: trap `stackUnderflow` unless `sp ≤ dEnd - 8k`. -/
def uf (L : Layout) (k : Nat) : List WI :=
  if k = 0 then [] else [.globalGet spG, i32c (L.dEnd - 8 * k), .i32gtu, .ite [.exitTrap 1]]

/-- Overflow guard on the stack whose pointer is global `g`: exit 6 unless one more word fits,
i.e. unless `base + 8 ≤ ptr`. -/
def ovf (g base : Nat) : List WI := [i32c (base + 8), .globalGet g, .i32gtu, .ite [.exitTrap 6]]

/-- Push the word computed by `val`. -/
def pushWith (val : List WI) : List WI :=
  spSub 8 ++ [.globalGet spG] ++ val ++ [.i64store 0]

/-- `[sp + off]` as an `i64` on the operand stack. -/
def ldS (off : Nat) : List WI := [.globalGet spG, .i64load off]

/-- Address of IR memory word `[sp+0]`, bounds-checked first. -/
def memAddr (L : Layout) : List WI :=
  ldS 0 ++ [.i64const (BitVec.ofNat 64 L.M), .i64geu, .ite [.exitTrap 2]] ++
    ldS 0 ++ [.i32wrap, i32c 3, .i32shl, i32c L.mb, .i32add]

/-- Binary operation on `[sp+8] (op) [sp+0]`, result in `[sp+8]`, then pop one. -/
def binBody (op : List WI) : List WI :=
  [.globalGet spG] ++ ldS 8 ++ ldS 0 ++ op ++ [.i64store 8] ++ spAdd 8

def binOp (L : Layout) (op : List WI) : List WI := uf L 2 ++ binBody op

/-- Shifts: a count of 64 or more yields 0. -/
def shiftBody (op : WI) : List WI :=
  [.globalGet spG, .i64const 0#64] ++ ldS 8 ++ ldS 0 ++ [op] ++
    ldS 0 ++ [.i64const 64#64, .i64geu, .select, .i64store 8] ++ spAdd 8

def shiftOp (L : Layout) (op : WI) : List WI := uf L 2 ++ shiftBody op

/-- Trap `divideByZero` when the divisor `[sp+0]` is zero. -/
def zeroGuard : List WI := ldS 0 ++ [.i64eqz, .ite [.exitTrap 3]]

/-- Signed division of `[sp+8]` by `[sp+0]` (non-zero), result in `[sp+8]`, pop one. A divisor of -1
yields `0 - a` and the divisor passed to `i64.div_s` is then 1, so the spec's `INT64_MIN / -1` trap
cannot occur. -/
def sdivBody : List WI :=
  [.globalGet spG, .i64const 0#64] ++ ldS 8 ++ [.i64sub] ++
    ldS 8 ++ [.i64const 1#64] ++ ldS 0 ++ ldS 0 ++ [.i64const (BitVec.allOnes 64), .i64eq, .select,
      .i64divs] ++ ldS 0 ++ [.i64const (BitVec.allOnes 64), .i64eq, .select, .i64store 8] ++
    spAdd 8

def cmpOp : WordDialect.Cond → WI
  | .eq => .i64eq | .ne => .i64ne | .ult => .i64ltu | .ule => .i64leu | .ugt => .i64gtu
  | .uge => .i64geu | .slt => .i64lts | .sle => .i64les | .sgt => .i64gts | .sge => .i64ges

/-- Code for IR instruction number `k` of a program of `n` instructions: performs it and leaves
the next instruction index on the operand stack. -/
def lowerInstr (L : Layout) (n k : Nat) : WordDialect.Instr 64 → List WI
  | .word w => ovf spG L.dBase ++ pushWith [.i64const w] ++ [i32c (k + 1)]
  | .ptr p => ovf spG L.dBase ++ pushWith [.i64const p.toWord] ++ [i32c (k + 1)]
  | .load =>
    uf L 1 ++ [.globalGet spG] ++ memAddr L ++ [.i64load 0, .i64store 0] ++ [i32c (k + 1)]
  | .store =>
    uf L 2 ++ memAddr L ++ ldS 8 ++ [.i64store 0] ++ spAdd 16 ++ [i32c (k + 1)]
  | .add => binOp L [.i64add] ++ [i32c (k + 1)]
  | .sub => binOp L [.i64sub] ++ [i32c (k + 1)]
  | .mul => binOp L [.i64mul] ++ [i32c (k + 1)]
  | .and => binOp L [.i64and] ++ [i32c (k + 1)]
  | .or => binOp L [.i64or] ++ [i32c (k + 1)]
  | .xor => binOp L [.i64xor] ++ [i32c (k + 1)]
  | .div => uf L 2 ++ zeroGuard ++ binBody [.i64divu] ++ [i32c (k + 1)]
  | .sdiv => uf L 2 ++ zeroGuard ++ sdivBody ++ [i32c (k + 1)]
  | .not =>
    uf L 1 ++ [.globalGet spG] ++ ldS 0 ++ [.i64const (BitVec.allOnes 64), .i64xor, .i64store 0] ++
      [i32c (k + 1)]
  | .shl => shiftOp L .i64shl ++ [i32c (k + 1)]
  | .shr => shiftOp L .i64shru ++ [i32c (k + 1)]
  | .rotl => binOp L [.i64rotl] ++ [i32c (k + 1)]
  | .rotr => binOp L [.i64rotr] ++ [i32c (k + 1)]
  | .cmp c => binOp L [cmpOp c, .i64extu] ++ [i32c (k + 1)]
  | .select =>
    uf L 3 ++ [.globalGet spG] ++ ldS 16 ++ ldS 8 ++ ldS 0 ++ [.i64const 0#64, .i64ne, .select,
      .i64store 16] ++ spAdd 16 ++ [i32c (k + 1)]
  | .jmp t => [i32c (min t n)]
  | .branch t =>
    uf L 1 ++ [i32c (min t n), i32c (k + 1)] ++ ldS 0 ++ [.i64const 0#64, .i64ne, .select] ++ spAdd 8
  | .call t =>
    ovf rpG L.rBase ++ [.globalGet rpG, i32c 8, .i32sub, .globalSet rpG, .globalGet rpG, i64c (k + 1), .i64store 0,
      i32c (min t n)]
  | .ret =>
    [.globalGet rpG, i32c L.rEnd, .i32eq, .ite [.exitTrap 5], .globalGet rpG, .i64load 0, .i32wrap,
      .globalGet rpG, i32c 8, .i32add, .globalSet rpG]
  | .push r => ovf spG L.dBase ++ pushWith [i32c (L.rf + 8 * r), .i64load 0] ++ [i32c (k + 1)]
  | .pop r =>
    uf L 1 ++ [i32c (L.rf + 8 * r)] ++ ldS 0 ++ [.i64store 0] ++ spAdd 8 ++ [i32c (k + 1)]
  | .dup => uf L 1 ++ ovf spG L.dBase ++ spSub 8 ++ [.globalGet spG] ++ ldS 8 ++ [.i64store 0] ++ [i32c (k + 1)]
  | .drop => uf L 1 ++ spAdd 8 ++ [i32c (k + 1)]
  | .swap =>
    uf L 2 ++ [.globalGet spG] ++ ldS 8 ++ [.globalGet spG] ++ ldS 0 ++ [.i64store 8, .i64store 0] ++
      [i32c (k + 1)]
  | .over =>
    uf L 2 ++ ovf spG L.dBase ++ spSub 8 ++ [.globalGet spG, .globalGet spG, .i64load 16, .i64store 0] ++ [i32c (k + 1)]
  | .rot =>
    uf L 3 ++ [.globalGet spG] ++ ldS 16 ++ [.globalGet spG] ++ ldS 0 ++ [.globalGet spG] ++ ldS 8 ++
      [.i64store 16, .i64store 8, .i64store 0] ++ [i32c (k + 1)]
  | .tor =>
    uf L 1 ++ ovf apG L.aBase ++ [.globalGet apG, i32c 8, .i32sub, .globalSet apG, .globalGet apG] ++
      ldS 0 ++ [.i64store 0] ++ spAdd 8 ++ [i32c (k + 1)]
  | .fromr =>
    [.globalGet apG, i32c L.aEnd, .i32eq, .ite [.exitTrap 5]] ++ ovf spG L.dBase ++
      pushWith [.globalGet apG, .i64load 0] ++ [.globalGet apG, i32c 8, .i32add, .globalSet apG] ++
      [i32c (k + 1)]
  | .rfetch =>
    [.globalGet apG, i32c L.aEnd, .i32eq, .ite [.exitTrap 5]] ++ ovf spG L.dBase ++
      pushWith [.globalGet apG, .i64load 0] ++ [i32c (k + 1)]
  | .halt => [.exitHalt]

/-- Function `k`: the code of IR instruction `k`, or the bad-pc stub past the end. -/
def instrCode (L : Layout) (p : Prog 64) (k : Nat) : List WI :=
  match p[k]? with
  | some i => lowerInstr L p.length k i
  | none => [.exitTrap 4]

/-- The function table: one function per IR instruction, then the bad-pc stub. -/
def funcsOf (L : Layout) (p : Prog 64) : Funcs :=
  (List.range (p.length + 1)).map (instrCode L p)

/-- The module's start function: the dispatch loop. -/
def mainBody : List WI :=
  [.loop [.globalGet pcG, .callIndirect, .globalSet pcG, .br 0]]

end Wasm
end WordDialect
