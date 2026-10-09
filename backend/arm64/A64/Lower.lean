import A64.Isa

/-!
# A64.Lower

Lowering of Universal Word IR (64-bit words) to AArch64.

Runtime conventions (all fixed here; the assembly runtime in `A64.Emit` establishes them):

| register | role |
|----------|------|
| `x19`    | data-stack pointer; the stack grows downward, `[x19]` is the top, empty = `dEnd` |
| `x20`    | base of the virtual register file, cell `r` at `x20 + 8r` |
| `x21`    | base of IR memory; IR word address `a` is at `x21 + 8a` |
| `x22`    | the empty return stack (`x23` at entry) |
| `x23`    | return-stack pointer; grows downward, `[x23]` is the top return address |
| `x24`    | auxiliary-stack pointer; grows downward, `[x24]` is the top, empty = `aEnd` |
| `x9 x10 x11 x12` | scratch; `x30` is written by `call` and `ret` |

IR `call`/`ret` are the model's `call`/`ret` (fixed sequences on the `x23` stack, see `A64.Isa`). IR memory is valid exactly on `[0, memSize)`; every
`load`/`store` is bounds-checked, so an invalid address traps as in the IR semantics. Operand
counts are checked against `dEnd` before every instruction that pops, so stack underflow
traps as in the IR semantics. Every instruction that grows the data stack first checks
`x19 ≥ dBase + 8`, and `call` first checks `x23 ≥ x22 - (8 rcap - 16)`; on overflow the code
exits 6 (`exitOvf`). `tor` likewise checks `x24 ≥ aBase + 8` before growing the auxiliary
stack, and `fromr`/`rfetch` trap `returnUnderflow` when `x24 = aEnd` (empty). IR stacks are unbounded, so this exit has no IR counterpart: it reports that
the run exceeded the target's stack capacity.

Every instruction's code has a size that depends only on the instruction, so jump targets are
absolute code indices computed from prefix sums (`offs`). One definition serves both the
model and the assembly text.
-/

namespace WordDialect
namespace A64

open Reg

structure Layout where
  dEnd : W
  memSize : Nat
  dLim : W        -- `dBase + 8`: the data stack has room for one more word iff `x19 ≥ dLim`
  rGap : W        -- `8 rcap - 16`: a call has room iff `x23 ≥ x22 - rGap`
  aEnd : W        -- empty auxiliary stack: `x24 = aEnd`
  aLim : W        -- `aBase + 8`: the auxiliary stack has room for one more word iff `x24 ≥ aLim`

/-- Stack-underflow guard for `k` operands. -/
def uf (L : Layout) (k base : Nat) : List (Instr Nat) :=
  if k = 0 then []
  else [.movImm x9 (L.dEnd - BitVec.ofNat 64 (8 * k)), .cmp x19 x9, .jcc .be (base + 4),
        .exitTrap .stackUnderflow]

def ufSize (k : Nat) : Nat := if k = 0 then 0 else 4

/-- Data-stack overflow guard: exit 6 unless one more word fits. -/
def ovfD (L : Layout) (base : Nat) : List (Instr Nat) :=
  [.movImm x9 L.dLim, .cmp x19 x9, .jcc .ae (base + 4), .exitOvf]

/-- Return-stack overflow guard: exit 6 unless a call has room on the return stack. -/
def ovfR (L : Layout) (base : Nat) : List (Instr Nat) :=
  [.movRR x9 x22, .movImm x10 L.rGap, .sub x9 x10, .cmp x23 x9, .jcc .ae (base + 6), .exitOvf]

/-- Auxiliary-stack overflow guard: exit 6 unless one more word fits. -/
def ovfA (L : Layout) (base : Nat) : List (Instr Nat) :=
  [.movImm x9 L.aLim, .cmp x24 x9, .jcc .ae (base + 4), .exitOvf]

/-- Empty-auxiliary-stack guard: trap `returnUnderflow` when `x24 = aEnd`. -/
def emptyA (L : Layout) (base : Nat) : List (Instr Nat) :=
  [.movImm x9 L.aEnd, .cmp x24 x9, .jcc .ne (base + 4), .exitTrap .returnUnderflow]

def ccOf : WordDialect.Cond → Cc
  | .eq => .e | .ne => .ne | .ult => .b | .ule => .be | .ugt => .a | .uge => .ae
  | .slt => .l | .sle => .le | .sgt => .g | .sge => .ge

/-- Code size of one IR instruction. -/
def isize : WordDialect.Instr 64 → Nat
  | .word _ | .ptr _ => 7
  | .load => ufSize 1 + 7
  | .store => ufSize 2 + 8
  | .add | .sub | .mul | .and | .or | .xor => ufSize 2 + 5
  | .div => ufSize 2 + 8
  | .sdiv => ufSize 2 + 8
  | .not => ufSize 1 + 3
  | .shl | .shr => ufSize 2 + 8
  | .rotl => ufSize 2 + 6
  | .rotr => ufSize 2 + 5
  | .cmp _ => ufSize 2 + 8
  | .select => ufSize 3 + 7
  | .jmp _ => 1
  | .branch _ => ufSize 1 + 4
  | .call _ => 7
  | .ret => 4
  | .push _ => 7
  | .pop _ => ufSize 1 + 3
  | .dup => ufSize 1 + 7
  | .drop => ufSize 1 + 1
  | .swap => ufSize 2 + 4
  | .over => ufSize 2 + 7
  | .rot => ufSize 3 + 6
  | .tor => ufSize 1 + 8
  | .fromr => 12
  | .rfetch => 11
  | .halt => 1

/-- Code for one IR instruction placed at A64 index `base`; `off t` is the A64 index of IR
instruction `t` (clamped to the bad-pc stub for out-of-range targets). -/
def lowerInstr (L : Layout) (base : Nat) (off : Nat → Nat) : WordDialect.Instr 64 → List (Instr Nat)
  | .word w => ovfD L base ++ [.movImm x9 w, .addImm x19 (-8), .store x19 0 x9]
  | .ptr p => ovfD L base ++ [.movImm x9 p.toWord, .addImm x19 (-8), .store x19 0 x9]
  | .load =>
    let b0 := base + ufSize 1
    uf L 1 base ++
      [.load x9 x19 0, .movImm x10 (BitVec.ofNat 64 L.memSize), .cmp x9 x10,
       .jcc .b (b0 + 5), .exitTrap .badAddress, .loadIdx x9 x21 x9, .store x19 0 x9]
  | .store =>
    let b0 := base + ufSize 2
    uf L 2 base ++
      [.load x9 x19 0, .load x10 x19 8, .movImm x11 (BitVec.ofNat 64 L.memSize), .cmp x9 x11,
       .jcc .b (b0 + 6), .exitTrap .badAddress, .storeIdx x21 x9 x10, .addImm x19 16]
  | .add => uf L 2 base ++ [.load x10 x19 0, .load x9 x19 8, .add x9 x10, .store x19 8 x9, .addImm x19 8]
  | .sub => uf L 2 base ++ [.load x10 x19 0, .load x9 x19 8, .sub x9 x10, .store x19 8 x9, .addImm x19 8]
  | .mul => uf L 2 base ++ [.load x10 x19 0, .load x9 x19 8, .mul x9 x10, .store x19 8 x9, .addImm x19 8]
  | .and => uf L 2 base ++ [.load x10 x19 0, .load x9 x19 8, .and x9 x10, .store x19 8 x9, .addImm x19 8]
  | .or => uf L 2 base ++ [.load x10 x19 0, .load x9 x19 8, .or x9 x10, .store x19 8 x9, .addImm x19 8]
  | .xor => uf L 2 base ++ [.load x10 x19 0, .load x9 x19 8, .xor x9 x10, .store x19 8 x9, .addImm x19 8]
  | .div =>
    let b0 := base + ufSize 2
    uf L 2 base ++
      [.load x10 x19 0, .load x9 x19 8, .test x10 x10, .jcc .ne (b0 + 5),
       .exitTrap .divideByZero, .udiv x9 x9 x10, .store x19 8 x9, .addImm x19 8]
  | .sdiv =>
    let b0 := base + ufSize 2
    uf L 2 base ++
      [.load x10 x19 0, .load x9 x19 8, .test x10 x10, .jcc .ne (b0 + 5),
       .exitTrap .divideByZero, .sdiv x9 x9 x10, .store x19 8 x9, .addImm x19 8]
  | .not => uf L 1 base ++ [.load x9 x19 0, .not x9, .store x19 0 x9]
  | .shl =>
    uf L 2 base ++
      [.load x10 x19 0, .load x9 x19 8, .movImm x11 0#64, .shlCl x9, .cmpImm x10 64,
       .cmov .ae x9 x11, .store x19 8 x9, .addImm x19 8]
  | .shr =>
    uf L 2 base ++
      [.load x10 x19 0, .load x9 x19 8, .movImm x11 0#64, .shrCl x9, .cmpImm x10 64,
       .cmov .ae x9 x11, .store x19 8 x9, .addImm x19 8]
  | .rotl =>
    uf L 2 base ++ [.load x10 x19 0, .load x9 x19 8, .neg x10, .rorCl x9, .store x19 8 x9, .addImm x19 8]
  | .rotr => uf L 2 base ++ [.load x10 x19 0, .load x9 x19 8, .rorCl x9, .store x19 8 x9, .addImm x19 8]
  | .cmp c =>
    uf L 2 base ++
      [.load x10 x19 0, .load x9 x19 8, .movImm x11 0#64, .movImm x12 1#64, .cmp x9 x10,
       .cmov (ccOf c) x11 x12, .store x19 8 x11, .addImm x19 8]
  | .select =>
    uf L 3 base ++
      [.load x10 x19 0, .load x9 x19 8, .load x12 x19 16, .test x10 x10, .cmov .ne x9 x12,
       .store x19 16 x9, .addImm x19 16]
  | .jmp t => [.jmp (off t)]
  | .branch t => uf L 1 base ++ [.load x9 x19 0, .addImm x19 8, .test x9 x9, .jcc .ne (off t)]
  | .call t => ovfR L base ++ [.call (off t)]
  | .ret =>
    [.cmp x23 x22, .jcc .ne (base + 3), .exitTrap .returnUnderflow, .ret]
  | .push r => ovfD L base ++ [.load x9 x20 (8 * (r : Int)), .addImm x19 (-8), .store x19 0 x9]
  | .pop r => uf L 1 base ++ [.load x9 x19 0, .addImm x19 8, .store x20 (8 * (r : Int)) x9]
  | .dup =>
    uf L 1 base ++ ovfD L (base + ufSize 1) ++ [.load x9 x19 0, .addImm x19 (-8), .store x19 0 x9]
  | .drop => uf L 1 base ++ [.addImm x19 8]
  | .swap => uf L 2 base ++ [.load x9 x19 0, .load x10 x19 8, .store x19 0 x10, .store x19 8 x9]
  | .over =>
    uf L 2 base ++ ovfD L (base + ufSize 2) ++ [.load x9 x19 8, .addImm x19 (-8), .store x19 0 x9]
  | .rot =>
    uf L 3 base ++
      [.load x9 x19 0, .load x10 x19 8, .load x11 x19 16, .store x19 0 x11, .store x19 8 x9,
       .store x19 16 x10]
  | .tor =>
    uf L 1 base ++ ovfA L (base + ufSize 1) ++
      [.load x9 x19 0, .addImm x19 8, .addImm x24 (-8), .store x24 0 x9]
  | .fromr =>
    emptyA L base ++ ovfD L (base + 4) ++
      [.load x9 x24 0, .addImm x24 8, .addImm x19 (-8), .store x19 0 x9]
  | .rfetch =>
    emptyA L base ++ ovfD L (base + 4) ++ [.load x9 x24 0, .addImm x19 (-8), .store x19 0 x9]
  | .halt => [.exitHalt]

theorem lowerInstr_length (L : Layout) (base : Nat) (off : Nat → Nat) (i : WordDialect.Instr 64) :
    (lowerInstr L base off i).length = isize i := by
  cases i <;> simp [lowerInstr, isize, uf, ufSize, ovfD, ovfR, ovfA, emptyA] <;> (try split) <;> simp

/-- Prefix sums of instruction sizes: `offs p k` is the A64 index of IR instruction `k`.
For `k` past the end it is the index of the final bad-pc stub. -/
def offs (p : Prog 64) (k : Nat) : Nat := ((p.take k).map isize).sum

def lowerGo (L : Layout) (off : Nat → Nat) : Nat → List (WordDialect.Instr 64) → List (Instr Nat)
  | _, [] => [.exitTrap .badPc]
  | b, i :: is => lowerInstr L b off i ++ lowerGo L off (b + isize i) is

/-- The whole program; the last instruction is the bad-pc stub, so jumping past the end of the
IR program traps `badPc` exactly as the IR semantics does. -/
def lowerProg (L : Layout) (p : Prog 64) : List (Instr Nat) := lowerGo L (offs p) 0 p

end A64
end WordDialect
